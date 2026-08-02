// Finds the outer boundary - edges belonging to only one selected face
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require

const uint VERTS_GROUP_SIZE = 256u;

layout(local_size_x = 256) in;

layout(set = 0, binding = 0, scalar) restrict readonly buffer FacesBuffer {
	uvec3 faces_dispatch;
	uint faces_count;
	uvec3 faces[]; // input: eligible faces from faces.glsl
};

layout(set = 1, binding = 0, scalar) restrict buffer EdgesBuffer {
	uvec3 dispatch; // indirect args for verts.glsl
	uint edges_count;
	uvec2 edges[]; // output: boundary edges (walls)
};

uvec2 edge_at(uint edge) {
	uvec3 face = faces[edge / 3u];
	uint corner = edge % 3u;

	if (corner == 0u) {
		return face.xy;
	}
	if (corner == 1u) {
		return face.yz;
	}
	return face.zx;
}

bool same_edge(uvec2 a, uvec2 b) {
	return all(equal(a, b)) || all(equal(a, b.yx));
}

void main() {
	uint edge = gl_GlobalInvocationID.x + gl_GlobalInvocationID.y * (gl_NumWorkGroups.x * gl_WorkGroupSize.x);
	uint total_edges = faces_count * 3u;

	if (edge >= total_edges) {
		return;
	}

	uvec2 current = edge_at(edge);

	for (uint other = 0u; other < total_edges; other++) {
		if (other != edge && same_edge(current, edge_at(other))) {
			return;
		}
	}

	uint slot = atomicAdd(edges_count, 1u);
	edges[slot] = current;
	atomicMax(dispatch.x, (faces_count + slot + VERTS_GROUP_SIZE) / VERTS_GROUP_SIZE);
	dispatch.y = 1u;
	dispatch.z = 1u;
}
