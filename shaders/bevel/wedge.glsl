// Fill the gap at one end of a shared edge with a fan anchored at the original vertex.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types_int16 : require

const uint SEGMENTS = 2u; // Per side of the crease
const uint RING_COUNT = SEGMENTS * 2u + 1u;
const uint VERT_COUNT = RING_COUNT + 1u;
const uint TRI_COUNT = RING_COUNT - 1u;

// X = shared edge, Y = which end of it
layout(local_size_x = 256, local_size_y = 2) in;

layout(push_constant, std430) uniform PushParams {
	float shrink; // Must match shrink.glsl
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

uint corner_vertex(uint corner) {
	return uint(in_faces[corner / 3u][corner % 3u]);
}

void write_color(uint vert, vec4 color) {
	out_attributes[(out_color_offset + vert * out_attribute_stride) / 4u] = packUnorm4x8(color);
}

void write_vertex(uint vert, vec3 position, vec4 color) {
	out_positions[vert] = position;
	write_color(vert, color);
}

void write_triangle(uint at, uvec3 verts) {
	out_faces[at] = uint16_t(verts.x);
	out_faces[at + 1u] = uint16_t(verts.y);
	out_faces[at + 2u] = uint16_t(verts.z);
}

// Walks retracted_a -> crease -> retracted_b, crease landing exactly on step SEGMENTS
vec3 ring_point(mat3 anchors, uint step) {
	bool past_crease = step > SEGMENTS;
	float t = float(past_crease ? step - SEGMENTS : step) / float(SEGMENTS);

	return past_crease
		? mix(anchors[1], anchors[2], t)
		: mix(anchors[0], anchors[1], t);
}

void main() {
	uint edge = gl_GlobalInvocationID.x;
	uint end = gl_GlobalInvocationID.y;

	if (edge >= shared_count) return;

	uvec4 corners = shared_edges[edge];

	// Faces run the edge in opposite directions, so the ends pair crosswise
	uint corner_a = end == 0u ? corners.x : corners.y;
	uint corner_b = end == 0u ? corners.w : corners.z;
	uint far = end == 0u ? corners.y : corners.x;

	vec3 origin = in_positions[corner_vertex(corner_a)];
	vec3 crease = mix(origin, in_positions[corner_vertex(far)], shrink); // On the edge, so in both planes

	mat3 anchors = mat3(out_positions[corner_a], crease, out_positions[corner_b]);

	uint wedge = edge * 2u + end;
	uint corner_count = uint(in_faces.length()) * 3u; // Shrink filled everything below this
	uint vert_base = corner_count + wedge * VERT_COUNT;
	uint index_base = corner_count + wedge * TRI_COUNT * 3u;

	write_vertex(vert_base, origin, vec4(0, 0, 1, 1));

	for (uint i = 0u; i < RING_COUNT; i++) {
		write_vertex(vert_base + 1u + i, ring_point(anchors, i), vec4(0, 1, 0, 1));
	}

	for (uint i = 0u; i < TRI_COUNT; i++) {
		write_triangle(index_base + i * 3u, uvec3(vert_base, vert_base + 1u + i, vert_base + 2u + i));
	}
}
