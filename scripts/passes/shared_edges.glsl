// List every edge shared by two selected faces, store the apex verts.
// Anchor the verts on the boundary.
// X = face, Y = edge.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types : require

const uint NONE = 0xFFFFFFFFu;
const uint FILL_GROUP_SIZE = 256;

layout(local_size_x = 64, local_size_y = 3) in;

// One corner per invocation per tile
const uint TILE_SIZE = gl_WorkGroupSize.x * gl_WorkGroupSize.y;

layout(push_constant, std430) uniform PushParams {
	uint selected_face_count;
	uint out_custom_offset;
	uint out_attribute_stride;
};

struct SharedEdge {
	uvec2 apexes; // Original ends of edge A_B, sorted
	uvec2 retracted[2]; // [A1_B1, A2_B2], written by shrink
};

layout(set = 0, binding = 0, scalar) restrict buffer OutVertexBuffer {
	vec3 out_positions[]; // Unused
};

layout(set = 0, binding = 1, scalar) restrict buffer OutIndexBuffer {
	u16vec3 out_faces[];
};

layout(set = 0, binding = 2, std430) restrict buffer OutAttributeBuffer {
	uint out_attributes[];
};

layout(set = 1, binding = 0, scalar) restrict buffer SharedEdgeBuffer {
	uint shared_count;
	SharedEdge shared_edges[]; // Initial values are 0 (a valid vert index), but (0,0) is a degenerate edge
};

layout(set = 2, binding = 0, std430) restrict buffer DispatchBuffer {
	uvec3 dispatch; // Indirect bevel_fill.glsl
};

// Two pages: the group scans one while the next is fetched into the other
shared uvec2 tile_edges[2][TILE_SIZE];

// AB = BA, so store sorted and two corners share an edge iff their pairs match
uvec2 sorted_edge(uvec2 edge) {
	return uvec2(min(edge.x, edge.y), max(edge.x, edge.y));
}

// Edge `corner` runs from that corner to the next one round
uvec2 edge_at(uvec3 corners, uint corner) {
	if (corner == 0) return corners.xy;
	if (corner == 1) return corners.yz;

	return corners.zx;
}

// Out of range corners are never compared, so any value will do
uvec2 edge_at_corner(uint global_corner) {
	uint face = global_corner / 3;

	if (face >= selected_face_count) return uvec2(0);

	return sorted_edge(edge_at(out_faces[face], global_corner % 3));
}

// w = 1 anchors the vert, so nothing downstream moves it
void anchor(uint vert) {
	out_attributes[(out_custom_offset + vert * out_attribute_stride) / 4 + 3] = floatBitsToUint(1);
}

void main() {
	uint local = gl_LocalInvocationIndex;
	uint self = gl_WorkGroupID.x * TILE_SIZE + local;
	uint corner_count = selected_face_count * 3;

	// Fill repoints every selected face too, so its dispatch must cover them all.
	// Uniform across the dispatch, so one invocation seeds it for everyone
	if (gl_WorkGroupID.x == 0 && local == 0) {
		atomicMax(dispatch.x, (selected_face_count + FILL_GROUP_SIZE - 1) / FILL_GROUP_SIZE);
		dispatch.y = 1;
		dispatch.z = 1;
	}

	// Out of range invocations stay resident: the tile loop barriers are group wide
	bool in_range = self < corner_count;

	uvec2 edge = edge_at_corner(self);
	uint twin = NONE;

	tile_edges[0][local] = edge_at_corner(local);

	uint tile_count = (corner_count + TILE_SIZE - 1) / TILE_SIZE;

	for (uint tile = 0; tile < tile_count; tile++) {
		uint base = tile * TILE_SIZE;
		uint current_page = tile % 2;
		uint next_page = (tile + 1) % 2;

		barrier();

		// Nobody reads the next page this pass, so the fetch races nothing
		tile_edges[next_page][local] = edge_at_corner(base + TILE_SIZE + local);

		if (in_range && twin == NONE) {
			uint span = min(TILE_SIZE, corner_count - base);

			for (uint i = 0; i < span; i++) {
				uint other = base + i;

				if (other == self) continue;

				if (tile_edges[current_page][i] == edge) {
					twin = other;
					break;
				}
			}
		}
	}

	// Nothing on the far side, so both ends anchor the selection
	if (in_range && twin == NONE) {
		anchor(edge.x);
		anchor(edge.y);
		return;
	}

	// Both corners find each other, so only the lower one lists the edge
	if (!in_range || self > twin) return;

	uint slot = atomicAdd(shared_count, 1);

	shared_edges[slot].apexes = edge;

	atomicMax(dispatch.x, (slot + FILL_GROUP_SIZE) / FILL_GROUP_SIZE);
}
