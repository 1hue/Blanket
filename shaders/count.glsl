#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types_int16 : require

layout(local_size_x = 256) in;

layout(constant_id = 0) const uint INDEX_COUNT = 0;
layout(constant_id = 1) const uint VERTEX_COUNT = 0;
layout(constant_id = 2) const uint INDEX_STRIDE = 0; // bytes per index, 2 or 4
layout(constant_id = 3) const uint NORMALS_OFFSET = 0; // bytes
layout(constant_id = 4) const uint NORMAL_TANGENT_STRIDE = 0; // bytes per vertex
layout(constant_id = 5) const uint COLORS_OFFSET = 0;
layout(constant_id = 6) const uint ATTRIBUTE_STRIDE = 0;

layout(push_constant, std430) uniform PushParams {
	vec3 local_up; // World-up transformed into mesh local space (computed on CPU)
	float up_threshold_degrees; // Max angle from local_up for a face to qualify, 0deg for horizontal
	float shift_amount;
};

layout(set = 0, binding = 0, std430) restrict readonly buffer IndexBuffer {
	uint index_buffer[]; // 16-bit or 32-bit indices, per INDEX_STRIDE
};

layout(set = 0, binding = 1, std430) restrict readonly buffer VertexBuffer {
	uint vertex_buffer[]; // positions, then normals+tangents
};

layout(set = 0, binding = 2, std430) restrict buffer AttributeBuffer {
	uint attribute_buffer[];
};

layout(set = 1, binding = 0, scalar) restrict buffer CountBuffer {
	uint counter;
	uvec3 eligible[];
};

uint read_index(uint i) {
	if (INDEX_STRIDE == 2u) {
		u16vec2 pair = unpackUint2x16(index_buffer[i / 2u]);
		return uint(i % 2u == 0u ? pair.x : pair.y);
	}
	return index_buffer[i];
}

uvec3 read_triangle(uint tri) {
	uint base = tri * 3u;
	return uvec3(read_index(base), read_index(base + 1u), read_index(base + 2u));
}

vec3 oct_decode(vec2 e) {
	vec3 v = vec3(e.xy, 1.0 - abs(e.x) - abs(e.y));
	vec2 wrapped = (1.0 - abs(v.yx)) * sign(v.xy);
	v.xy = mix(v.xy, wrapped, step(v.z, 0.0));
	return normalize(v);
}

vec3 read_normal(uint vertex_index) {
	uint word = (NORMALS_OFFSET + vertex_index * NORMAL_TANGENT_STRIDE) / 4u;
	vec2 e = unpackUnorm2x16(vertex_buffer[word]) * 2.0 - 1.0;
	return oct_decode(e);
}

void write_color(uint vertex_index, vec4 color) {
	uint word = (COLORS_OFFSET + vertex_index * ATTRIBUTE_STRIDE) / 4u;
	attribute_buffer[word] = packUnorm4x8(color);
}

void main() {
	uint tri = gl_GlobalInvocationID.x + gl_GlobalInvocationID.y * (gl_NumWorkGroups.x * gl_WorkGroupSize.x);

	if (tri * 3u + 2u >= INDEX_COUNT) {
		return;
	}

	uvec3 tri_indices = read_triangle(tri);

	if (any(greaterThanEqual(tri_indices, uvec3(VERTEX_COUNT)))) {
		return;
	}

	vec3 face_normal = normalize(
		read_normal(tri_indices.x)
		+ read_normal(tri_indices.y)
		+ read_normal(tri_indices.z)
	);

	bool passes = dot(face_normal, normalize(local_up)) > cos(radians(up_threshold_degrees));
	vec4 color = passes ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);

	write_color(tri_indices.x, color);
	write_color(tri_indices.y, color);
	write_color(tri_indices.z, color);

	if (!passes) {
		return;
	}

	eligible[atomicAdd(counter, 1u)] = tri_indices;
}
