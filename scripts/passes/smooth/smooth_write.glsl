// Move each vertex toward its neighbour average. Pinned verts stay put.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types : require

layout(constant_id = 0) const float SMOOTH_STRENGTH = 0.5; // 0 = unchanged, 1 = fully at the neighbour average
layout(constant_id = 1) const float WALL_STRENGTH = 0.4; // 0 = collapses inward, 1 = stands up

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	uint wall_rim_base; // Everything past this is wall
	uint out_vertex_count;
	uint out_custom_offset;
	uint out_attribute_stride;
};

layout(set = 0, binding = 0, std430) restrict buffer SmoothSumBuffer {
	vec4 sums[]; // Weighted neighbour positions in xyz, total weight in w
};

layout(set = 1, binding = 0, scalar) restrict buffer OutVertexBuffer {
	vec3 out_positions[];
};

layout(set = 1, binding = 1, scalar) restrict buffer OutIndexBuffer {
	u16vec3 out_faces[]; // unused
};

layout(set = 1, binding = 2, std430) restrict buffer OutAttributeBuffer {
	uint out_attributes[];
};

// Custom0 W is the fraction of depth this vert travels - 0 pinned, 1 free
float movable(uint vert) {
	return uintBitsToFloat(out_attributes[(out_custom_offset + vert * out_attribute_stride) / 4 + 3]);
}

void main() {
	uint vert = gl_GlobalInvocationID.x;

	if (vert >= out_vertex_count) return;
	if (sums[vert].w < 1e-6) return; // No neighbours, or their weights cancelled out

	float smoothing = vert < wall_rim_base ? SMOOTH_STRENGTH : SMOOTH_STRENGTH * (1.0 - WALL_STRENGTH);
	float strength = movable(vert) * smoothing;

	if (strength < 1e-6) return;

	vec3 average = sums[vert].xyz / sums[vert].w;

	out_positions[vert] = mix(out_positions[vert], average, strength);
}
