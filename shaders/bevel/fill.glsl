// Fill the hole left at each original vertex by fanning its stand-ins.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types_int16 : require

const uint MAX_VALENCE = 32u;

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	uint in_corner_count;
	uint fan_face_base; // first output face slot for vertex fans
};

layout(set = 0, binding = 0, scalar) restrict readonly buffer InVertexBuffer {
	vec3 in_positions[];
};

layout(set = 0, binding = 1, scalar) restrict readonly buffer InIndexBuffer {
	u16vec3 in_faces[];
};

layout(set = 1, binding = 0, scalar) restrict writeonly buffer OutVertexBuffer {
	vec3 out_positions[];
};

layout(set = 1, binding = 1, scalar) restrict writeonly buffer OutIndexBuffer {
	u16vec3 out_faces[];
};

uint corner_vertex(uint corner) {
	return uint(in_faces[corner / 3u][corner % 3u]);
}

uint next_corner(uint corner) {
	uint face = corner / 3u;
	return face * 3u + (corner + 1u) % 3u;
}

uint twin_corner(uint corner) {
	uint v0 = corner_vertex(corner);
	uint v1 = corner_vertex(next_corner(corner));

	for (uint other = 0u; other < in_corner_count; other++) {
		if (corner_vertex(other) == v1 && corner_vertex(next_corner(other)) == v0) {
			return other;
		}
	}
	return 0xFFFFFFFFu;
}

// Step to the next stand-in rotating around the shared vertex
uint rotate_around(uint corner) {
	uint twin = twin_corner(corner);
	return twin == 0xFFFFFFFFu ? 0xFFFFFFFFu : next_corner(twin);
}

void main() {
	uint corner = gl_GlobalInvocationID.x + gl_GlobalInvocationID.y * (gl_NumWorkGroups.x * gl_WorkGroupSize.x);

	if (corner >= in_corner_count) {
		return;
	}

	// Only the lowest-numbered stand-in emits the fan for its vertex
	uint ring[MAX_VALENCE];
	uint count = 0u;
	uint walk = corner;

	do {
		if (walk < corner) {
			return;
		}
		ring[count++] = walk;
		walk = rotate_around(walk);
	} while (walk != corner && walk != 0xFFFFFFFFu && count < MAX_VALENCE);

	// Open vertex - ring never closed, skip rather than emit a wrong fan
	if (walk != corner || count < 3u) {
		return;
	}

	uint slot = fan_face_base + corner * (MAX_VALENCE - 2u);
	for (uint i = 1u; i + 1u < count; i++) {
		out_faces[slot + i - 1u] = u16vec3(ring[0], ring[i], ring[i + 1u]);
	}
}
