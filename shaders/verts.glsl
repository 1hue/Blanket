// Build the new surface: top verts from faces, side verts from edges.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	vec3 local_up; // model space, normalized
	uint in_vertex_count;
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
	uint edges_count;
	uvec3 edges[];
};

layout(set = 2, binding = 0, std430) restrict writeonly buffer OutVertexBuffer {
	uint out_words[];
};

layout(set = 2, binding = 1, std430) restrict writeonly buffer OutIndexBuffer {
	uint out_index_words[];
};

layout(set = 2, binding = 2, std430) restrict writeonly buffer OutAttributeBuffer {
	uint out_attributes[];
};

layout(set = 2, binding = 3, std430) restrict writeonly buffer OutInMapBuffer {
	uint out_in_map[]; // per out vertex, its in vertex - shape.glsl reads position from here
};

layout(set = 3, binding = 0, std430) restrict buffer SlotBuffer {
	uint unique_count;
	uint slots[];
};

layout(set = 3, binding = 1, std430) restrict buffer UsedBuffer {
	uint used[];
};

const float MARKER_SHIFTED = 1.0;
const float MARKER_STATIC = 0.0;

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
	// Position
	uint position_word = (out_index * out_vertex_stride) / 4u;
	out_words[position_word] = floatBitsToUint(position.x);
	out_words[position_word + 1u] = floatBitsToUint(position.y);
	out_words[position_word + 2u] = floatBitsToUint(position.z);

	// Normal, tangent left blank until UVs exist
	uint normal_word = (out_normal_offset + out_index * out_normal_stride) / 4u;
	out_words[normal_word] = oct_encode(normal);
	out_words[normal_word + 1u] = 0u;

	// Shifted vs static flag, read back by shape.glsl
	uint marker_word = (out_marker_offset + out_index * out_attribute_stride) / 4u;
	out_attributes[marker_word] = floatBitsToUint(marker);

	// Source vertex this came from, read back by shape.glsl
	out_in_map[out_index] = in_index;
}

// Godot picks 16-bit or 32-bit indices based on vertex count - write accordingly
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

void write_top(uint face_index) {
	uvec3 face = faces[face_index];
	uint base = face_index * 3u;

	// Verts already written by the dedupe-driven pass below; only indices needed here
	write_index(base, slots[face.x]);
	write_index(base + 1u, slots[face.y]);
	write_index(base + 2u, slots[face.z]);
}

// Side: extrude the edge into a quad - bottom pair stays put, top pair gets shifted by shape.glsl
void write_side(uint edge_index, uint vertex_base, uint index_base) {
	uvec3 edge = edges[edge_index];
	vec3 position_a = read_in_position(edge.x);
	vec3 position_b = read_in_position(edge.y);
	vec3 position_third = read_in_position(edge.z);

	vec3 normal = normalize(cross(position_b - position_a, local_up));

	// third is inside the face this edge came from - wall must face away from it
	if (dot(normal, position_third - position_a) > 0.0) {
		normal = -normal;
	}

	uint base = vertex_base + edge_index * 4u;
	write_vertex(base, edge.x, position_a, normal, MARKER_STATIC);
	write_vertex(base + 1u, edge.y, position_b, normal, MARKER_STATIC);
	write_vertex(base + 2u, edge.x, position_a, normal, MARKER_SHIFTED);
	write_vertex(base + 3u, edge.y, position_b, normal, MARKER_SHIFTED);

	uint indices_at = index_base + edge_index * 6u;
	write_index(indices_at, base);
	write_index(indices_at + 1u, base + 1u);
	write_index(indices_at + 2u, base + 3u);
	write_index(indices_at + 3u, base);
	write_index(indices_at + 4u, base + 3u);
	write_index(indices_at + 5u, base + 2u);
}

void main() {
	uint idx = gl_GlobalInvocationID.x + gl_GlobalInvocationID.y * (gl_NumWorkGroups.x * gl_WorkGroupSize.x);

	// Vertex data: one invocation per source vertex, only canonicals write
	if (idx < in_vertex_count) {
		if (used[idx] == 1u && slots[idx] != 0xFFFFFFFFu) {
			write_vertex(slots[idx], idx, read_in_position(idx), read_in_normal(idx), MARKER_SHIFTED);
		}
	}

	// Top indices: one invocation per face
	if (idx < faces_count) {
		write_top(idx);
	}

	// Sides: one invocation per edge, appended after all unique top verts, undeduped
	if (idx < edges_count) {
		write_side(idx, unique_count, faces_count * 3u);
	}
}
