// Copy the selection into the new surface, merged verts sharing one slot.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require

const uint EMPTY = 0xFFFFFFFFu;

struct TableEntry {
	uint vert; // Source vertex holding this position, EMPTY if free
	uint out_vert; // Where its position lives in the scratch buffer
};

layout(constant_id = 0) const uint WORKGROUP_SIZE = 1;

layout(local_size_x_id = 0, local_size_y = 3) in; // X = face, Y = corner

layout(set = 0, binding = 0, scalar) restrict readonly buffer InVertexBuffer {
	vec3 in_positions[];
};

layout(set = 0, binding = 1, scalar) restrict readonly buffer InIndexBuffer {
	uint in_faces[]; // unused
};

layout(set = 0, binding = 2, std430) restrict buffer InAttributeBuffer {
	uint in_attributes[]; // unused
};

layout(set = 1, binding = 0, scalar) restrict buffer SelectedVertexBuffer {
	uint sel_vertex_count;
	vec3 sel_positions[]; // unused
};

layout(set = 1, binding = 1, scalar) restrict buffer SelectedIndexBuffer {
	uint sel_face_count;
	uvec3 sel_faces[];
};

layout(set = 2, binding = 0, scalar) restrict buffer FacesTableBuffer {
	uint table_size;
	layout(offset = 8) TableEntry table[];
};

uint hash(vec3 position) {
	uvec3 bits = floatBitsToUint(position);
	uint h = bits.x * 0x9E3779B1u ^ bits.y * 0x85EBCA6Bu ^ bits.z * 0xC2B2AE35u;

	h ^= h >> 16;
	h *= 0x7FEB352Du;
	h ^= h >> 15;

	return h;
}

uint out_vert_of(uint vert) {
	vec3 position = in_positions[vert];
	uint slot = hash(position) & (table_size - 1);

	for (uint probe = 0; probe < table_size; probe++) {
		TableEntry entry = table[slot];

		if (entry.vert == EMPTY) break; // Unreachable: dedupe claimed every corner
		if (in_positions[entry.vert] == position) return entry.out_vert;

		slot = (slot + 1) & (table_size - 1);
	}

	return 0;
}

void main() {
	uint face = gl_GlobalInvocationID.x;
	uint corner = gl_GlobalInvocationID.y;

	if (face >= sel_face_count || corner > 2) return;

	sel_faces[face][corner] = out_vert_of(sel_faces[face][corner]);
}
