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

// Custom0.w = 1 freezes the vert against the displacement pass
void write_freeze(uint vert, float frozen) {
	out_attributes[(out_custom_offset + vert * out_attribute_stride) / 4 + 3] = floatBitsToUint(frozen);
}

// The wall row starts coincident with the surface and only separates once it lifts
void write_wall_vert(uint slot, uint source) {
	out_positions[slot] = out_positions[source];
	write_freeze(slot, 1.0);
	write_color(slot, COLOR_WALL);
}

void main() {
	uint idx = gl_GlobalInvocationID.x;

	if (idx >= boundary_count) return;

	uvec2 edge = boundary_edges[idx];
	uint base = wall_vertex_base + idx * 2;
	uint face = wall_face_base + idx * 2;

	write_wall_vert(base, edge.x);
	write_wall_vert(base + 1, edge.y);

	// Edge runs x -> y in face winding, so the skirt hangs off that direction
	out_faces[face] = u16vec3(edge.x, edge.y, base + 1);
	out_faces[face + 1] = u16vec3(edge.x, base + 1, base);
}
