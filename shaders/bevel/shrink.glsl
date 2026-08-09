// Shrink each face away from its shared edges. Corner index becomes the new vertex index.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types_int16 : require

// Edge i runs from corner i to corner i+1, so corner i touches edges i and i-1
const uint EDGE_AB = 0u;
const uint EDGE_BA = 0u;
const uint EDGE_BC = 1u;
const uint EDGE_CB = 1u;
const uint EDGE_CA = 2u;
const uint EDGE_AC = 2u;
const uint NONE = 0xFFFFFFFFu;

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	float shrink; // 0 = unchanged, 1 = collapsed to centroid
	uint in_vertex_count;
	uint in_index_count;
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
	u16vec3 out_faces[];
};

layout(set = 1, binding = 2, std430) restrict writeonly buffer OutAttributeBuffer {
	uint out_attributes[];
};

layout(set = 2, binding = 0, scalar) restrict buffer SharedEdgeBuffer {
	uint shared_count;
	uvec2 shared_edges[]; // corner in face A, matching corner in face B
};

layout(set = 3, binding = 0, std430) restrict buffer DispatchBuffer {
	uvec3 dispatch; // indirect args for wedge.glsl
};

layout(set = 4, binding = 0, std430) restrict buffer DebugBuffer {
	float debug_out[3];
};

mat3 get_face_positions(uint face) {
	uvec3 corners = uvec3(in_faces[face]);
	return mat3(
		in_positions[corners.x],
		in_positions[corners.y],
		in_positions[corners.z]
	);
}

bool edges_match(vec3 a0, vec3 a1, vec3 b0, vec3 b1) {
	return (a0 == b0 && a1 == b1) || (a0 == b1 && a1 == b0);
}

// Twin corner index per edge, or NONE if the edge is a boundary
uvec3 find_shared_edges(uint face, uint in_face_count) {
	mat3 positions_self = get_face_positions(face);
	uvec3 result = uvec3(NONE);

	for (uint f = 0u; f < in_face_count; f++) {
		if (face == f) continue; // Don't compare with self

		mat3 positions_other = get_face_positions(f);

		for (uint i_self = 0u; i_self < 3u; i_self++) {
			vec3 self_a = positions_self[i_self];
			vec3 self_b = positions_self[(i_self + 1u) % 3u];

			for (uint i_other = 0u; i_other < 3u; i_other++) {
				vec3 other_a = positions_other[i_other];
				vec3 other_b = positions_other[(i_other + 1u) % 3u];

				if (edges_match(self_a, self_b, other_a, other_b)) {
					result[i_self] = f * 3u + i_other;
					break;
				}
			}
		}
	}

	return result;
}

// Each corner retreats along its two edges (or between, towards face center) based on whether edge is shared
vec3 inset_corner(vec3 own, vec3 next, vec3 prev, bool next_shared, bool prev_shared) {
	if (!next_shared && !prev_shared) {
		return own;
	}

	float bias = next_shared && prev_shared ? 0.5 : (next_shared ? 1.0 : 0.0);
	return mix(own, mix(next, prev, bias), shrink);
}

void write_out_color(uint out_index, vec4 color) {
	uint word = (out_color_offset + out_index * out_attribute_stride) / 4u;
	out_attributes[word] = packUnorm4x8(color);
}

void main() {
	uint face = gl_GlobalInvocationID.x + gl_GlobalInvocationID.y * (gl_NumWorkGroups.x * gl_WorkGroupSize.x);
	uint in_face_count = in_index_count / 3u;

	if (face >= in_face_count) return;

	uvec3 corners = uvec3(in_faces[face]);
	vec3 a = in_positions[corners.x];
	vec3 b = in_positions[corners.y];
	vec3 c = in_positions[corners.z];

	uvec3 edges = find_shared_edges(face, in_face_count);
	uint base = face * 3u;

	out_positions[base] = inset_corner(a, b, c, edges[EDGE_AB] != NONE, edges[EDGE_AC] != NONE);
	out_positions[base + 1u] = inset_corner(b, c, a, edges[EDGE_BC] != NONE, edges[EDGE_BA] != NONE);
	out_positions[base + 2u] = inset_corner(c, a, b, edges[EDGE_CA] != NONE, edges[EDGE_CB] != NONE);

	out_faces[face] = u16vec3(base, base + 1u, base + 2u);

	vec4 red = vec4(1, 0, 0, 1);
	write_out_color(base, edges[EDGE_AB] != NONE || edges[EDGE_AC] != NONE ? red : vec4(1));
	write_out_color(base + 1u, edges[EDGE_BC] != NONE || edges[EDGE_BA] != NONE ? red : vec4(1));
	write_out_color(base + 2u, edges[EDGE_CA] != NONE || edges[EDGE_CB] != NONE ? red : vec4(1));

	// Register shared edges for the wedge pass - lower corner wins so each edge lands once
	for (uint e = 0u; e < 3u; e++) {
		uint corner = base + e;
		uint twin = edges[e];

		if (twin == NONE || twin < corner) continue;

		uint slot = atomicAdd(shared_count, 1u);
		shared_edges[slot] = uvec2(corner, twin);
		atomicMax(dispatch.x, (slot + 256u) / 256u);
		dispatch.y = 2u; // one invocation per edge endpoint
		dispatch.z = 1u;
	}
}
