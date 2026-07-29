#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require

layout(local_size_x = 256) in;

layout(set = 0, binding = 0, scalar) restrict readonly buffer CountBuffer {
	uvec3 dispatch;
	uint counter;
	uvec3 eligible[];
};

layout(set = 1, binding = 0, scalar) restrict buffer OuterBuffer {
	uint outer_counter;
	uvec2 outer_edges[];
};

uvec2 edge_at(uint edge) {
	uvec3 tri = eligible[edge / 3u];
	uint corner = edge % 3u;

	if (corner == 0u) {
		return tri.xy;
	}
	if (corner == 1u) {
		return tri.yz;
	}
	return tri.zx;
}

bool same_edge(uvec2 a, uvec2 b) {
	return all(equal(a, b)) || all(equal(a, b.yx));
}

void main() {
	uint edge = gl_GlobalInvocationID.x + gl_GlobalInvocationID.y * (gl_NumWorkGroups.x * gl_WorkGroupSize.x);
	uint edge_count = counter * 3u;

	if (edge >= edge_count) {
		return;
	}

	uvec2 mine = edge_at(edge);

	for (uint other = 0u; other < edge_count; other++) {
		if (other != edge && same_edge(mine, edge_at(other))) {
			return;
		}
	}

	outer_edges[atomicAdd(outer_counter, 1u)] = mine;
}
