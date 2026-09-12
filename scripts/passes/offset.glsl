// Offset each vert along local_up, scaled by the proportion stored in custom0
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types : require

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	vec3 local_up; // Model space, normalized
	float depth; // Extrude distance
	uint out_vertex_count;
	uint out_custom_offset;
	uint out_attribute_stride;
};

layout(set = 0, binding = 0, scalar) restrict buffer OutVertexBuffer {
	vec3 out_positions[];
};

layout(set = 0, binding = 1, scalar) restrict buffer OutIndexBuffer {
	u16vec3 out_faces[]; // unused
};

layout(set = 0, binding = 2, std430) restrict buffer OutAttributeBuffer {
	uint out_attributes[];
};

// Custom0 XYZ = rest position, W = fraction of depth this vert travels
vec4 read_custom(uint vert) {
	uint at = (out_custom_offset + vert * out_attribute_stride) / 4;

	return uintBitsToFloat(uvec4(
		out_attributes[at],
		out_attributes[at + 1],
		out_attributes[at + 2],
		out_attributes[at + 3]
	));
}

void main() {
	uint vert = gl_GlobalInvocationID.x;

	if (vert >= out_vertex_count) return;

	// Working from rest keeps this idempotent - depth can be dragged without drift
	vec4 custom = read_custom(vert);

	out_positions[vert] = custom.xyz + local_up * depth * custom.w;
}
