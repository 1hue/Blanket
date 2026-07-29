#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types_int16 : require

const uint NEXT_PASS_SIZE = 256u;

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	vec3 local_up; // World-up transformed into mesh local space (computed on CPU)
	float max_slope_degrees; // Max angle from local_up for a face to qualify, 0deg for horizontal
	uint index_count;
	uint vertex_count;
	uint index_stride; // bytes per index, 2 or 4
	uint normals_offset; // bytes
	uint normal_tangent_stride; // bytes per vertex
	uint colors_offset; // bytes
	uint attribute_stride; // bytes per vertex
};

layout(set = 0, binding = 0, std430) restrict readonly buffer VertexBuffer {
	uint vertex_buffer[]; // positions, then normals+tangents
};

layout(set = 0, binding = 1, std430) restrict readonly buffer IndexBuffer {
	uint index_buffer[]; // 16-bit or 32-bit indices, per index_stride
};

layout(set = 0, binding = 2, std430) restrict buffer AttributeBuffer {
	uint attribute_buffer[];
};

layout(set = 1, binding = 0, scalar) restrict buffer CountBuffer {
	uvec3 dispatch;
	uint counter;
	uvec3 eligible[];
};

uint read_index(uint i) {
	if (index_stride == 2u) {
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
	uint word = (normals_offset + vertex_index * normal_tangent_stride) / 4u;
	vec2 e = unpackUnorm2x16(vertex_buffer[word]) * 2.0 - 1.0;
	return oct_decode(e);
}

void write_color(uint vertex_index, vec4 color) {
	uint word = (colors_offset + vertex_index * attribute_stride) / 4u;
	attribute_buffer[word] = packUnorm4x8(color);
}

void main() {
	uint tri = gl_GlobalInvocationID.x + gl_GlobalInvocationID.y * (gl_NumWorkGroups.x * gl_WorkGroupSize.x);

	if (tri * 3u + 2u >= index_count) {
		return;
	}

	uvec3 tri_indices = read_triangle(tri);

	if (any(greaterThanEqual(tri_indices, uvec3(vertex_count)))) {
		return;
	}

	vec3 face_normal = normalize(
		read_normal(tri_indices.x)
		+ read_normal(tri_indices.y)
		+ read_normal(tri_indices.z)
	);

	bool passes = dot(face_normal, normalize(local_up)) > cos(radians(max_slope_degrees));
	vec4 color = passes ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);

	write_color(tri_indices.x, color);
	write_color(tri_indices.y, color);
	write_color(tri_indices.z, color);

	if (!passes) {
		return;
	}

	uint slot = atomicAdd(counter, 1u);
	eligible[slot] = tri_indices;
	atomicMax(dispatch.x, (slot + NEXT_PASS_SIZE) / NEXT_PASS_SIZE);
	dispatch.y = 3u;
	dispatch.z = 1u;
}
