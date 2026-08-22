// Merge duplicate positions, assigning each survivor a compacted slot.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types_int16 : require

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	uint vertex_count; // Buffer holds normals past the positions, so length() overruns
};

layout(set = 0, binding = 0, std430) restrict buffer SlotBuffer {
	uint unique_count;
	uint slots[]; // Per vertex: its compacted slot
};

layout(set = 1, binding = 0, scalar) restrict readonly buffer OutVertexBuffer {
	vec3 out_positions[];
};

layout(set = 1, binding = 1, scalar) restrict readonly buffer OutIndexBuffer {
	u16vec3 out_faces[];
};

layout(set = 1, binding = 2, std430) restrict buffer OutAttributeBuffer {
	uint out_attributes[]; // Unused
};

// Lowest-indexed vertex sharing this position, so every duplicate agrees without coordination
uint canonical_of(uint vert) {
	vec3 position = out_positions[vert];

	for (uint other = 0; other < vert; other++) {
		if (out_positions[other] == position) {
			return other;
		}
	}

	return vert;
}

void main() {
	uint vert = gl_GlobalInvocationID.x + gl_GlobalInvocationID.y * (gl_NumWorkGroups.x * gl_WorkGroupSize.x);

	if (vert >= vertex_count) return;

	uint canonical = canonical_of(vert);

	// Slot is however many canonicals precede mine
	uint slot = 0;
	for (uint other = 0; other < canonical; other++) {
		if (canonical_of(other) == other) {
			slot++;
		}
	}

	slots[vert] = slot;

	if (canonical == vert) {
		atomicAdd(unique_count, 1);
	}
}
