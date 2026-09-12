// Bridge each shared edge with a fan at both apexes and a strip between their rims
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types : require

const uint COLOR_APEX = 0xFF3030E0; // Red
const uint COLOR_RING = 0xFFE08030; // Blue
const uint COLOR_OUTER = 0xFF30E030; // Green

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	float bevel_width; // Must match bevel_shrink.glsl
	uint steps; // Subdivisions along each ring, per side of the crease
	uint rings; // Rings from the apex out to the retracted verts
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
uint ring_steps; // Segments across a ring - both sides of the crease
uint ring_count; // Verts across a ring, ends included
uint inner_base; // Rings 1..rings-1, every vert new
uint outer_base; // Ring `rings`, minus the two retracted ends

void write_color(uint vert, uint color) {
	out_attributes[(out_color_offset + vert * out_attribute_stride) / 4] = color;
}

void write_vertex(uint vert, vec3 position) {
	uint at = (out_custom_offset + vert * out_attribute_stride) / 4;

	out_positions[vert] = position;
	out_attributes[at] = floatBitsToUint(position.x);
	out_attributes[at + 1] = floatBitsToUint(position.y);
	out_attributes[at + 2] = floatBitsToUint(position.z);
	out_attributes[at + 3] = floatBitsToUint(1.0); // Movable
}

void write_triangle(uint face, uvec3 verts, bool reverse) {
	out_faces[face] = u16vec3(reverse ? verts.xzy : verts);
}

// Anchors: retracted on one face, crease, retracted on the other
vec3 ring_point(mat3 anchors, vec3 apex, uint step) {
	vec3 p = step > steps
	? mix(anchors[1], anchors[2], float(step - steps) / float(steps))
	: mix(anchors[0], anchors[1], float(step) / float(steps));

	// The straight mix cuts inside the circle - push it back out
	float radius = distance(anchors[0], apex);
	vec3 spoke = p - apex;
	float reach = length(spoke);

	return reach < 1e-9 ? p : apex + spoke * (radius / reach);
}

// Retracted is per face, in apex order - the ring at one apex crosses from one face's vert to the other's
uvec2 ring_ends(uint end) {
	return uvec2(edge.retracted[0][end], edge.retracted[1][end]);
}

mat3 ring_anchors(uint end) {
	uvec2 pair = ring_ends(end);

	vec3 apex = out_positions[edge.apexes[end]];
	vec3 along = out_positions[edge.apexes[1 - end]];

	// The ends set the radius - the crease must sit at the same distance or
	// the ring bulges in the middle
	float radius = 0.5 * (distance(out_positions[pair.x], apex) + distance(out_positions[pair.y], apex));
	float t = clamp(radius / max(distance(apex, along), 1e-9), 0.0, 0.5);
	vec3 crease = mix(apex, along, t);

	return mat3(out_positions[pair.x], crease, out_positions[pair.y]);
}

// Ring 0 is the apex, ring `rings` is the outermost, whose ends bevel_shrink already wrote
uint fan_vert(uint end, uint ring, uint step) {
	if (ring == 0) return edge.apexes[end];

	if (ring == rings) {
		uvec2 pair = ring_ends(end);

		if (step == 0) return pair.x;
		if (step == ring_steps) return pair.y;

		return outer_base + end * (ring_count - 2) + step - 1;
	}

	return inner_base + (end * (rings - 1) + ring - 1) * ring_count + step;
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
	mat3 anchors = ring_anchors(end);
	bool reverse = end == 1; // The two apexes sit at opposite ends of the edge

	write_color(apex_vert, COLOR_APEX);

	for (uint ring = 1; ring <= rings; ring++) {
		float t = float(ring) / float(rings);

		for (uint step = 0; step <= ring_steps; step++) {
			uint vert = fan_vert(end, ring, step);

			// The outer ring's ends are shrink's verts, already written
			if (ring == rings && (step == 0 || step == ring_steps)) continue;

			write_vertex(vert, mix(apex, ring_point(anchors, apex, step), t));
			write_color(vert, ring == rings ? COLOR_OUTER : COLOR_RING);
		}
	}

	for (uint step = 0; step < ring_steps; step++) {
		uvec3 tip = uvec3(fan_vert(end, 0, 0), fan_vert(end, 1, step + 1), fan_vert(end, 1, step));
		write_triangle(face_base + step, tip, reverse);
	}

	for (uint ring = 1; ring < rings; ring++) {
		uint band = face_base + ring_steps + (ring - 1) * ring_steps * 2;

		for (uint step = 0; step < ring_steps; step++) {
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
	for (uint step = 0; step < ring_steps; step++) {
		build_quad(
			face_base + step * 2,
			 fan_vert(0, rings, step),
				   fan_vert(0, rings, step + 1),
				   fan_vert(1, rings, step + 1),
				   fan_vert(1, rings, step),
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

	ring_steps = steps * 2;
	ring_count = ring_steps + 1;

	uint fan_verts = (rings - 1) * ring_count + ring_count - 2;
	uint fan_faces = ring_steps + (rings - 1) * ring_steps * 2;

	inner_base = sel_vertex_count + sel_face_count * 3 + idx * fan_verts * 2;
	outer_base = inner_base + (rings - 1) * ring_count * 2;
	uint face_base = sel_face_count + idx * (fan_faces * 2 + ring_steps * 2);

	build_fan(0, face_base);
	build_fan(1, face_base + fan_faces);
	build_strip(face_base + fan_faces * 2);
}
