// Retract each selected face from its shared edges
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types : require

// X = face, Y = corner
layout(local_size_x = 64, local_size_y = 3) in;

layout(push_constant, std430) uniform PushParams {
	float shrink; // 0 = unchanged, 1 = moved onto the opposite corner
	uint selected_vertex_count;
	uint selected_face_count;
	uint out_custom_offset;
	uint out_attribute_stride;
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
	uint shared_count; // unused
};

// Bit c set = edge c of this face is shared. Retraction reads only this.
layout(set = 1, binding = 1, std430) restrict buffer FaceEdgeBuffer {
	uint shared_mask[];
};

void copy_attributes(uint src, uint dst) {
	uint s = src * out_attribute_stride;
	uint d = dst * out_attribute_stride;
	for (uint i = out_custom_offset; i < out_attribute_stride; ++i) {
		out_attributes[d + i] = out_attributes[s + i];
	}
}

// Edge c runs from corner c to corner c+1, so corner c sits on edges c and c-1
uint next_corner(uint corner) {
	return (corner + 1) % 3;
}

uint prev_corner(uint corner) {
	return (corner + 2) % 3;
}

bool is_shared(uint mask, uint edge) {
	return (mask & (1 << edge)) != 0;
}

bool retracts(uint mask, uint corner) {
	return is_shared(mask, corner) || is_shared(mask, prev_corner(corner));
}

uint retracted_at(uint face_idx, uint corner) {
	return selected_vertex_count + 3 * face_idx + corner;
}

void main() {
	uint face_idx = gl_GlobalInvocationID.x;
	uint corner = gl_GlobalInvocationID.y;
	if (face_idx >= selected_face_count) return;

	uint mask = shared_mask[face_idx];
	uvec3 face = uvec3(out_faces[face_idx]);

	// One lane owns the u16vec3 store: three lanes writing 2-byte components
	// of a 6-byte element risks dword read-modify-write on some drivers
	if (corner == 0) {
		uvec3 repointed = face;

		for (uint i = 0; i < 3; ++i) {
			if (retracts(mask, i)) repointed[i] = retracted_at(face_idx, i);
		}

		out_faces[face_idx] = u16vec3(repointed);
	}

	if (!retracts(mask, corner)) return;

	uint next = next_corner(corner);
	uint prev = prev_corner(corner);
	vec3 apex = out_positions[face[corner]];
	vec3 pull = vec3(0);

	// Each shared edge pulls the corner toward the vert it doesn't touch.
	// Both are corners of this face, so one lane holds the whole inset -
	// no accumulation, no competing writes, no ordering
	if (is_shared(mask, corner)) {
		pull += out_positions[face[prev]] - apex;
	}
	if (is_shared(mask, prev)) {
		pull += out_positions[face[next]] - apex;
	}

	uint slot = retracted_at(face_idx, corner);

	out_positions[slot] = apex + shrink * pull;
	copy_attributes(face[corner], slot);
}
