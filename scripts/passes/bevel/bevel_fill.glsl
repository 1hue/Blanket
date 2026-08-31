// Bridge each shared edge: a fan at both ends, and a strip between their arcs.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types : require

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	float shrink; // Must match bevel_shrink.glsl
	uint segments; // Per side of the crease
	uint arcs; // Rings from apex out to the arc
	uint selected_vertex_count;
	uint selected_face_count;
};

layout(set = 0, binding = 0, scalar) restrict buffer OutVertexBuffer {
	vec3 out_positions[];
};

layout(set = 0, binding = 1, scalar) restrict buffer OutIndexBuffer {
	u16vec3 out_faces[];
};

layout(set = 0, binding = 2, scalar) restrict buffer OutCustom0Buffer {
	vec4 out_origins[];
};

layout(set = 1, binding = 0, scalar) restrict buffer SharedEdgeBuffer {
	uint shared_count;
	uvec4 shared_edges[];
};

uvec4 corners;
uint arc_steps;
uint arc_count;
uint shrunk_base;
uint apex_base;
uint ring_base;
uint arc_base;

void write_vertex(uint vert, vec3 position, vec4 origin) {
	out_positions[vert] = position;
	out_origins[vert] = origin;
}

void write_triangle(uint face, uvec3 verts, bool reverse) {
	out_faces[face] = u16vec3(reverse ? verts.xzy : verts);
}

// Anchors: retracted A, crease, retracted B
vec3 arc_point(mat3 anchors, uint step) {
	return step > segments
	? mix(anchors[1], anchors[2], float(step - segments) / float(segments))
	: mix(anchors[0], anchors[1], float(step) / float(segments));
}

mat3 arc_anchors(uint end) {
	uint near = shrunk_base + (end == 0 ? corners.x : corners.y);
	uint far = shrunk_base + (end == 0 ? corners.w : corners.z);

	// The crease sits on the original edge, so it lies in both faces' planes
	vec3 origin = out_origins[near].xyz;
	vec3 along = out_origins[shrunk_base + (end == 0 ? corners.y : corners.x)].xyz;

	return mat3(out_positions[near], mix(origin, along, shrink), out_positions[far]);
}

// Ring 0 is the apex, ring `arcs` is the arc, whose ends are the retracted corners
uint fan_vert(uint end, uint ring, uint step) {
	uint corner = end == 0 ? corners.x : corners.y;

	if (ring == 0) return apex_base + corner;
	if (ring < arcs) return ring_base + (end * (arcs - 1) + ring - 1) * arc_count + step;
	if (step == 0) return shrunk_base + corner;
	if (step == arc_steps) return shrunk_base + (end == 0 ? corners.w : corners.z);

	return arc_base + end * (arc_count - 2) + step - 1;
}

void build_fan(uint end, uint face_base) {
	uint corner = shrunk_base + (end == 0 ? corners.x : corners.y);
	vec4 origin = out_origins[corner];
	vec3 apex = origin.xyz; // Where the corner sat before shrink pulled it in
	mat3 anchors = arc_anchors(end);
	bool reverse = end == 1; // Ends sit at opposite ends of the edge

	write_vertex(fan_vert(end, 0, 0), apex, origin);

	for (uint ring = 1; ring <= arcs; ring++) {
		float t = float(ring) / float(arcs);

		for (uint step = 0; step <= arc_steps; step++) {
			write_vertex(fan_vert(end, ring, step), mix(apex, arc_point(anchors, step), t), origin);
		}
	}

	for (uint step = 0; step < arc_steps; step++) {
		uvec3 tip = uvec3(fan_vert(end, 0, 0), fan_vert(end, 1, step + 1), fan_vert(end, 1, step));
		write_triangle(face_base + step, tip, reverse);
	}

	for (uint ring = 1; ring < arcs; ring++) {
		uint band = face_base + arc_steps + (ring - 1) * arc_steps * 2;

		for (uint step = 0; step < arc_steps; step++) {
			uint a = fan_vert(end, ring, step);
			uint b = fan_vert(end, ring, step + 1);
			uint c = fan_vert(end, ring + 1, step + 1);
			uint d = fan_vert(end, ring + 1, step);

			bool flip = (ring + step) % 2 == 1; // Alternate the diagonal

			write_triangle(band + step * 2, flip ? uvec3(a, b, d) : uvec3(a, b, c), reverse);
			write_triangle(band + step * 2 + 1, flip ? uvec3(b, c, d) : uvec3(a, c, d), reverse);
		}
	}
}

void build_strip(uint face_base) {
	for (uint step = 0; step < arc_steps; step++) {
		uint a = fan_vert(0, arcs, step);
		uint b = fan_vert(0, arcs, step + 1);
		uint c = fan_vert(1, arcs, step + 1);
		uint d = fan_vert(1, arcs, step);

		// Alternate the diagonal so neither side collects every quad's extra edge
		bool flip = step % 2 == 1;

		write_triangle(face_base + step * 2, flip ? uvec3(a, b, d) : uvec3(a, b, c), false);
		write_triangle(face_base + step * 2 + 1, flip ? uvec3(b, c, d) : uvec3(a, c, d), false);
	}
}

void main() {
	uint edge = gl_GlobalInvocationID.x;

	if (edge >= shared_count) return;

	corners = shared_edges[edge];
	arc_steps = segments * 2;
	arc_count = arc_steps + 1;

	uint fan_verts = (arcs - 1) * arc_count + arc_count - 2;
	uint fan_faces = arc_steps + (arcs - 1) * arc_steps * 2;

	shrunk_base = selected_vertex_count;
	apex_base = shrunk_base + selected_face_count * 3;
	ring_base = apex_base + selected_face_count * 3 + edge * fan_verts * 2;
	arc_base = ring_base + (arcs - 1) * arc_count * 2;

	uint face_base = selected_face_count + edge * (fan_faces * 2 + arc_steps * 2);

	build_fan(0, face_base);
	build_fan(1, face_base + fan_faces);
	build_strip(face_base + fan_faces * 2);
}
