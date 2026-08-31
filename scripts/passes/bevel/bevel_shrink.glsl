// Retract each selected face from its shared edges, and record those edges for fill.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types : require

const uint NONE = 0xFFFFFFFFu;

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	float shrink; // 0 = unchanged, 1 = collapsed onto the opposite corner
	uint selected_vertex_count; // Where the retracted corners begin
	uint selected_face_count;
};

layout(set = 0, binding = 0, scalar) restrict buffer OutVertexBuffer {
	vec3 out_positions[];
};

layout(set = 0, binding = 1, scalar) restrict buffer OutIndexBuffer {
	u16vec3 out_faces[];
};

layout(set = 0, binding = 2, std430) restrict buffer OutCustom0Buffer {
	vec4 out_origins[]; // xyz = position before any shift, w = 1 when the vert may move
};

layout(set = 1, binding = 0, scalar) restrict buffer SharedEdgeBuffer {
	uint shared_count;
	uvec4 shared_edges[]; // Corner indices into the retracted block: this face's edge, then the twin's
};

layout(set = 2, binding = 0, std430) restrict buffer DispatchBuffer {
	uvec3 dispatch; // Indirect args for bevel_fill.glsl
};

uint next_corner(uint corner) {
	return (corner + 1) % 3;
}

// Twin corner per edge, or NONE at a boundary.
// Dedupe merged the verts, so a shared edge is the same index pair in both faces.
uvec3 find_twins(uint face) {
	uvec3 twins = uvec3(NONE);
	uvec3 corners = uvec3(out_faces[face]);

	for (uint f = 0; f < selected_face_count; f++) {
		if (f == face) continue;

		uvec3 other = uvec3(out_faces[f]);

		for (uint e = 0; e < 3; e++) {
			if (twins[e] != NONE) continue;

			uvec2 edge = uvec2(corners[e], corners[next_corner(e)]);

			for (uint o = 0; o < 3; o++) {
				// Correctly wound neighbours run their shared edge in opposite directions
				if (edge == uvec2(other[next_corner(o)], other[o])) twins[e] = f * 3 + o;
			}
		}

		if (all(notEqual(twins, uvec3(NONE)))) break;
	}

	return twins;
}

// Edge e sits opposite corner e+2, so a corner retreats toward the corner opposite
// whichever of its two edges is shared - or between both, when both are
vec3 inset_corner(mat3 positions, uint c, bvec3 is_shared) {
	uint next = next_corner(c);
	uint prev = (c + 2) % 3;

	bool to_prev = is_shared[c];
	bool to_next = is_shared[prev];

	if (!to_prev && !to_next) return positions[c];

	vec3 target = to_prev && to_next
	? mix(positions[next], positions[prev], 0.5)
	: (to_prev ? positions[prev] : positions[next]);

	return mix(positions[c], target, shrink);
}

void main() {
	uint face = gl_GlobalInvocationID.x;

	if (face >= selected_face_count) return;

	uvec3 corners = uvec3(out_faces[face]);
	mat3 positions = mat3(
		out_positions[corners.x], out_positions[corners.y], out_positions[corners.z]
	);

	uvec3 twins = find_twins(face);
	bvec3 is_shared = notEqual(twins, uvec3(NONE));

	// Retracted corners sit after the selection, one per face corner
	uint base = selected_vertex_count + face * 3;

	for (uint c = 0; c < 3; c++) {
		out_positions[base + c] = inset_corner(positions, c, is_shared);

		// Carries where the corner sat before retracting, so fill can rebuild the apex
		out_origins[base + c] = vec4(positions[c], out_origins[corners[c]].w);
	}

	out_faces[face] = u16vec3(base, base + 1, base + 2);

	// Both faces of an edge find each other, so only the lower corner registers it
	uvec4 pending[3];
	uint pending_count = 0;

	for (uint e = 0; e < 3; e++) {
		uint twin = twins[e];
		if (twin == NONE || face * 3 + e > twin) continue;

		uint twin_next = twin / 3 * 3 + next_corner(twin % 3);
		pending[pending_count] = uvec4(face * 3 + e, face * 3 + next_corner(e), twin, twin_next);
		pending_count++;
	}

	if (pending_count == 0) return;

	uint slot = atomicAdd(shared_count, pending_count);

	for (uint i = 0; i < pending_count; i++) {
		shared_edges[slot + i] = pending[i];
	}

	atomicMax(dispatch.x, (slot + pending_count + 255) / 256);
	dispatch.y = 1;
	dispatch.z = 1;
}
