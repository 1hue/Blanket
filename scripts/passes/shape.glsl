// Offset marked verts along local_up by depth, from their source position.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types_int16 : require

const float SHIFT_FACTOR = 0.1;

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	vec3 local_up; // model space, normalized
	float depth; // extrude distance
	uint out_vertex_count;
	uint out_marker_offset;
	uint out_attribute_stride;
};

layout(set = 0, binding = 0, scalar) restrict readonly buffer InVertexBuffer {
	vec3 in_positions[];
};

layout(set = 0, binding = 1, std430) restrict readonly buffer InIndexBuffer {
	u16vec3 in_faces[];
};

layout(set = 0, binding = 2, std430) restrict buffer InAttributeBuffer {
	uint in_attribute_words[]; // unused here
};

layout(set = 2, binding = 0, scalar) restrict writeonly buffer OutVertexBuffer {
	vec3 out_positions[];
};

layout(set = 2, binding = 1, scalar) restrict buffer OutIndexBuffer {
	uint16_t out_faces[]; // unused
};

layout(set = 2, binding = 2, std430) restrict buffer OutAttributeBuffer {
	uint out_attributes[];
};

layout(set = 2, binding = 3, std430) restrict buffer OutInMapBuffer {
	uint out_in_map[];
};

float read_marker(uint out_index) {
	uint word = (out_marker_offset + out_index * out_attribute_stride) / 4u;
	return uintBitsToFloat(out_attributes[word]);
}

void main() {
	uint out_index = gl_GlobalInvocationID.x;

	if (out_index >= out_vertex_count) return;

	vec3 position = in_positions[out_in_map[out_index]];
	// Marker is 1.0 (shifted) or 0.0 (static), doubling as the multiplier - no branch needed
	vec3 offset = local_up * depth * SHIFT_FACTOR * read_marker(out_index);

	out_positions[out_index] = position + offset;
}
