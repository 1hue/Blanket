// Shrink each face away from its shared edges. Corner index becomes the new vertex index.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types_int16 : require

const uint NONE = 0xFFFFFFFFu;
const uint WEDGES_GROUP_SIZE = 256u;

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	float shrink; // 0 = unchanged, 1 = collapsed onto the opposite corner
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
	uvec4 shared_edges[]; // Vertex indices: this face's edge, then the twin's
};

layout(set = 3, binding = 0, std430) restrict buffer DispatchBuffer {
	uvec3 dispatch; // Indirect args for wedge.glsl
};

uint next_corner(uint corner) {
	return (corner + 1u) % 3u;
}

// Edge e runs from corner e to the next corner round
uvec2 edge_verts(uint face, uint e) {
	return uvec2(in_faces[face][e], in_faces[face][next_corner(e)]);
}

mat2x3 edge_pos(uint face, uint e) {
	uvec2 verts = edge_verts(face, e);
	return mat2x3(in_positions[verts[0]], in_positions[verts[1]]);
}

mat3 face_pos(uint face) {
	uvec3 verts = uvec3(in_faces[face]);
	return mat3(in_positions[verts.x], in_positions[verts.y], in_positions[verts.z]);
}

bool is_degen(mat2x3 edge) {
	return edge[0] == edge[1];
}

// Correctly wound neighbours run their shared edge in opposite directions.
// A degenerate edge can never satisfy this, so it needs no separate check.
bool is_twin(mat2x3 edge, mat2x3 other) {
	return (
		(edge[0] == other[1] && edge[1] == other[0]) ||
		(edge[1] == other[0] && edge[0] == other[1])
	);
}

// Twin corner index per edge, or NONE where the edge is a boundary
uvec3 find_twins(uint face, uint face_count) {
	uvec3 twins = uvec3(NONE);
	mat2x3 edges[3] = mat2x3[](edge_pos(face, 0u), edge_pos(face, 1u), edge_pos(face, 2u));

	for (uint f = 0u; f < face_count; f++) {
		if (f == face) continue; // Don't compare with self

		// Fetch each candidate edge once, test all three of ours against it
		for (uint o = 0u; o < 3u; o++) {
			mat2x3 other = edge_pos(f, o);
			if (is_degen(other)) continue;

			for (uint e = 0u; e < 3u; e++) {
				if (twins[e] == NONE && is_twin(edges[e], other)) {
					twins[e] = f * 3u + o;
				}
			}
		}

		if (all(notEqual(twins, uvec3(NONE)))) break; // Nothing left to look for
	}

	return twins;
}

// Edge e sits opposite corner e+2, so a corner retreats toward the corner opposite
// whichever of its two edges is shared - or between both, when both are.
vec3 inset_corner(mat3 face, uint c, bvec3 is_shared) {
	uint next = next_corner(c);
	uint prev = (c + 2u) % 3u;

	bool to_prev = is_shared[c]; // Edge c is shared, so retreat away from it
	bool to_next = is_shared[prev]; // Edge prev is shared

	if (!to_prev && !to_next) return face[c];

	vec3 target = to_prev && to_next
	? mix(face[next], face[prev], 0.5)
	: (to_prev ? face[prev] : face[next]);

	return mix(face[c], target, shrink);
}

void write_out_color(uint out_index, vec4 color) {
	uint word = (out_color_offset + out_index * out_attribute_stride) / 4u;
	out_attributes[word] = packUnorm4x8(color);
}

void main() {
	uint face = gl_GlobalInvocationID.x + gl_GlobalInvocationID.y * (gl_NumWorkGroups.x * gl_WorkGroupSize.x);
	uint face_count = uint(in_faces.length());

	if (face >= face_count) return;

	uvec3 twins = find_twins(face, face_count);
	bvec3 is_shared = notEqual(twins, uvec3(NONE));

	// Corner index becomes this vertex's index in the output buffer
	mat3 positions = face_pos(face);
	uint base = face * 3u;

	for (uint c = 0u; c < 3u; c++) {
		out_positions[base + c] = inset_corner(positions, c, is_shared);
		out_faces[base + c] = uint16_t(base + c);

		// Debug visualization: red where this corner touches a shared edge
		write_out_color(base + c, is_shared[c] ? vec4(1, 0, 0, 1) : vec4(1));
	}

	// Both faces of an edge find each other, so only the lower corner registers it.
	// Gather first, so the whole face costs one atomic rather than one per edge.
	uvec4 pending[3];
	uint pending_count = 0u;

	for (uint e = 0u; e < 3u; e++) {
		uint twin = twins[e];
		if (twin == NONE || base + e > twin) continue;

		pending[pending_count++] = uvec4(edge_verts(face, e), edge_verts(twin / 3u, twin % 3u));
	}

	if (pending_count == 0u) return;

	uint slot = atomicAdd(shared_count, pending_count);
	for (uint i = 0u; i < pending_count; i++) {
		shared_edges[slot + i] = pending[i];
	}

	atomicMax(dispatch.x, (slot + pending_count + WEDGES_GROUP_SIZE - 1u) / WEDGES_GROUP_SIZE);
	dispatch.y = 1u;
	dispatch.z = 1u;
}
