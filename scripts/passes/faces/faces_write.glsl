// Copy the selection into the new surface, merged verts sharing one slot.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types : require

const uint EMPTY = 0xFFFFFFFFu;

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	uint table_size;
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
	uint vertex_count;
	u16vec3 faces[];
};

layout(set = 2, binding = 0, std430) restrict buffer FacesTableBuffer {
	uint table[];
};

layout(set = 3, binding = 0, scalar) restrict buffer FacesSlotBuffer {
	uint16_t slots[];
};

layout(set = 4, binding = 0, scalar) restrict writeonly buffer FacesOutVertexBuffer {
	vec3 out_positions[];
};

layout(set = 4, binding = 1, scalar) restrict writeonly buffer FacesOutIndexBuffer {
	u16vec3 out_faces[];
};

layout(set = 4, binding = 2, std430) restrict writeonly buffer FacesOutCustom0Buffer {
	vec4 out_origins[];
};

uint hash(vec3 position) {
	uvec3 bits = floatBitsToUint(position);
	uint h = bits.x * 0x9E3779B1u ^ bits.y * 0x85EBCA6Bu ^ bits.z * 0xC2B2AE35u;

	h ^= h >> 16;
	h *= 0x7FEB352Du;
	h ^= h >> 15;

	return h;
}

// Walks the table faces_dedupe.glsl built
uint survivor_of(uint vert) {
	vec3 position = in_positions[vert];
	uint slot = hash(position) & (table_size - 1);

	for (uint probe = 0; probe < table_size; probe++) {
		uint holder = table[slot];

		if (holder == EMPTY) return vert;
		if (in_positions[holder] == position) return holder;

		slot = (slot + 1) & (table_size - 1);
	}

	return vert;
}

void main() {
	uint face = gl_GlobalInvocationID.x;

	if (face >= face_count) return;

	u16vec3 corners = faces[face];
	uvec3 merged = uvec3(survivor_of(corners.x), survivor_of(corners.y), survivor_of(corners.z));
	u16vec3 dense = u16vec3(slots[merged.x], slots[merged.y], slots[merged.z]);

	out_faces[face] = dense;

	// Merged corners share a slot, so these writes land on top of each other harmlessly
	out_positions[dense.x] = in_positions[merged.x];
	out_positions[dense.y] = in_positions[merged.y];
	out_positions[dense.z] = in_positions[merged.z];
}
