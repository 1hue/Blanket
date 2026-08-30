// Give each surviving vertex a dense slot in the new surface, merging by position.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types : require

const uint EMPTY = 0xFFFFFFFFu;

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	uint table_size; // Power of two
};

layout(set = 0, binding = 0, scalar) restrict readonly buffer InVertexBuffer {
	vec3 in_positions[];
};

layout(set = 0, binding = 1, scalar) restrict readonly buffer InIndexBuffer {
	u16vec3 in_faces[]; // Unused
};

layout(set = 0, binding = 2, std430) restrict buffer InAttributeBuffer {
	uint in_attributes[]; // Unused
};

layout(set = 1, binding = 0, scalar) restrict buffer FacesBuffer {
	uint face_count;
	uint vertex_count; // Survivors found, and the new surface's vertex count
	u16vec3 faces[];
};

layout(set = 2, binding = 0, std430) restrict buffer FacesTableBuffer {
	uint table[]; // Per table slot: the vertex holding that position, cleared to EMPTY
};

layout(set = 3, binding = 0, std430) restrict buffer FacesSlotBuffer {
	uint16_t slots[]; // Per source vertex: its dense slot, valid only for survivors
};

layout(set = 4, binding = 0, std430) restrict buffer FacesDedupeDispatchBuffer {
	uvec3 dispatch; // Indirect args for faces_write.glsl - its own buffer, since the one
	// dispatching this pass cannot also be bound to it
};

uint hash(vec3 position) {
	uvec3 bits = floatBitsToUint(position);
	uint h = bits.x * 0x9E3779B1u ^ bits.y * 0x85EBCA6Bu ^ bits.z * 0xC2B2AE35u;

	h ^= h >> 16;
	h *= 0x7FEB352Du;
	h ^= h >> 15;

	return h;
}

// First vertex to claim a position keeps it - everyone else adopts its index
uint survivor_of(uint vert) {
	vec3 position = in_positions[vert];
	uint slot = hash(position) & (table_size - 1);

	for (uint probe = 0; probe < table_size; probe++) {
		uint holder = atomicCompSwap(table[slot], EMPTY, vert);

		if (holder == EMPTY) return vert;
		if (in_positions[holder] == position) return holder;

		slot = (slot + 1) & (table_size - 1); // Different position, collision - try the next slot
	}

	return vert; // Table full, which sizing should prevent
}

void main() {
	uint face = gl_GlobalInvocationID.x;

	if (face >= face_count) return;

	u16vec3 corners = faces[face];

	// A corner claiming its own position is the first to reach it, so it gets a slot
	for (uint c = 0; c < 3; c++) {
		uint vert = corners[c];

		if (survivor_of(vert) == vert) {
			slots[vert] = uint16_t(atomicAdd(vertex_count, 1));
		}
	}

	atomicMax(dispatch.x, (face + 256) / 256);
	dispatch.y = 1;
	dispatch.z = 1;
}
