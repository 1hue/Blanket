// Find the outer boundary - edges belonging to only one selected face.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require

const uint VERTS_GROUP_SIZE = 256u;

// X = faces, Y = 3 verts per face
layout(local_size_x = 1) in;

layout(push_constant, std430) uniform PushParams {
	uint in_vertex_stride;
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

layout(set = 1, binding = 0, scalar) restrict buffer FacesBuffer {
	uint faces_count;
	uvec3 faces[]; // input: eligible faces from faces.glsl
};

layout(set = 1, binding = 1, scalar) restrict buffer EdgesBuffer {
	uint edges_count;
	uvec2 edges[]; // output: boundary edges (walls)
};

layout(set = 2, binding = 0, std430) restrict buffer EdgesDispatchBuffer {
	uvec3 dispatch;
};

vec3 read_in_position(uint in_index) {
	uint word = (in_index * in_vertex_stride) / 4u;
	return vec3(
		uintBitsToFloat(in_words[word]),
		uintBitsToFloat(in_words[word + 1u]),
		uintBitsToFloat(in_words[word + 2u])
	);
}

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
	vec3 a0 = read_in_position(a.x);
	vec3 a1 = read_in_position(a.y);
	vec3 b0 = read_in_position(b.x);
	vec3 b1 = read_in_position(b.y);

	return (a0 == b0 && a1 == b1) || (a0 == b1 && a1 == b0);
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
