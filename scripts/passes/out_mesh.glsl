// Seed the out surface
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types : require

const uint FLAG_BOUNDARY = 1;
const uint COLOR_ORIGINAL = 0xFFE06020; // Blue
const uint COLOR_ANCHORED = 0xFF0000FF; // Red

layout(local_size_x = 64) in;

layout(push_constant, std430) uniform PushParams {
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

layout(set = 1, binding = 0, scalar) restrict buffer SelectedVertexBuffer {
	uint sel_vertex_count;
	vec3 sel_positions[];
};

layout(set = 1, binding = 1, scalar) restrict buffer SelectedIndexBuffer {
	uint sel_face_count;
	uvec3 sel_faces[];
};

// Declared for layout match only
layout(set = 2, binding = 0, std430) restrict buffer SharedMaskBuffer {
	uint shared_mask[];
};

// Bit 0 set = vert lies on the selection boundary
layout(set = 2, binding = 1, std430) restrict buffer VertexFlagBuffer {
	uint vertex_flags[];
};

void write_color(uint vert, uint color) {
	out_attributes[(out_color_offset + vert * out_attribute_stride) / 4] = color;
}

// Custom0 is RGBA_FLOAT, so w is the 4th word
void write_custom_w(uint vert, float value) {
	out_attributes[(out_custom_offset + vert * out_attribute_stride) / 4 + 3] = floatBitsToUint(value);
}

// The selection occupies the first sel_vertex_count slots of the new surface
void write_vertex(uint vert) {
	bool anchored = (vertex_flags[vert] & FLAG_BOUNDARY) != 0;

	out_positions[vert] = sel_positions[vert];
	write_custom_w(vert, float(anchored));
	write_color(vert, anchored ? COLOR_ANCHORED : COLOR_ORIGINAL);
}

void main() {
	uint idx = gl_GlobalInvocationID.x;

	if (idx < sel_vertex_count) {
		write_vertex(idx);
	}

	if (idx < sel_face_count) {
		// Flat copy - bevel_shrink repoints these onto the retracted verts
		out_faces[idx] = u16vec3(sel_faces[idx]);
	}
}
