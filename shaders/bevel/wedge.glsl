// Build the ring points that fill the gap at one end of a shared edge.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types_int16 : require

const uint SEGMENTS = 4u; // per side of the crease

layout(local_size_x = 128, local_size_y = 2) in;

layout(push_constant, std430) uniform PushParams {
	float shrink; // must match the value shrink.glsl used
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
	u16vec3 out_faces[];
};

layout(set = 1, binding = 2, std430) restrict buffer OutAttributeBuffer {
	uint out_attributes[];
};

layout(set = 2, binding = 0, scalar) restrict buffer SharedEdgeBuffer {
	uint shared_count;
	uvec2 shared_edges[]; // corner in face A, matching corner in face B
};

uint corner_vertex(uint corner) {
	return uint(in_faces[corner / 3u][corner % 3u]);
}

uint next_corner(uint corner) {
	uint face = corner / 3u;
	return face * 3u + (corner + 1u) % 3u;
}

void main() {
	uint edge = gl_GlobalInvocationID.x;
	uint end = gl_GlobalInvocationID.y; // 0 or 1 - which end of the shared edge

	if (edge >= shared_count) return;

	uvec2 corners = shared_edges[edge];

	// At end 0 the two stand-ins are corner_a and the twin's next corner; at end 1 they swap
	uint corner_a = end == 0u ? corners.x : next_corner(corners.x);
	uint corner_b = end == 0u ? next_corner(corners.y) : corners.y;

	// The vertex this wedge is anchored at, before shrink moved anything
	vec3 origin = in_positions[corner_vertex(corner_a)];
	vec3 far_end = in_positions[corner_vertex(end == 0u ? next_corner(corners.x) : corners.x)];

	// Sits on the shared edge itself, so it lies in both face planes and holds the crease
	vec3 midpoint = mix(origin, far_end, shrink);

	vec3 stand_in_a = out_positions[corner_a];
	vec3 stand_in_b = out_positions[corner_b];

	// Ring points from each face's stand-in to the crease
	vec3 ring_a[SEGMENTS];
	vec3 ring_b[SEGMENTS];

	for (uint i = 0u; i < SEGMENTS; i++) {
		float t = float(i + 1u) / float(SEGMENTS);
		ring_a[i] = mix(stand_in_a, midpoint, t);
		ring_b[i] = mix(stand_in_b, midpoint, t);
	}
}
