// Shrink each face away from its shared edges. Corner index becomes the new vertex index.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types_int16 : require

const uint WEDGES_GROUP_SIZE = 256u;
const uint NONE = 0xFFFFFFFFu;

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	float shrink; // 0 = unchanged, 1 = moved towards face center
	uint out_color_offset;
	uint out_attribute_stride;
};

layout(set = 0, binding = 0, scalar) restrict readonly buffer InVertexBuffer {
	vec3 in_positions[];
};

layout(set = 0, binding = 1, scalar) restrict readonly buffer InIndexBuffer {
	u16vec3 in_faces[];
};

layout(set = 1, binding = 0, scalar) restrict writeonly buffer OutVertexBuffer {
	vec3 out_positions[];
};

layout(set = 1, binding = 1, scalar) restrict writeonly buffer OutIndexBuffer {
	uint16_t out_faces[];
};

layout(set = 1, binding = 2, std430) restrict writeonly buffer OutAttributeBuffer {
	uint out_attributes[];
};

layout(set = 2, binding = 0, scalar) restrict buffer SharedEdgeBuffer {
	uint shared_count;
	uvec2 shared_edges[]; // this face's corner, matching corner on the neighbour face
};

layout(set = 3, binding = 0, std430) restrict buffer DispatchBuffer {
	uvec3 dispatch; // indirect args for wedge.glsl
};

layout(set = 4, binding = 0, std430) restrict buffer DebugBuffer {
	float debug_out[12];
};

uint next_corner(uint corner) {
	return (corner + 1u) % 3u;
}

// Find the twin corner for each of face's 3 edges.
// Return actual corner indices.
uvec3 find_twins(uint face, uint in_face_count) {
	uvec3 twins = uvec3(NONE);

	vec3 self_pos[3] = vec3[](
		in_positions[in_faces[face][0]],
		in_positions[in_faces[face][1]],
		in_positions[in_faces[face][2]]
	);

	// Degenerate self-edges never match anything - decide once, not per candidate face
	bvec3 self_degen = bvec3(
		self_pos[0] == self_pos[1],
		self_pos[1] == self_pos[2],
		self_pos[2] == self_pos[0]
	);

	uint found = 0u;
	uint remaining = uint(!self_degen[0]) + uint(!self_degen[1]) + uint(!self_degen[2]);

	if (remaining == 0u) return twins; // Face degenerate

	// Compare against every other face's 3 edges
	for (uint f = 0u; f < in_face_count && found < remaining; f++) {
		if (f == face) continue; // Don't compare with self

		vec3 other_pos[3] = vec3[](
			in_positions[in_faces[f][0]],
			in_positions[in_faces[f][1]],
			in_positions[in_faces[f][2]]
		);

		bvec3 other_degen = bvec3(
			other_pos[0] == other_pos[1],
			other_pos[1] == other_pos[2],
			other_pos[2] == other_pos[0]
		);

		for (uint c = 0u; c < 3u; c++) {
			if (self_degen[c] || twins[c] != NONE) continue; // Already resolved or invalid

			uint next = next_corner(c);

			for (uint oc = 0u; oc < 3u; oc++) {
				if (other_degen[oc]) continue;

				uint onext = next_corner(oc);

				// Correctly-wound adjacent triangles run a shared edge in opposite
				// directions, so the match is self[c]==other[next], self[next]==other[c]
				if (self_pos[c] == other_pos[onext] && self_pos[next] == other_pos[oc]) {
					twins[c] = f * 3u + oc;
					found++;
					break; // This edge can only have one twin - stop checking other corners of f
				}
			}
		}
	}

	return twins;
}

// Each corner retreats along its two edges (or between, towards face center) based on whether edge is shared
vec3 inset_corner(vec3 positions[3], uint c, bvec3 is_shared) {
	uint next = next_corner(c);
	uint prev = (c + 2u) % 3u;

	bool next_shared = is_shared[c];
	bool prev_shared = is_shared[prev];

	if (!next_shared && !prev_shared) {
		return positions[c];
	}

	float bias = next_shared && prev_shared ? 0.5 : (next_shared ? 1.0 : 0.0);
	return mix(positions[c], mix(positions[next], positions[prev], bias), shrink);
}

void write_out_color(uint out_index, vec4 color) {
	uint word = (out_color_offset + out_index * out_attribute_stride) / 4u;
	out_attributes[word] = packUnorm4x8(color);
}

void main() {
	uint face = gl_GlobalInvocationID.x + gl_GlobalInvocationID.y * (gl_NumWorkGroups.x * gl_WorkGroupSize.x);
	uint in_face_count = uint(in_faces.length());

	if (face >= in_face_count) return;

	vec3 positions[3] = vec3[](
		in_positions[in_faces[face][0]],
		in_positions[in_faces[face][1]],
		in_positions[in_faces[face][2]]
	);

	uvec3 twins = find_twins(face, in_face_count);
	bvec3 is_shared = bvec3(twins[0] != NONE, twins[1] != NONE, twins[2] != NONE);

	// Corner index becomes this vertex's new position in the output buffer
	uint base = face * 3u;
	for (uint c = 0u; c < 3u; c++) {
		out_positions[base + c] = inset_corner(positions, c, is_shared);
		out_faces[base + c] = uint16_t(base + c);

		// Debug visualization: red where this corner touches a shared edge
		write_out_color(base + c, is_shared[c] ? vec4(1, 0, 0, 1) : vec4(1));
	}

	// Collect this face's edges locally first, so only one atomic reserves the whole
	// block instead of one atomic per edge
	uint local_count = 0u;
	uvec2 local_edges[3];

	for (uint c = 0u; c < 3u; c++) {
		if (!is_shared[c]) continue;

		uint self_corner = base + c;
		uint twin_corner = twins[c];

		// Both faces of a shared edge find each other now, so only the lower-indexed
		// corner registers, to avoid recording each edge twice
		if (self_corner > twin_corner) continue;

		local_edges[local_count] = uvec2(self_corner, twin_corner);
		local_count++;
	}

	if (local_count == 0u) return;

	uint slot = atomicAdd(shared_count, local_count);
	for (uint i = 0u; i < local_count; i++) {
		shared_edges[slot + i] = local_edges[i];
	}

	uint local_max = slot + local_count;
	atomicMax(dispatch.x, (local_max + WEDGES_GROUP_SIZE - 1u) / WEDGES_GROUP_SIZE);
	dispatch.y = 1u;
	dispatch.z = 1u;
}
