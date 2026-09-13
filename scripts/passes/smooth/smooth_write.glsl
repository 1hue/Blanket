// Move each vertex toward its neighbour average. Static verts stay put.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types_int16 : require

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	float strength; // 0 = unchanged, 1 = fully at the neighbour average
	uint out_vertex_count;
	uint out_custom_offset;
	uint out_attribute_stride;
};

layout(set = 0, binding = 0, std430) restrict buffer SmoothSumBuffer {
	vec4 sums[]; // 4 floats per vertex: x, y, z, count
};

layout(set = 1, binding = 0, scalar) restrict buffer OutVertexBuffer {
	vec3 out_positions[]; // Positions and normals
};

layout(set = 1, binding = 1, scalar) restrict buffer OutIndexBuffer {
	u16vec3 out_faces[]; // Unused
};

layout(set = 1, binding = 2, std430) restrict buffer OutAttributeBuffer {
	uint out_attributes[];
};

// Custom0 W is the fraction of depth this vert travels - 0 means immovable
bool immovable(uint vert) {
	return uintBitsToFloat(out_attributes[(out_custom_offset + vert * out_attribute_stride) / 4 + 3]) == 0.0;
}

void main() {
	uint vert = gl_GlobalInvocationID.x;

	if (vert >= out_vertex_count) return;
	if (immovable(vert)) return; // Pinned verts pull their neighbours but don't move
	if (sums[vert].w <= 0.0) return; // Nothing to average toward

	vec3 average = sums[vert].xyz / sums[vert].w;

	out_positions[vert] = mix(out_positions[vert], average, strength);
}
