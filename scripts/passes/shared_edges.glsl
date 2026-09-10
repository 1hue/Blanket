// Find every edge shared by two selected faces, store the apex verts.
// Anchor the verts on the boundary and record its edges for the wall.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types : require

const uint OUT_MESH_WORKGROUP_SIZE = 64;
const uint FILL_WORKGROUP_SIZE = 256;
const uint BOUNDARY_WORKGROUP_SIZE = 64;
const uint FLAG_BOUNDARY = 1;

// X = face, Y = corner (the edge running from that corner to the next)
layout(local_size_x = 64, local_size_y = 3) in;

layout(push_constant, std430) uniform PushParams {
	uint max_shared_edges;
	uint max_boundary_edges;
	float crease_dot; // Max face-vs-face dot to still bevel
};

struct SharedEdge {
	uvec2 faces; // Which 2 faces in index_buffer
	uvec2 apexes; // 2 indices forming the shared edge
	uvec2 retracted[2]; // Resultant edges, per face
};

layout(set = 0, binding = 0, scalar) restrict buffer SelectedVertexBuffer {
	uint sel_vertex_count;
	vec3 sel_positions[];
};

layout(set = 0, binding = 1, scalar) restrict buffer SelectedIndexBuffer {
	uint sel_face_count;
	uvec3 sel_faces[];
};

layout(set = 1, binding = 0, scalar) restrict buffer SharedEdgeBuffer {
	uint shared_edge_count;
	SharedEdge shared_edges[];
};

// Bit c set = edge c of this face is shared. Retraction reads only this.
layout(set = 2, binding = 0, std430) restrict buffer FaceEdgeMaskBuffer {
	uint face_edge_mask[];
};

// Bit 0 set = vert lies on the selection boundary
layout(set = 3, binding = 0, std430) restrict buffer VertexFlagBuffer {
	uint vertex_flags[];
};

layout(set = 4, binding = 0, scalar) restrict buffer BoundaryBuffer {
	uint boundary_count;
	uvec2 boundary_edges[]; // Face winding order - the wall needs the direction
};

layout(set = 5, binding = 0, scalar) restrict buffer DispatchBuffer {
	layout(offset = 36) uvec3 dispatch_out_mesh;
	layout(offset = 60) uvec3 dispatch_fill;
	uvec3 dispatch_boundary;
};

vec3 face_normal(uint face) {
	uvec3 corners = sel_faces[face];
	vec3 p0 = sel_positions[corners.x];
	vec3 p1 = sel_positions[corners.y];
	vec3 p2 = sel_positions[corners.z];

	return normalize(cross(p1 - p0, p2 - p0));
}

// Near-coplanar faces get no bevel - the crease isn't visible enough to be worth the geometry
bool is_creased(uint face_a, uint face_b) {
	return dot(face_normal(face_a), face_normal(face_b)) < crease_dot;
}

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

	return sorted_edge(edge_at(sel_faces[face], global_corner % 3));
}

// Every corner gets its own retracted vert, so the slot is just its address.
// Returned in apex order, since apexes are sorted and corners are wound.
uvec2 retracted_at_corner(uint global_corner, uvec2 apexes) {
	uvec3 corners = sel_faces[global_corner / 3];
	uint corner = global_corner % 3;
	uvec2 pair = uvec2(corner, (corner + 1) % 3);

	if (corners[corner] != apexes.x) pair = pair.yx;

	return sel_vertex_count + 3 * (global_corner / 3) + pair;
}

// Boundary verts are pinned - the wall row anchors them while the surface lifts
void mark_boundary(uint vert) {
	atomicOr(vertex_flags[vert], FLAG_BOUNDARY);
}

// Winding order matters here, so take the edge unsorted
void record_boundary(uint face, uint corner, uvec2 edge) {
	uint slot = atomicAdd(boundary_count, 1);

	if (slot >= max_boundary_edges) return;

	boundary_edges[slot] = edge_at(sel_faces[face], corner);

	atomicMax(dispatch_boundary.x, 1 + slot / BOUNDARY_WORKGROUP_SIZE);

	mark_boundary(edge.x);
	mark_boundary(edge.y);
}

// The pair is recorded once, by the lower lane. False means the edge is too flat to bevel
bool match_twin(uint self, uint twin, uvec2 edge) {
	uint face = self / 3;

	if (!is_creased(face, twin / 3)) return false; // Flat enough to leave alone
	if (twin < self) return true; // The other lane records it

	uint slot = atomicAdd(shared_edge_count, 1);

	if (slot >= max_shared_edges) return true; // Buffer overflowed

	shared_edges[slot].faces = uvec2(face, twin / 3);
	shared_edges[slot].apexes = edge;
	shared_edges[slot].retracted[0] = retracted_at_corner(self, edge);
	shared_edges[slot].retracted[1] = retracted_at_corner(twin, edge);

	atomicMax(dispatch_fill.x, 1 + slot / FILL_WORKGROUP_SIZE);

	return true;
}

void main() {
	uint face = gl_GlobalInvocationID.x;
	uint corner = gl_GlobalInvocationID.y;

	// Uniform across the dispatch, so one invocation seeds it for everyone
	if (face == 0 && corner == 0) {
		uint lanes = max(sel_vertex_count, sel_face_count);

		atomicMax(dispatch_out_mesh.x, (lanes + OUT_MESH_WORKGROUP_SIZE - 1) / OUT_MESH_WORKGROUP_SIZE);
		atomicMax(dispatch_fill.x, (sel_face_count + FILL_WORKGROUP_SIZE - 1) / FILL_WORKGROUP_SIZE);
	}

	if (face >= sel_face_count) return;

	uint self = face * 3 + corner;
	uvec2 edge = edge_at_corner(self);
	bool has_twin = false;
	bool is_shared_edge = false;

	for (uint twin = 0; twin < sel_face_count * 3; twin++) {
		if (twin == self || edge_at_corner(twin) != edge) continue;

		has_twin = true; // Topology only - anchoring must not depend on the crease test
		is_shared_edge = match_twin(self, twin, edge) || is_shared_edge;
	}

	if (is_shared_edge) {
		// Retraction needs both edges at a corner; each is found by its own lane
		atomicOr(face_edge_mask[face], 1u << corner);
	}

	if (!has_twin) {
		record_boundary(face, corner, edge);
	}
}
