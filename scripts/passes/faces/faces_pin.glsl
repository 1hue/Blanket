// Pin the verts on the selection's outer boundary, where an edge has no neighbouring face.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types : require

const float PINNED = 1;

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	uint out_marker_offset;
	uint out_color_offset;
	uint out_attribute_stride;
};

layout(set = 0, binding = 0, scalar) restrict writeonly buffer OutVertexBuffer {
	vec3 out_positions[]; // Unused
};

layout(set = 0, binding = 1, scalar) restrict buffer OutIndexBuffer {
	u16vec3 out_faces[];
};

layout(set = 0, binding = 2, std430) restrict buffer OutAttributeBuffer {
	uint out_attributes[];
};

layout(set = 1, binding = 0, scalar) restrict buffer FacesBuffer {
	uint face_count;
	uint vertex_count;
	u16vec3 faces[]; // Unused - dedupe made out_faces the authority
};

// Dedupe merged the verts, so a shared edge is now the same index pair in both faces
bool has_neighbour(uvec2 edge, uint face) {
	for (uint other = 0; other < face_count; other++) {
		if (other == face) continue;

		uvec3 corners = uvec3(out_faces[other]);

		for (uint c = 0; c < 3; c++) {
			uvec2 candidate = uvec2(corners[c], corners[(c + 1) % 3]);

			if (edge == candidate || edge == candidate.yx) return true;
		}
	}

	return false;
}

void write_color(uint vert, vec4 color) {
	out_attributes[(out_color_offset + vert * out_attribute_stride) / 4] = packUnorm4x8(color);
}

void main() {
	uint face = gl_GlobalInvocationID.x;

	if (face >= face_count) return;

	uvec3 corners = uvec3(out_faces[face]);

	// Both ends of an unshared edge are pinned - faces meeting there write the same value
	for (uint c = 0; c < 3; c++) {
		uint next = (c + 1) % 3;

		if (has_neighbour(uvec2(corners[c], corners[next]), face)) continue;

		write_color(corners[c], vec4(1, 1, 0, 1));
		write_color(corners[next], vec4(1, 1, 0, 1));

		out_attributes[(out_marker_offset + corners[c] * out_attribute_stride) / 4] = floatBitsToUint(PINNED);
		out_attributes[(out_marker_offset + corners[next] * out_attribute_stride) / 4] = floatBitsToUint(PINNED);
	}
}
