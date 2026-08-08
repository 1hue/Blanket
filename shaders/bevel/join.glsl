// Bridge each original edge with a quad joining the two faces' stand-ins.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types_int16 : require

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	uint in_corner_count;
	uint quad_face_base; // first output face slot for edge quads
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

// The same edge seen from the adjacent face, running the other way
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

void main() {
	uint corner = gl_GlobalInvocationID.x + gl_GlobalInvocationID.y * (gl_NumWorkGroups.x * gl_WorkGroupSize.x);

	if (corner >= in_corner_count) {
		return;
	}

	uint twin = twin_corner(corner);

	// Open edge, or the twin already emitted this quad
	if (twin == 0xFFFFFFFFu || twin < corner) {
		return;
	}

	uint slot = quad_face_base + corner * 2u;
	uint a = corner;
	uint b = next_corner(corner);
	uint c = twin;
	uint d = next_corner(twin);

	out_faces[slot] = u16vec3(a, b, c);
	out_faces[slot + 1u] = u16vec3(a, c, d);
}
