// Sum each face's normal into its three corners. Run before normals_post.glsl.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types_int16 : require
#extension GL_EXT_shader_atomic_float : require

layout(local_size_x = 256) in;

layout(set = 0, binding = 0, std430) restrict buffer NormalSumBuffer {
	float normal_sums[]; // 3 floats per vertex, cleared before each run
};

layout(set = 1, binding = 0, scalar) restrict buffer OutVertexBuffer {
	vec3 out_positions[];
};

layout(set = 1, binding = 1, scalar) restrict buffer OutIndexBuffer {
	u16vec3 out_faces[];
};

layout(set = 1, binding = 2, std430) restrict buffer OutAttributeBuffer {
	uint out_attributes[]; // Unused
};

// Cross product magnitude is twice the triangle's area, so bigger faces weigh more
void accumulate(uint vert, vec3 normal) {
	uint base = vert * 3;
	atomicAdd(normal_sums[base], normal.x);
	atomicAdd(normal_sums[base + 1], normal.y);
	atomicAdd(normal_sums[base + 2], normal.z);
}

void main() {
	uint face = gl_GlobalInvocationID.x;

	if (face >= out_faces.length()) return;

	uvec3 corners = uvec3(out_faces[face]);
	vec3 a = out_positions[corners.x];
	vec3 b = out_positions[corners.y];
	vec3 c = out_positions[corners.z];

	vec3 normal = cross(b - a, c - a);

	accumulate(corners.x, normal);
	accumulate(corners.y, normal);
	accumulate(corners.z, normal);
}
