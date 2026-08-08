// Sum neighbour positions per vertex - centre verts need the full ring average, not per-triangle.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	uint out_index_count;
	uint out_vertex_stride;
	uint out_index_stride;
};

layout(set = 0, binding = 0, std430) restrict readonly buffer OutVertexBuffer {
	uint out_words[];
};

layout(set = 0, binding = 1, std430) restrict readonly buffer OutIndexBuffer {
	uint out_index_words[];
};

layout(set = 1, binding = 0, std430) restrict buffer NeighbourBuffer {
	uint neighbour_sums[]; // 4 uints per vertex: x, y, z as fixed point, then count
};

const float FIXED_SCALE = 65536.0;

uint read_index(uint i) {
	if (out_index_stride == 2u) {
		uint word = out_index_words[i / 2u];
		return i % 2u == 0u ? (word & 0xFFFFu) : (word >> 16u);
	}
	return out_index_words[i];
}

vec3 read_position(uint v) {
	uint word = (v * out_vertex_stride) / 4u;
	return vec3(
		uintBitsToFloat(out_words[word]),
		uintBitsToFloat(out_words[word + 1u]),
		uintBitsToFloat(out_words[word + 2u])
	);
}

// Fixed point so the sum can be atomic - float atomics need an extension
void add_neighbour(uint v, vec3 position) {
	uint base = v * 4u;
	atomicAdd(neighbour_sums[base], uint(int(position.x * FIXED_SCALE)));
	atomicAdd(neighbour_sums[base + 1u], uint(int(position.y * FIXED_SCALE)));
	atomicAdd(neighbour_sums[base + 2u], uint(int(position.z * FIXED_SCALE)));
	atomicAdd(neighbour_sums[base + 3u], 1u);
}

void main() {
	uint tri = gl_GlobalInvocationID.x + gl_GlobalInvocationID.y * (gl_NumWorkGroups.x * gl_WorkGroupSize.x);

	if (tri * 3u + 2u >= out_index_count) {
		return;
	}

	uint a = read_index(tri * 3u);
	uint b = read_index(tri * 3u + 1u);
	uint c = read_index(tri * 3u + 2u);

	vec3 pa = read_position(a);
	vec3 pb = read_position(b);
	vec3 pc = read_position(c);

	// Each corner sees the other two - duplicated across shared edges, which the average absorbs
	add_neighbour(a, pb);
	add_neighbour(a, pc);
	add_neighbour(b, pa);
	add_neighbour(b, pc);
	add_neighbour(c, pa);
	add_neighbour(c, pb);
}
