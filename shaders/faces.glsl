// Finds faces whose normal points within max_slope_degrees of local_up.
// Writes them to FacesBuffer and sizes the edges pass dispatch.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types_int16 : require

const uint EDGES_GROUP_SIZE = 256u;

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	vec3 local_up; // World-up transformed into mesh local space (computed on CPU)
	float max_slope_degrees; // Max angle from local_up for a face to qualify, 0deg for horizontal
	uint in_index_count;
	uint in_vertex_count;
	uint in_index_stride; // bytes per index, 2 or 4
	uint in_normals_offset; // bytes
	uint in_normal_tangent_stride; // bytes per vertex
	uint in_colors_offset; // bytes
	uint in_attribute_stride; // bytes per vertex
};

layout(set = 0, binding = 0, std430) restrict readonly buffer InVertexBuffer {
	uint in_words[]; // positions, then normals+tangents
};

layout(set = 0, binding = 1, std430) restrict readonly buffer InIndexBuffer {
	uint in_index_words[]; // 16-bit or 32-bit indices, per in_index_stride
};

layout(set = 0, binding = 2, std430) restrict buffer InAttributeBuffer {
	uint in_attribute_words[];
};

layout(set = 1, binding = 0, scalar) restrict buffer FacesBuffer {
	uvec3 dispatch; // x scales with faces_count, y is 3 so the edges pass gets one invocation per edge
	uint faces_count;
	uvec3 faces[];
};

uint read_index(uint i) {
	if (in_index_stride == 2u) {
		u16vec2 pair = unpackUint2x16(in_index_words[i / 2u]);
		return uint(i % 2u == 0u ? pair.x : pair.y);
	}
	return in_index_words[i];
}

uvec3 read_face(uint face) {
	uint base = face * 3u;
	return uvec3(read_index(base), read_index(base + 1u), read_index(base + 2u));
}

vec3 oct_decode(vec2 e) {
	vec3 v = vec3(e.xy, 1.0 - abs(e.x) - abs(e.y));
	vec2 wrapped = (1.0 - abs(v.yx)) * sign(v.xy);
	v.xy = mix(v.xy, wrapped, step(v.z, 0.0));
	return normalize(v);
}

vec3 read_normal(uint vertex_index) {
	uint word = (in_normals_offset + vertex_index * in_normal_tangent_stride) / 4u;
	vec2 e = unpackUnorm2x16(in_words[word]) * 2.0 - 1.0;
	return oct_decode(e);
}

void write_color(uint vertex_index, vec4 color) {
	uint word = (in_colors_offset + vertex_index * in_attribute_stride) / 4u;
	in_attribute_words[word] = packUnorm4x8(color);
}

void main() {
	uint face = gl_GlobalInvocationID.x + gl_GlobalInvocationID.y * (gl_NumWorkGroups.x * gl_WorkGroupSize.x);

	dispatch.y = 3u;
	dispatch.z = 1u;

	if (face * 3u + 2u >= in_index_count) {
		return;
	}

	uvec3 face_indices = read_face(face);

	if (any(greaterThanEqual(face_indices, uvec3(in_vertex_count)))) {
		return;
	}

	vec3 face_normal = normalize(
		read_normal(face_indices.x)
		+ read_normal(face_indices.y)
		+ read_normal(face_indices.z)
	);

	bool is_upright = dot(face_normal, normalize(local_up)) > cos(radians(max_slope_degrees));
	vec4 color = is_upright ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);

	write_color(face_indices.x, color);
	write_color(face_indices.y, color);
	write_color(face_indices.z, color);

	if (!is_upright) {
		return;
	}

	uint slot = atomicAdd(faces_count, 1u);
	faces[slot] = face_indices;
	atomicMax(dispatch.x, (slot + EDGES_GROUP_SIZE) / EDGES_GROUP_SIZE);
}
