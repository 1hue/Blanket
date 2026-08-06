// Assign each used source vertex a compacted slot, merging duplicates by position + normal.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	uint in_vertex_count;
	uint in_vertex_stride;
	uint in_normal_offset;
	uint in_normal_stride;
};

layout(set = 0, binding = 0, std430) restrict readonly buffer InVertexBuffer {
	uint in_words[];
};

layout(set = 0, binding = 1, std430) restrict readonly buffer InIndexBuffer {
	uint in_index_words[]; // unused here
};

layout(set = 0, binding = 2, std430) restrict buffer InAttributeBuffer {
	uint in_attribute_words[]; // unused here
};

layout(set = 3, binding = 0, std430) restrict buffer SlotBuffer {
	uint unique_count;
	uint slots[]; // per source vertex: compacted out slot, or 0xFFFFFFFF if unused
};

layout(set = 3, binding = 1, std430) restrict buffer UsedBuffer {
	uint used[]; // per source vertex: 1 if any selected face references it
};

vec3 read_in_position(uint in_index) {
	uint word = (in_index * in_vertex_stride) / 4u;
	return vec3(
		uintBitsToFloat(in_words[word]),
		uintBitsToFloat(in_words[word + 1u]),
		uintBitsToFloat(in_words[word + 2u])
	);
}

vec3 oct_decode(vec2 e) {
	vec3 v = vec3(e.xy, 1.0 - abs(e.x) - abs(e.y));
	vec2 wrapped = (1.0 - abs(v.yx)) * sign(v.xy);
	v.xy = mix(v.xy, wrapped, step(v.z, 0.0));
	return normalize(v);
}

vec3 read_in_normal(uint in_index) {
	uint word = (in_normal_offset + in_index * in_normal_stride) / 4u;
	vec2 e = fma(unpackUnorm2x16(in_words[word]), vec2(2.0), vec2(-1.0));
	return oct_decode(e);
}

bool same_vertex(uint a, uint b) {
	return read_in_position(a) == read_in_position(b) && read_in_normal(a) == read_in_normal(b);
}

// First used vertex sharing this position + normal - always the lowest index, so every
// duplicate agrees on it without any coordination between threads.
uint canonical_of(uint i) {
	for (uint other = 0u; other < i; other++) {
		if (used[other] == 1u && same_vertex(other, i)) {
			return other;
		}
	}
	return i;
}

void main() {
	uint i = gl_GlobalInvocationID.x + gl_GlobalInvocationID.y * (gl_NumWorkGroups.x * gl_WorkGroupSize.x);

	if (i >= in_vertex_count || used[i] == 0u) {
		return;
	}

	uint canonical = canonical_of(i);

	// Compacted slot is simply how many canonical vertices precede mine - no atomics, no ordering
	uint slot = 0u;
	for (uint other = 0u; other < canonical; other++) {
		if (used[other] == 1u && canonical_of(other) == other) {
			slot++;
		}
	}

	slots[i] = slot;

	// Only canonicals contribute to the total
	if (canonical == i) {
		atomicAdd(unique_count, 1u);
	}
}
