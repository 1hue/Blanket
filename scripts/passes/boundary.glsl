// Skirt each boundary edge with a quad
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types : require

const uint COLOR_WALL = 0xFF20C0E0; // Amber

layout(local_size_x = 64) in;

layout(push_constant, std430) uniform PushParams {
	uint wall_vertex_base; // First slot the wall owns
	uint wall_face_base;
	uint out_color_offset;
	uint out_custom_offset;
	uint out_attribute_stride;
};

layout(set = 0, binding = 0, scalar) restrict buffer OutVertexBuffer {
	vec3 out_positions[];
};

layout(set = 0, binding = 1, scalar) restrict buffer OutIndexBuffer {
	u16vec3 out_faces[];
};

layout(set = 0, binding = 2, std430) restrict buffer OutAttributeBuffer {
	uint out_attributes[];
};

layout(set = 1, binding = 0, scalar) restrict buffer BoundaryBuffer {
	uint boundary_count;
	uvec2 boundary_edges[];
};

void write_color(uint vert, uint color) {
	out_attributes[(out_color_offset + vert * out_attribute_stride) / 4] = color;
}

void write_vertex(uint vert, vec3 position) {
	uint at = (out_custom_offset + vert * out_attribute_stride) / 4;

	out_positions[vert] = position;
	out_attributes[at] = floatBitsToUint(position.x);
	out_attributes[at + 1] = floatBitsToUint(position.y);
	out_attributes[at + 2] = floatBitsToUint(position.z);
	// Immovable, but skip writing W = 0.0 - already default

	write_color(vert, COLOR_WALL);
}

void main() {
	uint idx = gl_GlobalInvocationID.x;

	if (idx >= boundary_count) return;

	uvec2 edge = boundary_edges[idx];
	uint base = wall_vertex_base + idx * 2;
	uint face = wall_face_base + idx * 2;

	write_vertex(base, out_positions[edge.x]);
	write_vertex(base + 1, out_positions[edge.y]);

	// Alternate the diagonal so neighbouring quads converge rather than fan
	uvec4 quad = uvec4(edge.x, edge.y, base + 1, base);
	bool flip = idx % 2 == 1;

	out_faces[face] = u16vec3(flip ? quad.xyw : quad.xyz);
	out_faces[face + 1] = u16vec3(flip ? quad.yzw : quad.xzw);
}
