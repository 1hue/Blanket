#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require

const float SHIFT_FACTOR = 0.1;

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	vec3 local_up;
	float shift_amount;
	uint vertex_count;
	uint source_vertex_stride; // bytes per position in source buffer
	uint target_vertex_stride; // bytes per position in target buffer
};

layout(set = 0, binding = 0, std430) restrict readonly buffer SourceVertexBuffer {
	uint source_buffer[];
};

layout(set = 0, binding = 1, std430) restrict writeonly buffer TargetVertexBuffer {
	uint target_buffer[];
};

layout(set = 1, binding = 0, scalar) restrict buffer CountBuffer {
	uint counter;
	uvec3 eligible[];
};

vec3 read_source_position(uint vertex_index) {
	uint word = (vertex_index * source_vertex_stride) / 4u;
	return vec3(
		uintBitsToFloat(source_buffer[word]),
		uintBitsToFloat(source_buffer[word + 1u]),
		uintBitsToFloat(source_buffer[word + 2u])
	);
}

void write_target_position(uint vertex_index, vec3 position) {
	uint word = (vertex_index * target_vertex_stride) / 4u;
	target_buffer[word] = floatBitsToUint(position.x);
	target_buffer[word + 1u] = floatBitsToUint(position.y);
	target_buffer[word + 2u] = floatBitsToUint(position.z);
}

void main() {
	uint target_index = gl_GlobalInvocationID.x + gl_GlobalInvocationID.y * (gl_NumWorkGroups.x * gl_WorkGroupSize.x);

	if (target_index >= vertex_count) {
		return;
	}

	uint source_index = eligible[target_index / 3u][target_index % 3u];
	vec3 source_position = read_source_position(source_index);

	write_target_position(target_index, source_position + normalize(local_up) * shift_amount * SHIFT_FACTOR);
}
