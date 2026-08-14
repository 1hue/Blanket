// Fill the strip left between the two wedge fans along a shared edge.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types_int16 : require

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	float shrink; // Must match shrink.glsl
	uint segments; // Must match wedge.glsl
	uint out_color_offset;
	uint out_attribute_stride;
};

layout(set = 0, binding = 0, scalar) restrict readonly buffer InVertexBuffer {
	vec3 in_positions[];
};

layout(set = 0, binding = 1, scalar) restrict readonly buffer InIndexBuffer {
	u16vec3 in_faces[];
};

layout(set = 1, binding = 0, scalar) restrict buffer OutVertexBuffer {
	vec3 out_positions[];
};

layout(set = 1, binding = 1, scalar) restrict buffer OutIndexBuffer {
	uint16_t out_faces[];
};

layout(set = 1, binding = 2, std430) restrict buffer OutAttributeBuffer {
	uint out_attributes[];
};

layout(set = 2, binding = 0, scalar) restrict buffer SharedEdgeBuffer {
	uint shared_count;
	uvec4 shared_edges[];
};

layout(set = 4, binding = 0, scalar) restrict buffer DebugBuffer {
	vec4 debug;
};

uint corner_vertex(uint corner) {
	return uint(in_faces[corner / 3u][corner % 3u]);
}

void write_vertex(uint vert, vec3 position, vec4 color) {
	out_positions[vert] = position;
	out_attributes[(out_color_offset + vert * out_attribute_stride) / 4u] = packUnorm4x8(color);
}

void write_triangle(uint at, uvec3 verts) {
	out_faces[at] = uint16_t(verts.x);
	out_faces[at + 1u] = uint16_t(verts.y);
	out_faces[at + 2u] = uint16_t(verts.z);
}

vec3 ring_point(mat3 anchors, uint step) {
	bool past_crease = step > segments;
	float t = float(past_crease ? step - segments : step) / float(segments);

	return past_crease
		? mix(anchors[1], anchors[2], t)
		: mix(anchors[0], anchors[1], t);
}

// Recomputed rather than read from wedge.glsl, which may still be in flight
mat3 ring_anchors(uvec4 corners, uint end) {
	uint corner_a = end == 0u ? corners.x : corners.y;
	uint corner_b = end == 0u ? corners.w : corners.z;
	uint far = end == 0u ? corners.y : corners.x;

	vec3 origin = in_positions[corner_vertex(corner_a)];
	vec3 crease = mix(origin, in_positions[corner_vertex(far)], shrink);

	return mat3(out_positions[corner_a], crease, out_positions[corner_b]);
}

void main() {
	uint edge = gl_GlobalInvocationID.x;

	if (edge >= shared_count) return;

	uint ring_count = segments * 2u + 1u;
	uint vert_count = ring_count + 1u;
	uint tri_count = ring_count - 1u;

	mat3 near = ring_anchors(shared_edges[edge], 0u);
	mat3 far = ring_anchors(shared_edges[edge], 1u);

	uint corner_count = uint(in_faces.length()) * 3u;
	uint wedge_verts = shared_count * 2u * vert_count;
	uint wedge_indices = shared_count * 2u * tri_count * 3u;

	uint vert_base = corner_count + wedge_verts + edge * ring_count * 2u;
	uint index_base = corner_count + wedge_indices + edge * tri_count * 6u;

	debug = vec4(ring_count, vert_count, tri_count, corner_count);

	for (uint i = 0u; i < ring_count; i++) {
		write_vertex(vert_base + i, ring_point(near, i), vec4(1, 1, 0, 1));
		write_vertex(vert_base + ring_count + i, ring_point(far, i), vec4(1, 1, 0, 1));
	}

	// Rings run in step, so each pair of adjacent steps closes a quad
	for (uint i = 0u; i < tri_count; i++) {
		uint a = vert_base + i;
		uint b = vert_base + i + 1u;
		uint c = vert_base + ring_count + i + 1u;
		uint d = vert_base + ring_count + i;

		write_triangle(index_base + i * 6u, uvec3(a, b, c));
		write_triangle(index_base + i * 6u + 3u, uvec3(a, c, d));
	}
}
