// Offsets marked verts along local_up by depth, from their source position
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require

const float SHIFT_FACTOR = 0.1;

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	vec3 local_up;
	float depth;
	uint out_vertex_count;
	uint in_vertex_stride;
	uint out_vertex_stride;
	uint out_markers_offset;
	uint out_attribute_stride;
};

layout(set = 0, binding = 0, std430) restrict readonly buffer InVertexBuffer {
	uint in_words[];
};

layout(set = 1, binding = 0, std430) restrict buffer OutVertexBuffer {
	uint out_words[];
};

layout(set = 1, binding = 1, std430) restrict readonly buffer OutAttributeBuffer {
	uint out_attributes[];
};

layout(set = 1, binding = 2, std430) restrict readonly buffer OutSourceBuffer {
	uint out_sources[];
};

vec3 read_in_position(uint in_index) {
	uint word = (in_index * in_vertex_stride) / 4u;
	return vec3(
		uintBitsToFloat(in_words[word]),
				uintBitsToFloat(in_words[word + 1u]),
				uintBitsToFloat(in_words[word + 2u])
	);
}

float read_marker(uint out_index) {
	uint word = (out_markers_offset + out_index * out_attribute_stride) / 4u;
	return uintBitsToFloat(out_attributes[word]);
}

void write_position(uint out_index, vec3 position) {
	uint word = (out_index * out_vertex_stride) / 4u;
	out_words[word] = floatBitsToUint(position.x);
	out_words[word + 1u] = floatBitsToUint(position.y);
	out_words[word + 2u] = floatBitsToUint(position.z);
}

void main() {
	uint out_index = gl_GlobalInvocationID.x + gl_GlobalInvocationID.y * (gl_NumWorkGroups.x * gl_WorkGroupSize.x);

	if (out_index >= out_vertex_count) {
		return;
	}

	vec3 position = read_in_position(out_sources[out_index]);
	vec3 offset = normalize(local_up) * depth * SHIFT_FACTOR * read_marker(out_index);

	write_position(out_index, position + offset);
}
