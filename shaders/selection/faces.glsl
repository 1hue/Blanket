// Find all faces facing within upright_dot of local_up.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types_int16 : require

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	vec3 local_up; // model space, normalized
	float upright_dot; // min face-vs-up dot to qualify
	uint in_index_count;
	uint in_vertex_count;
	uint in_index_stride; // 2 or 4 bytes
	uint in_normal_offset; // bytes into vertex buffer
	uint in_normal_stride; // bytes per vertex
	uint in_color_offset; // bytes into attribute buffer
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
	uint faces_count;
	uvec3 faces[]; // eligible face vertex indices
};

layout(set = 1, binding = 1, scalar) restrict buffer EdgesBuffer {
	uint edges_count;
	uvec2 edges[]; // unused here - declared so the set matches other passes
};

layout(set = 2, binding = 0, std430) restrict writeonly buffer FacesDispatchBuffer {
	uvec3 dispatch;
};

layout(set = 3, binding = 0, std430) restrict buffer SlotBuffer {
	uint unique_count;
	uint slots[];
};

layout(set = 3, binding = 1, std430) restrict buffer UsedBuffer {
	uint used[];
};

const uint EDGES_GROUP_SIZE = 1u;

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
	return v; // unnormalized - summed with two others and renormalized by the caller
}

vec3 read_normal(uint vertex_index) {
	uint word = (in_normal_offset + vertex_index * in_normal_stride) / 4u;
	vec2 e = fma(unpackUnorm2x16(in_words[word]), vec2(2.0), vec2(-1.0));
	return oct_decode(e);
}

void write_color(uint vertex_index, vec4 color) {
	uint word = (in_color_offset + vertex_index * in_attribute_stride) / 4u;
	in_attribute_words[word] = packUnorm4x8(color);
}

void main() {
	uint face = gl_GlobalInvocationID.x + gl_GlobalInvocationID.y * (gl_NumWorkGroups.x * gl_WorkGroupSize.x);

	if (face * 3u + 2u >= in_index_count) {
		return;
	}

	uvec3 face_indices = read_face(face);

	if (any(greaterThanEqual(face_indices, uvec3(in_vertex_count)))) {
		return;
	}

	// Average the 3 corner normals to approximate the face normal
	vec3 face_normal = normalize(
		read_normal(face_indices.x)
		+ read_normal(face_indices.y)
		+ read_normal(face_indices.z)
	);

	bool is_upright = dot(face_normal, local_up) > upright_dot;
	vec4 color = is_upright ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 0.0, 0.0, 1.0);

	// Debug visualization on the source mesh, regardless of eligibility
	write_color(face_indices.x, color);
	write_color(face_indices.y, color);
	write_color(face_indices.z, color);

	if (!is_upright) {
		return;
	}

	// Record this face as part of the snow cap
	uint slot = atomicAdd(faces_count, 1u);
	faces[slot] = face_indices;

	// Mark corners so the dedupe pass knows which source verts matter
	used[face_indices.x] = 1u;
	used[face_indices.y] = 1u;
	used[face_indices.z] = 1u;

	atomicMax(dispatch.x, (slot + EDGES_GROUP_SIZE) / EDGES_GROUP_SIZE);
	dispatch.y = 3u;
	dispatch.z = 1u;
}
