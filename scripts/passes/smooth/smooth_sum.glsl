// Sum each face's edges into its vertices' neighbour totals. Run before smooth_write.glsl.
#[versions]
out_u16 = "#define OUT_INDEX_TYPE u16vec3";
out_u32 = "#define OUT_INDEX_TYPE uvec3";

#[compute]
#version 450
#VERSION_DEFINES

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types : require
#extension GL_EXT_shader_atomic_float : require

const float MAX_COTANGENT = 16.0; // Slivers otherwise dominate their vert's average

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	uint out_face_count;
};

layout(set = 0, binding = 0, std430) restrict buffer SmoothSumBuffer {
	float sums[]; // 4 floats per vertex: x, y, z, count
};

layout(set = 1, binding = 0, scalar) restrict buffer OutVertexBuffer {
	vec3 out_positions[]; // Positions and normals
};

layout(set = 1, binding = 1, scalar) restrict buffer OutIndexBuffer {
	OUT_INDEX_TYPE out_faces[];
};

layout(set = 1, binding = 2, std430) restrict buffer OutAttributeBuffer {
	uint out_attributes[]; // Unused
};

float cotangent(vec3 corner, vec3 a, vec3 b) {
	vec3 u = a - corner;
	vec3 v = b - corner;

	return clamp(dot(u, v) / max(length(cross(u, v)), 1e-8), 0.0, MAX_COTANGENT);
}

void accumulate(uint vert, vec3 position, float weight) {
	uint base = vert * 4;
	atomicAdd(sums[base], position.x * weight);
	atomicAdd(sums[base + 1], position.y * weight);
	atomicAdd(sums[base + 2], position.z * weight);
	atomicAdd(sums[base + 3], weight);
}

bool is_degen(uvec3 tri) {
	return tri.x == tri.y || tri.x == tri.z || tri.y == tri.z;
}

void main() {
	uint face = gl_GlobalInvocationID.x;

	if (face >= out_face_count) return;

	uvec3 corners = uvec3(out_faces[face]);

	if (is_degen(corners)) return;

	vec3 a = out_positions[corners.x];
	vec3 b = out_positions[corners.y];
	vec3 c = out_positions[corners.z];

	if (length(cross(c - a, b - a)) < 1e-12) return;

	// Each edge is weighted by the cotangent at the corner facing it
	float wc = cotangent(c, a, b);
	float wa = cotangent(a, b, c);
	float wb = cotangent(b, c, a);

	// Each vertex gets contributions from both of its edges in this face
	accumulate(corners.x, b, wc);
	accumulate(corners.y, a, wc);
	accumulate(corners.y, c, wa);
	accumulate(corners.z, b, wa);
	accumulate(corners.z, a, wb);
	accumulate(corners.x, c, wb);
}
