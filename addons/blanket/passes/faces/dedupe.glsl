// Merge vertices by position and place each survivor in the scratch buffer
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require

#include "../common.glsl.inc"

const uint EMPTY = 0xFFFFFFFFu;

struct TableEntry {
	uint vert; // Source vertex holding this position, EMPTY if free
	uint out_vert; // Where its position lives in the scratch buffer
};

layout(local_size_x = DEDUPE_WORKGROUP_SIZE, local_size_y = 3) in; // X = face, Y = corner

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
	vec3 sel_positions[];
};

layout(set = 1, binding = 1, scalar) restrict buffer SelectedIndexBuffer {
	uint sel_face_count;
	uvec3 sel_faces[];
};

layout(set = 2, binding = 0, scalar) restrict buffer FacesTableBuffer {
	uint table_size;
	layout(offset = 8) TableEntry table[];
};

layout(set = 3, binding = 0, scalar) restrict buffer DispatchBuffer {
	layout(offset = 12) uvec3 dispatch_faces;
	layout(offset = 24) uvec3 dispatch_edges;
	layout(offset = 48) uvec3 dispatch_shrink;
};

uint hash(vec3 position) {
	uvec3 bits = floatBitsToUint(position);
	uint h = bits.x * 0x9E3779B1u ^ bits.y * 0x85EBCA6Bu ^ bits.z * 0xC2B2AE35u;

	h ^= h >> 16;
	h *= 0x7FEB352Du;
	h ^= h >> 15;

	return h;
}

void main() {
	uint face = gl_GlobalInvocationID.x;
	uint corner = gl_GlobalInvocationID.y;

	if (face >= sel_face_count) return;

	// A corner claiming its own position is the first to reach it, so it gets a slot
	uint vert = sel_faces[face][corner];
	vec3 position = in_positions[vert];
	uint slot = hash(position) & (table_size - 1);

	for (uint probe = 0; probe < table_size; probe++) {
		uint holder = atomicCompSwap(table[slot].vert, EMPTY, vert);

		if (holder == EMPTY) {
			uint out_vert = atomicAdd(sel_vertex_count, 1);

			table[slot].out_vert = out_vert;
			sel_positions[out_vert] = position; // Claimant is the survivor, so write it here
			break;
		}

		if (in_positions[holder] == position) break; // Already has a slot

		slot = (slot + 1) & (table_size - 1);
	}

	if (corner == 0) {
		atomicMax(dispatch_faces.x, 1 + face / FACES_WORKGROUP_SIZE);
		atomicMax(dispatch_edges.x, 1 + face / EDGES_WORKGROUP_SIZE);
		atomicMax(dispatch_shrink.x, 1 + face / SHRINK_WORKGROUP_SIZE);
	}
}
