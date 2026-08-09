// Shrink each face away from its shared edges. Corner index becomes the new vertex index.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types_int16 : require

// const uint NONE = 0xFFFFFFFFu;
const uint WEDGES_GROUP_SIZE = 256;

// X = face index, Y = face corner index
layout(local_size_x = 128, local_size_y = 3) in;

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
	uint16_t out_faces[];
};

layout(set = 1, binding = 2, std430) restrict writeonly buffer OutAttributeBuffer {
	uint out_attributes[];
};

layout(set = 2, binding = 0, scalar) restrict buffer SharedEdgeBuffer {
	uint shared_count;
	uvec4 shared_edges[]; // Pairs of uvec2
};

layout(set = 3, binding = 0, std430) restrict buffer DispatchBuffer {
	uvec3 dispatch; // indirect args for wedge.glsl
};

layout(set = 4, binding = 0, std430) restrict buffer DebugBuffer {
	float debug_out[12];
};

// Mark which of 3 face edges are shared - neighbour verts need to know where to move
shared bool shared_flags[gl_WorkGroupSize.x][gl_WorkGroupSize.y];

uint next_corner(uint corner) {
	return (corner + 1u) % 3u;
}

bool is_degen(uvec2 parts) {
	return parts[0] == parts[1];
}

bool is_degen(mat2x3 parts) {
	return parts[0] == parts[1];
}

bool edges_match(mat2x3 a, mat2x3 b) {
	// TODO Compare position equality within a proximity margin
	return a == b || (a[0] == b[1] && a[1] == b[0]);
}

bool edges_match(uvec2 a, uvec2 b) {
	return a == b || (a[0] == b[1] && a[1] == b[0]);
}

// Find the first pair of matching edge positions and exit.
// Return actual vert indices.
uvec2 find_shared_edge(uint face, uvec2 edge) {
	mat2x3 edge_pos = mat2x3(
		in_positions[edge[0]], // This corner
		in_positions[edge[1]] // Next corner
	);

	if (is_degen(edge) || is_degen(edge_pos)) return uvec2(0);

	// Loop only up to self - any matching edges in faces above will be matched in their invocations
	for (uint f = 0; f < in_faces.length() && f < face; f++) {
		// Compare with the 3 edges of the other face
		for (uint i = 0; i < 3; i++) {
			uvec2 other_edge = uvec2(
				in_faces[f][i],
				in_faces[f][next_corner(i)]
			);
			mat2x3 other_edge_pos = mat2x3(
				in_positions[other_edge[0]],
				in_positions[other_edge[1]]
			);

			if (is_degen(other_edge) || is_degen(other_edge_pos)) {
				continue; // Degenerate triangle
			}
			if (edges_match(edge, other_edge) || edges_match(edge_pos, other_edge_pos)) {
				return other_edge;
			}
		}
	}

	return uvec2(0); // 0 is a valid index but 0,0 is a degenerate edge - use as falsy
}

// Each corner retreats along its two edges (or towards face center) based on whether edge is shared
vec3 inset_corner(uint face, uint corner) {
	uint next = next_corner(corner);
	uint prev = (corner + 2u) % 3u;

	vec3 self_pos = in_positions[in_faces[face][corner]];
	vec3 next_pos = in_positions[in_faces[face][next]];
	vec3 prev_pos = in_positions[in_faces[face][prev]];

	bool next_shared = shared_flags[gl_LocalInvocationID.x][corner];
	bool prev_shared = shared_flags[gl_LocalInvocationID.x][prev];

	if (!next_shared && !prev_shared) {
		return self_pos;
	}

	float bias = next_shared && prev_shared ? 0.5 : (next_shared ? 1.0 : 0.0);
	return mix(self_pos, mix(next_pos, prev_pos, bias), shrink);
}

void write_out_color(uint out_index, vec4 color) {
	uint word = (out_color_offset + out_index * out_attribute_stride) / 4;
	out_attributes[word] = packUnorm4x8(color);
}

void main() {
	uint face = gl_GlobalInvocationID.x; // Vert index
	uint corner = gl_GlobalInvocationID.y; // Index offset 0..2 within a face like (3,4,5)

	if (face >= in_index_count / 3) return;

// 	uint idx = gl_GlobalInvocationID.x + gl_GlobalInvocationID.y * (gl_NumWorkGroups.x * gl_WorkGroupSize.x);
	uvec2 edge = uvec2(
		in_faces[face][corner],
		in_faces[face][next_corner(corner)]
	);
	uvec2 twin = find_shared_edge(face, edge);
	bool is_shared = twin != uvec2(0);

	shared_flags[gl_LocalInvocationID.x][gl_LocalInvocationID.y] = is_shared;

	barrier(); // wait for all 3 corners of this face to finish their own detection

	// Copied vertex keeps its original index, but moves position
	uint base = face * 3u + corner;
	out_positions[base] = inset_corner(face, corner);
	out_faces[base] = uint16_t(base);

	// Debug visualization: red where this corner touches a shared edge
	write_out_color(base, is_shared ? vec4(1, 0, 0, 1) : vec4(1));

	if (!is_shared) return;

	uint slot = atomicAdd(shared_count, 1u);
	shared_edges[slot] = uvec4(edge, twin);
	atomicMax(dispatch.x, (slot + WEDGES_GROUP_SIZE) / WEDGES_GROUP_SIZE);
	dispatch.y = 1u;
	dispatch.z = 1u;
}
