// List every edge shared by two selected faces, store the apex verts.
// Anchor the verts on the boundary.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types : require

const uint FILL_GROUP_SIZE = 256;

// X = face, Y = corner (the edge running from that corner to the next)
layout(local_size_x = 64, local_size_y = 3) in;

layout(push_constant, std430) uniform PushParams {
	uint selected_vertex_count;
	uint selected_face_count;
	uint out_custom_offset;
	uint out_attribute_stride;
};

struct SharedEdge {
	uvec2 faces; // Which 2 faces in index_buffer
	uvec2 apexes; // 2 indices forming the shared edge
	uvec2 retracted[2]; // Resultant edges, per face
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
	// Zero-initialised but (0,0) is a degenerate edge, even if 0 is a valid vert index
	layout(offset = 16) SharedEdge shared_edges[];
};

// Bit c set = edge c of this face is shared. Retraction reads only this.
layout(set = 2, binding = 0, std430) restrict buffer SharedMaskBuffer {
	uint shared_mask[];
};

layout(set = 3, binding = 0, std430) restrict buffer DispatchBuffer {
	uvec3 dispatch; // Indirect bevel_fill.glsl
};

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

uvec2 edge_at_corner(uint global_corner) {
	uint face = global_corner / 3;

	return sorted_edge(edge_at(uvec3(out_faces[face]), global_corner % 3));
}

// Every corner gets its own retracted vert, so the slot is just its address.
// Returned in apex order, since apexes are sorted and corners are wound.
uvec2 retracted_at_corner(uint global_corner, uvec2 apexes) {
	uvec3 corners = uvec3(out_faces[global_corner / 3]);
	uint corner = global_corner % 3;
	uvec2 pair = uvec2(corner, (corner + 1) % 3);

	if (corners[corner] != apexes.x) pair = pair.yx;

	return selected_vertex_count + 3 * (global_corner / 3) + pair;
}

// w = 1 marks vert as sticky
void anchor(uint vert) {
	out_attributes[(out_custom_offset + vert * out_attribute_stride) / 4 + 3] = 1;
}

void main() {
	uint face = gl_GlobalInvocationID.x;
	uint corner = gl_GlobalInvocationID.y;

	// Uniform across the dispatch, so one invocation seeds it for everyone
	if (face == 0 && corner == 0) {
		// Fill repoints every selected face too, so its dispatch must cover them all
		atomicMax(dispatch.x, (selected_face_count + FILL_GROUP_SIZE - 1) / FILL_GROUP_SIZE);
		dispatch.y = 1;
		dispatch.z = 1;
	}

	if (face >= selected_face_count) return;

	uint self = face * 3 + corner;
	uvec2 edge = edge_at_corner(self);
	bool has_twin = false;

	for (uint twin = 0; twin < selected_face_count * 3; twin++) {
		if (twin == self || edge_at_corner(twin) != edge) continue;

		has_twin = true;

		if (twin < self) continue;

		uint slot = atomicAdd(shared_count, 1);

		shared_edges[slot].faces = uvec2(face, twin / 3);
		shared_edges[slot].apexes = edge;
		shared_edges[slot].retracted[0] = retracted_at_corner(self, edge);
		shared_edges[slot].retracted[1] = retracted_at_corner(twin, edge);

		atomicMax(dispatch.x, (slot + FILL_GROUP_SIZE) / FILL_GROUP_SIZE);
	}

	if (has_twin) {
		// Retraction needs both edges at a corner; each is found by its own lane
		atomicOr(shared_mask[face], 1 << corner);
	} else {
		anchor(edge.x);
		anchor(edge.y);
	}
}
