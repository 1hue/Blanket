// Bridge a shared edge: a polar fan at each end, and a strip between their arcs.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types_int16 : require

const uint RINGS = 4; // Tip triangle, then RINGS-1 quad bands out to the arc

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	float shrink;
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

uvec4 corners;
uint arc_steps;
uint arc_count;
uint apex_base;
uint ring_base;
uint arc_base;

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

// Anchors: retracted A, crease, retracted B
vec3 arc_point(mat3 anchors, uint step) {
	return step > segments
		? mix(anchors[1], anchors[2], float(step - segments) / float(segments))
		: mix(anchors[0], anchors[1], float(step) / float(segments));
}

mat3 arc_anchors(uint end) {
	uint near = end == 0 ? corners.x : corners.y;
	uint far = end == 0 ? corners.w : corners.z;
	uint along = end == 0 ? corners.y : corners.x;

	vec3 origin = in_positions[corner_vertex(near)];
	vec3 crease = mix(origin, in_positions[corner_vertex(along)], shrink);

	return mat3(out_positions[near], crease, out_positions[far]);
}

// Fan as a polar grid. The arc's two ends are shrink's retracted corners, so they
// resolve back into its output rather than being duplicated here.
uint fan_vert(uint end, uint ring, uint step) {
	if (ring == 0) return apex_base + end;
	if (ring < RINGS) return ring_base + (end * (RINGS - 1) + ring - 1) * arc_count + step;
	if (step == 0) return end == 0 ? corners.x : corners.y;
	if (step == arc_steps) return end == 0 ? corners.w : corners.z;

	return arc_base + end * (arc_count - 2) + step - 1;
}

void build_fan(uint end, uint tri_base) {
	mat3 anchors = arc_anchors(end);
	vec3 apex = in_positions[corner_vertex(end == 0 ? corners.x : corners.y)];
	bool reverse = end == 1;

	write_vertex(fan_vert(end, 0, 0), apex, vec4(0, 0, 1, 1));

	for (uint ring = 1; ring <= RINGS; ring++) {
		float t = float(ring) / float(RINGS);

		for (uint step = 0; step <= arc_steps; step++) {
			write_vertex(fan_vert(end, ring, step), mix(apex, arc_point(anchors, step), t), vec4(0, 1, 0, 1));
		}
	}

	for (uint step = 0; step < arc_steps; step++) {
		uvec3 tip = uvec3(fan_vert(end, 0, 0), fan_vert(end, 1, step + 1), fan_vert(end, 1, step));
		write_triangle(tri_base + step, tip, reverse);
	}

	for (uint ring = 1; ring < RINGS; ring++) {
		uint band = tri_base + arc_steps + (ring - 1) * arc_steps * 2;

		for (uint step = 0; step < arc_steps; step++) {
			uint a = fan_vert(end, ring, step);
			uint b = fan_vert(end, ring, step + 1);
			uint c = fan_vert(end, ring + 1, step + 1);
			uint d = fan_vert(end, ring + 1, step);

			bool flip = (ring + step) % 2 == 1;

			write_triangle(band + step * 2, flip ? uvec3(a, b, d) : uvec3(a, b, c), reverse);
			write_triangle(band + step * 2 + 1, flip ? uvec3(b, c, d) : uvec3(a, c, d), reverse);
		}
	}
}

void build_strip(uint tri_base) {
	for (uint step = 0; step < arc_steps; step++) {
		uint a = fan_vert(0, RINGS, step);
		uint b = fan_vert(0, RINGS, step + 1);
		uint c = fan_vert(1, RINGS, step + 1);
		uint d = fan_vert(1, RINGS, step);

		write_triangle(tri_base + step * 2, uvec3(a, b, c), false);
		write_triangle(tri_base + step * 2 + 1, uvec3(a, c, d), false);
	}
}

void main() {
	uint edge = gl_GlobalInvocationID.x;

	if (edge >= shared_count) return;

	corners = shared_edges[edge];
	arc_steps = segments * 2;
	arc_count = arc_steps + 1;

	uint fan_verts = 1 + (RINGS - 1) * arc_count + arc_count - 2;
	uint fan_tris = arc_steps + (RINGS - 1) * arc_steps * 2;
	uint corner_count = uint(in_faces.length()) * 3;

	apex_base = corner_count + edge * fan_verts * 2;
	ring_base = apex_base + 2;
	arc_base = ring_base + (RINGS - 1) * arc_count * 2;

	uint tri_base = corner_count + edge * (fan_tris * 2 + arc_steps * 2);

	build_fan(0, tri_base);
	build_fan(1, tri_base + fan_tris);
	build_strip(tri_base + fan_tris * 2);
}
