// Bridge each shared edge with a fan at both apexes and a strip between their arcs,
// and repoint the selected faces at their retracted verts.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types : require

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	float bevel_width; // Must match bevel_shrink.glsl
	uint segments; // Per side of the crease
	uint arcs; // Rings from apex out to the arc
	uint selected_vertex_count;
	uint selected_face_count;
	uint out_custom_offset;
	uint out_attribute_stride;
};

struct SharedEdge {
	uvec2 apexes;
	uvec2 retracted[2];
};

layout(set = 0, binding = 0, scalar) restrict buffer OutVertexBuffer {
	vec3 out_positions[];
};

layout(set = 0, binding = 1, scalar) restrict buffer OutIndexBuffer {
	u16vec3 out_faces[];
};

layout(set = 0, binding = 2, std430) restrict buffer OutAttributeBuffer {
	uint out_attributes[];
};

layout(set = 1, binding = 0, scalar) restrict buffer SharedEdgeBuffer {
	uint shared_count;
	SharedEdge shared_edges[];
};

SharedEdge edge;
uint arc_steps;
uint arc_count;
uint ring_base;
uint arc_base;

void copy_custom(uint from, uint to) {
	uint source = (out_custom_offset + from * out_attribute_stride) / 4;
	uint target = (out_custom_offset + to * out_attribute_stride) / 4;

	out_attributes[target] = out_attributes[source];
	out_attributes[target + 1] = out_attributes[source + 1];
	out_attributes[target + 2] = out_attributes[source + 2];
	out_attributes[target + 3] = out_attributes[source + 3];
}

void write_vertex(uint vert, vec3 position, uint inherit_from) {
	out_positions[vert] = position;
	copy_custom(inherit_from, vert);
}

void write_triangle(uint face, uvec3 verts, bool reverse) {
	out_faces[face] = u16vec3(reverse ? verts.xzy : verts);
}

// Anchors: retracted on one face, crease, retracted on the other
vec3 arc_point(mat3 anchors, uint step) {
	if (step > segments) {
		return mix(anchors[1], anchors[2], float(step - segments) / float(segments));
	}

	return mix(anchors[0], anchors[1], float(step) / float(segments));
}

mat3 arc_anchors(uint end) {
	uvec2 pair = edge.retracted[end];

	// The crease sits on the original edge, so it lies in both faces' planes
	vec3 apex = out_positions[edge.apexes[end]];
	vec3 along = out_positions[edge.apexes[1 - end]];

	return mat3(out_positions[pair.x], mix(apex, along, bevel_width), out_positions[pair.y]);
}

// Ring 0 is the apex, ring `arcs` is the arc, whose ends are the retracted verts
uint fan_vert(uint end, uint ring, uint step) {
	uvec2 pair = edge.retracted[end];

	if (ring == 0) return edge.apexes[end];
	if (ring < arcs) return ring_base + (end * (arcs - 1) + ring - 1) * arc_count + step;
	if (step == 0) return pair.x;
	if (step == arc_steps) return pair.y;

	return arc_base + end * (arc_count - 2) + step - 1;
}

void build_quad(uint face, uint inner_a, uint inner_b, uint outer_b, uint outer_a, bool flip, bool reverse) {
	if (flip) {
		write_triangle(face, uvec3(inner_a, inner_b, outer_a), reverse);
		write_triangle(face + 1, uvec3(inner_b, outer_b, outer_a), reverse);
		return;
	}

	write_triangle(face, uvec3(inner_a, inner_b, outer_b), reverse);
	write_triangle(face + 1, uvec3(inner_a, outer_b, outer_a), reverse);
}

void build_fan(uint end, uint face_base) {
	uint apex_vert = edge.apexes[end];
	vec3 apex = out_positions[apex_vert];
	mat3 anchors = arc_anchors(end);
	bool reverse = end == 1; // The two apexes sit at opposite ends of the edge

	for (uint ring = 1; ring <= arcs; ring++) {
		float t = float(ring) / float(arcs);

		for (uint step = 0; step <= arc_steps; step++) {
			uint vert = fan_vert(end, ring, step);

			// The arc's ends are shrink's verts, already written
			if (ring == arcs && (step == 0 || step == arc_steps)) continue;

			write_vertex(vert, mix(apex, arc_point(anchors, step), t), apex_vert);
		}
	}

	for (uint step = 0; step < arc_steps; step++) {
		uvec3 tip = uvec3(fan_vert(end, 0, 0), fan_vert(end, 1, step + 1), fan_vert(end, 1, step));
		write_triangle(face_base + step, tip, reverse);
	}

	for (uint ring = 1; ring < arcs; ring++) {
		uint band = face_base + arc_steps + (ring - 1) * arc_steps * 2;

		for (uint step = 0; step < arc_steps; step++) {
			build_quad(
				band + step * 2,
				fan_vert(end, ring, step),
				fan_vert(end, ring, step + 1),
				fan_vert(end, ring + 1, step + 1),
				fan_vert(end, ring + 1, step),
				(ring + step) % 2 == 1, // Alternate the diagonal
				reverse
			);
		}
	}
}

void build_strip(uint face_base) {
	for (uint step = 0; step < arc_steps; step++) {
		build_quad(
			face_base + step * 2,
			fan_vert(0, arcs, step),
			fan_vert(0, arcs, step + 1),
			fan_vert(1, arcs, step + 1),
			fan_vert(1, arcs, step),
			step % 2 == 1, // Alternate so neither side collects every extra edge
			false
		);
	}
}

void main() {
	uint idx = gl_GlobalInvocationID.x;

	// Selected faces now point at the retracted verts shrink wrote
	if (idx < selected_face_count) {
		uint base = selected_vertex_count + idx * 3;
		out_faces[idx] = u16vec3(base, base + 1, base + 2);
	}

	if (idx >= shared_count) return;

	edge = shared_edges[idx];
	arc_steps = segments * 2;
	arc_count = arc_steps + 1;

	uint fan_verts = (arcs - 1) * arc_count + arc_count - 2;
	uint fan_faces = arc_steps + (arcs - 1) * arc_steps * 2;

	ring_base = selected_vertex_count + selected_face_count * 3 + idx * fan_verts * 2;
	arc_base = ring_base + (arcs - 1) * arc_count * 2;

	uint face_base = selected_face_count + idx * (fan_faces * 2 + arc_steps * 2);

	build_fan(0, face_base);
	build_fan(1, face_base + fan_faces);
	build_strip(face_base + fan_faces * 2);
}
