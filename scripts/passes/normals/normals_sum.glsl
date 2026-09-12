// Sum each face's normal into its three corners. Run before normals_write.glsl.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types : require
#extension GL_EXT_shader_atomic_float : require

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	uint out_face_count;
};

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

void accumulate(uint vert, vec3 normal) {
	uint base = vert * 3;

	atomicAdd(normal_sums[base], normal.x);
	atomicAdd(normal_sums[base + 1], normal.y);
	atomicAdd(normal_sums[base + 2], normal.z);
}

bool is_degenerate(uvec3 tri) {
	return tri.x == tri.y || tri.x == tri.z || tri.y == tri.z;
}

// Area weighting would drown the narrow bevel strips in their large neighbours,
// softening the crease. The corner's own angle is what the vert actually sees
float corner_angle(vec3 apex, vec3 p, vec3 q) {
	vec3 to_p = p - apex;
	vec3 to_q = q - apex;
	float lengths = length(to_p) * length(to_q);

	if (lengths < 1e-18) return 0.0;

	return acos(clamp(dot(to_p, to_q) / lengths, -1.0, 1.0));
}

void main() {
	uint face = gl_GlobalInvocationID.x;

	if (face >= out_face_count) return;

	uvec3 corners = uvec3(out_faces[face]);

	if (is_degenerate(corners)) return;

	vec3 a = out_positions[corners.x];
	vec3 b = out_positions[corners.y];
	vec3 c = out_positions[corners.z];
	vec3 normal = cross(c - a, b - a);
	float area2 = length(normal);

	if (area2 < 1e-12) return; // Collinear corners, no plane to contribute

	normal /= area2;

	accumulate(corners.x, normal * corner_angle(a, b, c));
	accumulate(corners.y, normal * corner_angle(b, c, a));
	accumulate(corners.z, normal * corner_angle(c, a, b));
}
