// Seed the out surface with the flat selection - visible as soon as this runs
#[versions]
out_u16 = "#define OUT_INDEX_TYPE u16vec3";
out_u32 = "#define OUT_INDEX_TYPE uvec3";

#[compute]
#version 450
#VERSION_DEFINES

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types : require

const uint FLAG_BOUNDARY = 1;
const uint COLOR_ORIGINAL = 0xFFE06020; // Blue
const uint COLOR_BOUNDARY = 0xFF0000FF; // Red

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
	OUT_INDEX_TYPE out_faces[];
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

layout(set = 2, binding = 0, std430) restrict buffer VertexFlagBuffer {
	uint vertex_flags[];
};

void write_color(uint vert, uint color) {
	out_attributes[(out_color_offset + vert * out_attribute_stride) / 4] = color;
}

// Marked verts still move - only the wall row the boundary pass adds is frozen
void write_vertex(uint vert) {
	bool marked = (vertex_flags[vert] & FLAG_BOUNDARY) != 0;
	uint at = (out_custom_offset + vert * out_attribute_stride) / 4;
	vec3 position = sel_positions[vert];

	out_positions[vert] = position;
	out_attributes[at] = floatBitsToUint(position.x);
	out_attributes[at + 1] = floatBitsToUint(position.y);
	out_attributes[at + 2] = floatBitsToUint(position.z);
	out_attributes[at + 3] = floatBitsToUint(1.0); // Movable

	write_color(vert, marked ? COLOR_BOUNDARY : COLOR_ORIGINAL);
}

void main() {
	uint idx = gl_GlobalInvocationID.x;

	// Verts and faces are separate ranges, so a lane may do one, both or neither
	if (idx < sel_vertex_count) {
		write_vertex(idx);
	}

	// Flat copy - bevel_shrink repoints these onto the retracted verts
	if (idx < sel_face_count) {
		out_faces[idx] = OUT_INDEX_TYPE(sel_faces[idx]);
	}
}
