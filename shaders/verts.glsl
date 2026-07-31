// Builds the new surface: cap verts from faces, wall verts from edges.
// Writes positions, normals, markers, indices, and each vert's source index.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require

const float MARKER_SHIFTED = 1.0;
const float MARKER_STATIC = 0.0;

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	vec3 local_up;
	uint in_vertex_stride;
	uint in_normals_offset;
	uint in_normal_tangent_stride;
	uint out_vertex_stride;
	uint out_normals_offset;
	uint out_normal_tangent_stride;
	uint out_markers_offset;
	uint out_attribute_stride;
};

layout(set = 0, binding = 0, std430) restrict readonly buffer InVertexBuffer {
	uint in_words[];
};

layout(set = 1, binding = 0, scalar) restrict readonly buffer FacesBuffer {
	uvec3 faces_dispatch;
	uint faces_count;
	uvec3 faces[];
};

layout(set = 1, binding = 1, scalar) restrict readonly buffer EdgesBuffer {
	uvec3 edges_dispatch;
	uint edges_count;
	uvec2 edges[];
};

layout(set = 2, binding = 0, std430) restrict writeonly buffer OutVertexBuffer {
	uint out_words[];
};

layout(set = 2, binding = 1, std430) restrict writeonly buffer OutIndexBuffer {
	uint out_indices[];
};

layout(set = 2, binding = 2, std430) restrict writeonly buffer OutAttributeBuffer {
	uint out_attributes[];
};

layout(set = 2, binding = 3, std430) restrict writeonly buffer OutSourceBuffer {
	uint out_sources[]; // per out vertex, the in vertex it came from - depth offsets from that position
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
	uint word = (in_normals_offset + in_index * in_normal_tangent_stride) / 4u;
	vec2 e = unpackUnorm2x16(in_words[word]) * 2.0 - 1.0;
	return oct_decode(e);
}

uint oct_encode(vec3 n) {
	vec3 a = n / (abs(n.x) + abs(n.y) + abs(n.z));
	vec2 e = a.z >= 0.0 ? a.xy : (1.0 - abs(a.yx)) * sign(a.xy);
	return packUnorm2x16(e * 0.5 + 0.5);
}

void write_vertex(uint out_index, uint in_index, vec3 position, vec3 normal, float marker) {
	uint position_word = (out_index * out_vertex_stride) / 4u;
	out_words[position_word] = floatBitsToUint(position.x);
	out_words[position_word + 1u] = floatBitsToUint(position.y);
	out_words[position_word + 2u] = floatBitsToUint(position.z);

	uint normal_word = (out_normals_offset + out_index * out_normal_tangent_stride) / 4u;
	out_words[normal_word] = oct_encode(normal);

	uint marker_word = (out_markers_offset + out_index * out_attribute_stride) / 4u;
	out_attributes[marker_word] = floatBitsToUint(marker);

	out_sources[out_index] = in_index;
}

void main() {
	uint slot = gl_GlobalInvocationID.x + gl_GlobalInvocationID.y * (gl_NumWorkGroups.x * gl_WorkGroupSize.x);
	uint cap_vertices = faces_count * 3u;

	if (slot < faces_count) {
		uvec3 face = faces[slot];
		uint base = slot * 3u;

		for (uint corner = 0u; corner < 3u; corner++) {
			uint in_index = corner == 0u ? face.x : (corner == 1u ? face.y : face.z);
			write_vertex(
				base + corner,
				in_index,
				read_in_position(in_index),
						 read_in_normal(in_index),
						 MARKER_SHIFTED
			);
			out_indices[base + corner] = base + corner;
		}
		return;
	}

	uint edge = slot - faces_count;

	if (edge >= edges_count) {
		return;
	}

	uvec2 pair = edges[edge];
	vec3 position_a = read_in_position(pair.x);
	vec3 position_b = read_in_position(pair.y);
	vec3 normal = normalize(cross(position_b - position_a, local_up));

	uint base = cap_vertices + edge * 4u;
	write_vertex(base, pair.x, position_a, normal, MARKER_STATIC);
	write_vertex(base + 1u, pair.y, position_b, normal, MARKER_STATIC);
	write_vertex(base + 2u, pair.x, position_a, normal, MARKER_SHIFTED);
	write_vertex(base + 3u, pair.y, position_b, normal, MARKER_SHIFTED);

	uint index_base = cap_vertices + edge * 6u;
	out_indices[index_base] = base;
	out_indices[index_base + 1u] = base + 1u;
	out_indices[index_base + 2u] = base + 3u;
	out_indices[index_base + 3u] = base;
	out_indices[index_base + 4u] = base + 3u;
	out_indices[index_base + 5u] = base + 2u;
}
