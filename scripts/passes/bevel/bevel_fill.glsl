// Bridge each shared edge with a fan at both apexes and a strip between their arcs.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types : require

const uint COLOR_APEX = 0xFF3030E0; // Red
const uint COLOR_RING = 0xFFE08030; // Blue
const uint COLOR_ARC = 0xFF30E030; // Green

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	float bevel_width; // Must match bevel_shrink.glsl
	uint segments; // Per side of the crease
	uint arcs; // Rings from apex out to the arc
	uint out_color_offset;
	uint out_custom_offset;
	uint out_attribute_stride;
};

struct SharedEdge {
	uvec2 faces; // Unused here, but part of the layout
	uvec2 apexes;
	uvec2 retracted[2]; // Per face, in apex order
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

layout(set = 1, binding = 0, scalar) restrict buffer SelectedVertexBuffer {
	uint sel_vertex_count;
	vec3 sel_positions[]; // unused
};

layout(set = 1, binding = 1, scalar) restrict buffer SelectedIndexBuffer {
	uint sel_face_count;
	uvec3 sel_faces[]; // unused
};

layout(set = 2, binding = 0, scalar) restrict buffer SharedEdgeBuffer {
	uint shared_edge_count;
	SharedEdge shared_edges[];
};

SharedEdge edge;
uint arc_steps;
uint arc_count;
uint ring_base;
uint arc_base;

void write_color(uint vert, uint color) {
	out_attributes[(out_color_offset + vert * out_attribute_stride) / 4] = color;
}

void write_vertex(uint vert, vec3 position) {
	uint at = (out_custom_offset + vert * out_attribute_stride) / 4;

	out_positions[vert] = position;
	out_attributes[at] = floatBitsToUint(position.x);
	out_attributes[at + 1] = floatBitsToUint(position.y);
	out_attributes[at + 2] = floatBitsToUint(position.z);
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

// Retracted is per face, in apex order - the arc at one apex crosses from one face's vert to the other's
uvec2 arc_ends(uint end) {
	return uvec2(edge.retracted[0][end], edge.retracted[1][end]);
}

mat3 arc_anchors(uint end) {
	uvec2 pair = arc_ends(end);

	// The crease sits on the original edge, so it lies in both faces' planes
	vec3 apex = out_positions[edge.apexes[end]];
	vec3 along = out_positions[edge.apexes[1 - end]];
	float t = clamp(bevel_width / max(distance(apex, along), 1e-9), 0.0, 0.5);
	vec3 crease = mix(apex, along, t);

	return mat3(out_positions[pair.x], crease, out_positions[pair.y]);
}

// Ring 0 is the apex, ring `arcs` is the arc, whose ends are the retracted verts
uint fan_vert(uint end, uint ring, uint step) {
	if (ring == 0) return edge.apexes[end];

	uvec2 pair = arc_ends(end);

	if (ring == arcs) {
		if (step == 0) return pair.x;
		if (step == arc_steps) return pair.y;

		return arc_base + end * (arc_count - 2) + step - 1;
	}

	return ring_base + (end * (arcs - 1) + ring - 1) * arc_count + step;
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

	write_color(apex_vert, COLOR_APEX);

	for (uint ring = 1; ring <= arcs; ring++) {
		float t = float(ring) / float(arcs);

		for (uint step = 0; step <= arc_steps; step++) {
			uint vert = fan_vert(end, ring, step);

			// The arc's ends are shrink's verts, already written
			if (ring == arcs && (step == 0 || step == arc_steps)) continue;

			write_vertex(vert, mix(apex, arc_point(anchors, step), t));
			write_color(vert, ring == arcs ? COLOR_ARC : COLOR_RING);
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

	if (idx >= shared_edge_count) return;

	edge = shared_edges[idx];

	// (0, 0) is zero-init = degenerate edge
	if (edge.apexes.x == edge.apexes.y) return;

	arc_steps = segments * 2;
	arc_count = arc_steps + 1;

	uint fan_verts = (arcs - 1) * arc_count + arc_count - 2;
	uint fan_faces = arc_steps + (arcs - 1) * arc_steps * 2;

	ring_base = sel_vertex_count + sel_face_count * 3 + idx * fan_verts * 2;
	arc_base = ring_base + (arcs - 1) * arc_count * 2;
	uint face_base = sel_face_count + idx * (fan_faces * 2 + arc_steps * 2);

	build_fan(0, face_base);
	build_fan(1, face_base + fan_faces);
	build_strip(face_base + fan_faces * 2);
}
