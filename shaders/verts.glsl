// Build the top surface: copy each face's 3 source verts into 3 new verts + 1 new triangle.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require

const float MARKER_SHIFTED = 1.0;

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	vec3 local_up; // model space, normalized
	uint in_vertex_stride;
	uint in_normal_offset;
	uint in_normal_stride;
	uint out_vertex_stride;
	uint out_normal_offset;
	uint out_normal_stride;
	uint out_marker_offset; // shifted vs static flag
	uint out_attribute_stride;
	uint out_index_stride; // bytes per index on the new surface, 2 or 4
};

layout(set = 0, binding = 0, std430) restrict readonly buffer InVertexBuffer {
	uint in_words[];
};

layout(set = 0, binding = 1, std430) restrict readonly buffer InIndexBuffer {
	uint in_index_words[]; // unused here
};

layout(set = 0, binding = 2, std430) restrict buffer InAttributeBuffer {
	uint in_attribute_words[]; // unused here
};

layout(set = 1, binding = 0, scalar) restrict buffer FacesBuffer {
	uint faces_count;
	uvec3 faces[];
};

layout(set = 1, binding = 1, scalar) restrict buffer EdgesBuffer {
	uint edges_count; // unused here
	uvec2 edges[]; // unused here
};

layout(set = 2, binding = 0, std430) restrict writeonly buffer OutVertexBuffer {
	uint out_words[];
};

layout(set = 2, binding = 1, std430) restrict buffer OutIndexBuffer {
	uint out_index_words[];
};

layout(set = 2, binding = 2, std430) restrict writeonly buffer OutAttributeBuffer {
	uint out_attributes[];
};

layout(set = 2, binding = 3, std430) restrict writeonly buffer OutInMapBuffer {
	uint out_in_map[]; // per out vertex, its in vertex - shape.glsl reads position from here
};

layout(set = 3, binding = 0, std430) restrict writeonly buffer DebugBuffer {
	uint debug_count;
};

vec3 read_in_position(uint in_index) {
	uint word = (in_index * in_vertex_stride) / 4u;
	return vec3(
		uintBitsToFloat(in_words[word]),
				uintBitsToFloat(in_words[word + 1u]),
				uintBitsToFloat(in_words[word + 2u])
	);
}

vec3 oct_decode(vec2 e) {
	vec3 v = vec3(e.xy, 1.0 - abs(e.x) - abs(e.y));
	vec2 wrapped = (1.0 - abs(v.yx)) * sign(v.xy);
	v.xy = mix(v.xy, wrapped, step(v.z, 0.0));
	return normalize(v);
}

vec3 read_in_normal(uint in_index) {
	uint word = (in_normal_offset + in_index * in_normal_stride) / 4u;
	vec2 e = fma(unpackUnorm2x16(in_words[word]), vec2(2.0), vec2(-1.0));
	return oct_decode(e);
}

uint oct_encode(vec3 n) {
	vec3 a = n / (abs(n.x) + abs(n.y) + abs(n.z));
	vec2 e = a.z >= 0.0 ? a.xy : (1.0 - abs(a.yx)) * sign(a.xy);
	return packUnorm2x16(fma(e, vec2(0.5), vec2(0.5)));
}

void write_vertex(uint out_index, uint in_index, vec3 position, vec3 normal, float marker) {
	uint position_word = (out_index * out_vertex_stride) / 4u;
	out_words[position_word] = floatBitsToUint(position.x);
	out_words[position_word + 1u] = floatBitsToUint(position.y);
	out_words[position_word + 2u] = floatBitsToUint(position.z);

	uint normal_word = (out_normal_offset + out_index * out_normal_stride) / 4u;
	out_words[normal_word] = oct_encode(normal);
	out_words[normal_word + 1u] = 0u; // tangent placeholder, real tangent TODO once UVs exist

	uint marker_word = (out_marker_offset + out_index * out_attribute_stride) / 4u;
	out_attributes[marker_word] = floatBitsToUint(marker);

	out_in_map[out_index] = in_index;
}

// Godot picks 16-bit or 32-bit indices for the new surface based on its vertex count -
// write accordingly rather than assuming, since a wrong-width write corrupts neighboring indices.
void write_index(uint i, uint value) {
	if (out_index_stride == 2u) {
		uint word = i / 2u;
		uint shift = (i % 2u) * 16u;
		atomicAnd(out_index_words[word], ~(0xFFFFu << shift));
		atomicOr(out_index_words[word], (value & 0xFFFFu) << shift);
		return;
	}
	out_index_words[i] = value;
}

void main() {
	uint face_index = gl_GlobalInvocationID.x + gl_GlobalInvocationID.y * (gl_NumWorkGroups.x * gl_WorkGroupSize.x);

	if (face_index >= faces_count) {
		return;
	}

	atomicAdd(debug_count, 1u);

	uvec3 face = faces[face_index];
	uint out_base = face_index * 3u;

	write_vertex(out_base, face.x, read_in_position(face.x), read_in_normal(face.x), MARKER_SHIFTED);
	write_vertex(out_base + 1u, face.y, read_in_position(face.y), read_in_normal(face.y), MARKER_SHIFTED);
	write_vertex(out_base + 2u, face.z, read_in_position(face.z), read_in_normal(face.z), MARKER_SHIFTED);

	write_index(out_base, out_base);
	write_index(out_base + 1u, out_base + 1u);
	write_index(out_base + 2u, out_base + 2u);
}
