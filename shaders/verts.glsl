// Build the new surface geometry: top verts from faces, side verts from edges.
// Copy (In) to (Out) using faces & edges selection indices.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require

const float MARKER_SHIFTED = 1.0;
const float MARKER_STATIC = 0.0;

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

layout(set = 2, binding = 3, std430) restrict writeonly buffer OutInMapBuffer {
	uint out_in_map[]; // per out vertex, its in vertex - shape.glsl reads position from here
};

layout(set = 3, binding = 0, std430) restrict buffer DebugBuffer {
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

	uint marker_word = (out_marker_offset + out_index * out_attribute_stride) / 4u;
	out_attributes[marker_word] = floatBitsToUint(marker);

	out_in_map[out_index] = in_index;
}

void write_triangle(uint index_base, uint a, uint b, uint c) {
	out_indices[index_base] = a;
	out_indices[index_base + 1u] = b;
	out_indices[index_base + 2u] = c;
}

// Top: copy the face's 3 verts as-is, keeping their source normals
void write_top(uint face_index) {
	uvec3 face = faces[face_index];
	uint base = face_index * 3u;

	write_vertex(base, face.x, read_in_position(face.x), read_in_normal(face.x), MARKER_SHIFTED);
	write_vertex(base + 1u, face.y, read_in_position(face.y), read_in_normal(face.y), MARKER_SHIFTED);
	write_vertex(base + 2u, face.z, read_in_position(face.z), read_in_normal(face.z), MARKER_SHIFTED);

	write_triangle(base, base, base + 1u, base + 2u);
}

// Side: extrude the edge into a quad - bottom pair stays put, top pair gets shifted by shape.glsl
void write_side(uint edge_index, uint vertex_base, uint index_base) {
	uvec2 pair = edges[edge_index];
	vec3 position_a = read_in_position(pair.x);
	vec3 position_b = read_in_position(pair.y);
	vec3 normal = normalize(cross(position_b - position_a, local_up)); // flat, faces outward

	uint base = vertex_base + edge_index * 4u;
	write_vertex(base, pair.x, position_a, normal, MARKER_STATIC);
	write_vertex(base + 1u, pair.y, position_b, normal, MARKER_STATIC);
	write_vertex(base + 2u, pair.x, position_a, normal, MARKER_SHIFTED);
	write_vertex(base + 3u, pair.y, position_b, normal, MARKER_SHIFTED);

	uint indices_at = index_base + edge_index * 6u;
	write_triangle(indices_at, base, base + 1u, base + 3u);
	write_triangle(indices_at + 3u, base, base + 3u, base + 2u);
}

void main() {
	uint idx = gl_GlobalInvocationID.x + gl_GlobalInvocationID.y * (gl_NumWorkGroups.x * gl_WorkGroupSize.x);

	if (idx >= faces_count + edges_count) {
		return;
	}

	atomicAdd(debug_count, 1u);

	if (idx < faces_count) {
		write_top(idx);
		return;
	}

// 	write_side(idx - faces_count, faces_count * 3u, faces_count * 3u);
}
