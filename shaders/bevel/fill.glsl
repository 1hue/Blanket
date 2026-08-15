// Bridge a shared edge: an arc per end, a fan behind each, and a strip between them.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types_int16 : require

const uint WEDGE_SEGMENTS = 2; // Tip triangle, then WEDGE_SEGMENTS-1 quad bands outward

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	float shrink; // Must match shrink.glsl
	uint segments; // Per side of the crease
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
	return uint(in_faces[corner / 3][corner % 3]);
}

void write_vertex(uint vert, vec3 position, vec4 color) {
	out_positions[vert] = position;
	out_attributes[(out_color_offset + vert * out_attribute_stride) / 4] = packUnorm4x8(color);
}

void write_triangle(uint tri, uvec3 verts, bool reverse) {
	uvec3 wound = reverse ? verts.xzy : verts;
	uint at = tri * 3;

	out_faces[at] = uint16_t(wound.x);
	out_faces[at + 1] = uint16_t(wound.y);
	out_faces[at + 2] = uint16_t(wound.z);
}

// anchors: retracted A, crease, retracted B
vec3 arc_point(mat3 anchors, uint step) {
	return step > segments
	? mix(anchors[1], anchors[2], float(step - segments) / float(segments))
	: mix(anchors[0], anchors[1], float(step) / float(segments));
}

mat3 arc_anchors(uvec4 corners, uint end) {
	uint near = end == 0 ? corners.x : corners.y;
	uint far = end == 0 ? corners.w : corners.z;
	uint along = end == 0 ? corners.y : corners.x;

	vec3 origin = in_positions[corner_vertex(near)];
	vec3 crease = mix(origin, in_positions[corner_vertex(along)], shrink);

	return mat3(out_positions[near], crease, out_positions[far]);
}

// Ring 1 hugs the apex, ring WEDGE_SEGMENTS is the arc itself
uint ring_vert(uint ring_base, uint end, uint ring, uint step) {
	uint arc_count = segments * 2 + 1;
	return ring_base + (end * WEDGE_SEGMENTS + ring - 1) * arc_count + step;
}

void main() {
	uint edge = gl_GlobalInvocationID.x;

	if (edge >= shared_count) return;

	uvec4 corners = shared_edges[edge];

	uint arc_steps = segments * 2;
	uint arc_count = arc_steps + 1;
	uint bands = WEDGE_SEGMENTS - 1;

	uint fan_verts = 1 + WEDGE_SEGMENTS * arc_count;
	uint fan_tris = arc_steps + bands * arc_steps * 2;
	uint corner_count = uint(in_faces.length()) * 3;

	uint apex_base = corner_count + edge * fan_verts * 2;
	uint ring_base = apex_base + 2;
	uint tri_base = corner_count + edge * (fan_tris * 2 + arc_steps * 2);

	for (uint end = 0; end < 2; end++) {
		mat3 anchors = arc_anchors(corners, end);
		vec3 apex = in_positions[corner_vertex(end == 0 ? corners.x : corners.y)];

		write_vertex(apex_base + end, apex, vec4(0, 0, 1, 1));

		for (uint ring = 1; ring <= WEDGE_SEGMENTS; ring++) {
			float t = float(ring) / float(WEDGE_SEGMENTS);
			vec4 color = ring == WEDGE_SEGMENTS ? vec4(0, 1, 0, 1) : vec4(1, 0, 1, 1);

			for (uint i = 0; i <= arc_steps; i++) {
				vec3 point = mix(apex, arc_point(anchors, i), t);
				write_vertex(ring_vert(ring_base, end, ring, i), point, color);
			}
		}
	}

	for (uint end = 0; end < 2; end++) {
		bool reverse = end == 1; // Ends sit at opposite ends of the edge
		uint fan_base = tri_base + end * fan_tris;

		for (uint i = 0; i < arc_steps; i++) {
			uint inner = ring_vert(ring_base, end, 1, i);
			write_triangle(fan_base + i, uvec3(apex_base + end, inner + 1, inner), reverse);
		}

		for (uint ring = 1; ring < WEDGE_SEGMENTS; ring++) {
			uint band_base = fan_base + arc_steps + (ring - 1) * arc_steps * 2;

			for (uint i = 0; i < arc_steps; i++) {
				uint inner = ring_vert(ring_base, end, ring, i);
				uint outer = ring_vert(ring_base, end, ring + 1, i);

				// Alternate which diagonal splits the quad
				bool flip = (i + ring) % 2 == 1;

				uvec3 a = flip ? uvec3(inner, outer + 1, outer) : uvec3(inner, inner + 1, outer);
				uvec3 b = flip ? uvec3(inner, inner + 1, outer + 1) : uvec3(inner + 1, outer + 1, outer);

				write_triangle(band_base + i * 2, a, reverse);
				write_triangle(band_base + i * 2 + 1, b, reverse);
			}
		}
	}

	uint strip_base = tri_base + fan_tris * 2;

	for (uint i = 0; i < arc_steps; i++) {
		uint near = ring_vert(ring_base, 0, WEDGE_SEGMENTS, i);
		uint far = ring_vert(ring_base, 1, WEDGE_SEGMENTS, i);

		write_triangle(strip_base + i * 2, uvec3(near, near + 1, far + 1), false);
		write_triangle(strip_base + i * 2 + 1, uvec3(near, far + 1, far), false);
	}
}
