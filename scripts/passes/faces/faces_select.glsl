// Find all faces facing within upright_dot of local_up.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types : require

const uint DEDUPE_WORKGROUP_SIZE = 64;

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	vec3 local_up; // Model space, normalized
	float upright_dot; // Min face-vs-up dot to qualify
	uint in_vertex_count;
	uint in_face_count;
	uint in_normal_offset; // Bytes into the vertex buffer
	uint in_normal_stride; // Bytes per vertex
	uint in_color_offset; // Bytes into the attribute buffer
	uint in_attribute_stride; // Bytes per vertex
};

layout(set = 0, binding = 0, std430) restrict readonly buffer InVertexBuffer {
	uint in_words[]; // Positions, then packed normals - read as words for the normal block
};

layout(set = 0, binding = 1, scalar) restrict readonly buffer InIndexBuffer {
	u16vec3 in_faces[];
};

layout(set = 0, binding = 2, std430) restrict buffer InAttributeBuffer {
	uint in_attributes[];
};

layout(set = 1, binding = 0, scalar) restrict buffer FacesVertexScratchBuffer {
	uint vertex_count; // Unused
	vec3 out_positions[]; // Unused
};

layout(set = 1, binding = 1, scalar) restrict buffer FacesIndexScratchBuffer {
	uint face_count;
	uvec3 out_faces[]; // Source vertex indices until faces_write.glsl repoints them
};

layout(set = 2, binding = 0, scalar) restrict writeonly buffer DispatchBuffer {
	uvec3 dispatch_dedupe;
};

vec3 oct_decode(vec2 e) {
	vec3 v = vec3(e.xy, 1 - abs(e.x) - abs(e.y));
	vec2 wrapped = (1 - abs(v.yx)) * sign(v.xy);
	v.xy = mix(v.xy, wrapped, step(v.z, 0));
	return v; // Unnormalized - summed with two others and renormalized by the caller
}

vec3 read_normal(uint vert) {
	uint word = (in_normal_offset + vert * in_normal_stride) / 4;
	return oct_decode(fma(unpackUnorm2x16(in_words[word]), vec2(2), vec2(-1)));
}

void write_color(uint vert, vec4 color) {
	in_attributes[(in_color_offset + vert * in_attribute_stride) / 4] = packUnorm4x8(color);
}

void main() {
	uint face = gl_GlobalInvocationID.x;

	if (face >= in_face_count) return;

	u16vec3 corners = in_faces[face];

	if (any(greaterThanEqual(uvec3(corners), uvec3(in_vertex_count)))) return;

	// Average the 3 corner normals to approximate the face normal
	vec3 face_normal = normalize(
		read_normal(corners.x) + read_normal(corners.y) + read_normal(corners.z)
	);

	bool is_upright = dot(face_normal, local_up) > upright_dot;
	vec4 color = is_upright ? vec4(0, 1, 0, 1) : vec4(1, 0, 0, 1);

	// Debug visualization on the source mesh
	write_color(corners.x, color);
	write_color(corners.y, color);
	write_color(corners.z, color);

	if (!is_upright) return;

	uint slot = atomicAdd(face_count, 1);
	out_faces[slot] = corners;

	atomicMax(dispatch_dedupe.x, 1 + slot / DEDUPE_WORKGROUP_SIZE);
}
