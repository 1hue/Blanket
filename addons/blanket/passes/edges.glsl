// Find every edge shared by two selected faces, store the apex verts.
// Mark the verts on the boundary and record its edges for the wall.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types : require

#include "common.glsl.inc"

// X = face, Y = corner (the edge running from that corner to the next)
layout(local_size_x = EDGES_WORKGROUP_SIZE, local_size_y = 3) in;

layout(push_constant, std430) uniform PushParams {
	uint max_edges;
	float crease_dot;
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

// One entry per corner - the twin's address, or 0 where the edge is the selection's rim
layout(set = 2, binding = 0, std430) restrict buffer FaceEdgeBuffer {
	FaceEdge face_edges[];
};

// Bit 0 set = vert lies on the selection boundary
layout(set = 3, binding = 0, std430) restrict buffer VertexFlagBuffer {
	uint vertex_flags[];
};

layout(set = 4, binding = 0, scalar) restrict buffer BoundaryBuffer {
	uint boundary_count;
	uint boundary_vert_count;
	BoundaryEdge boundary_edges[];
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

// AB = BA, so compare sorted and two corners share an edge iff their pairs match
uvec2 sorted_edge(uvec2 edge) {
	return uvec2(min(edge.x, edge.y), max(edge.x, edge.y));
}

// Edge `corner` runs from that corner to the next one round
uvec2 edge_at(uvec3 corners, uint corner) {
	if (corner == 0) return corners.xy;
	if (corner == 1) return corners.yz;

	return corners.zx;
}

// Wound as this face sees it - only the twin search wants it sorted
uvec2 wound_edge_at_corner(uint global_corner) {
	return edge_at(sel_faces[global_corner / 3], global_corner % 3);
}

uvec2 edge_at_corner(uint global_corner) {
	return sorted_edge(wound_edge_at_corner(global_corner));
}

// Every corner gets its own retracted vert, so the slot is just its address.
// Returned in apex order, so the two faces' pairs line up for the fill strip
uvec2 retracted_at_corner(uint global_corner, uvec2 apexes) {
	uint corner = global_corner % 3;
	uvec2 pair = uvec2(corner, (corner + 1) % 3);

	// Two faces sharing an edge wind it opposite ways, so one of them flips
	if (sel_faces[global_corner / 3][corner] != apexes.x) pair = pair.yx;

	return sel_vertex_count + 3 * (global_corner / 3) + pair;
}

void mark_boundary(uint vert) {
	uint prev = atomicOr(vertex_flags[vert], FLAG_BOUNDARY);

	if ((prev & FLAG_BOUNDARY) != 0u) return; // Someone else got here first

	uint slot = atomicAdd(boundary_vert_count, 1);

	atomicOr(vertex_flags[vert], (slot + 1) << FLAG_BITS);
}

void record_boundary(uint self, uvec2 edge) {
	uint slot = atomicAdd(boundary_count, 1);

	if (slot >= max_edges) return;

	// The mask isn't settled yet - boundary.glsl resolves the retracted verts later
	boundary_edges[slot].verts = wound_edge_at_corner(self);
	boundary_edges[slot].face = self / 3;
	boundary_edges[slot].corner = self % 3;

	atomicMax(dispatch_boundary.x, 1 + slot / BOUNDARY_WORKGROUP_SIZE);

	mark_boundary(edge.x);
	mark_boundary(edge.y);
}

// Records the pair once, by the lower lane. Flat edges are recorded too - fill
// still has a gap to close where an adjacent crease pulled a corner back
void match_twin(uint self, uint twin, bool creased) {
	if (twin < self) return; // The other lane records it

	uint slot = atomicAdd(shared_edge_count, 1);

	if (slot >= max_edges) return; // Buffer overflowed

	uint face = self / 3;
	uvec2 apexes = wound_edge_at_corner(self);

	shared_edges[slot].faces = uvec2(face, twin / 3);
	shared_edges[slot].apexes = apexes;
	shared_edges[slot].retracted[0] = retracted_at_corner(self, apexes);
	shared_edges[slot].retracted[1] = retracted_at_corner(twin, apexes);
	shared_edges[slot].crease = creased ? 1u : 0u;

	atomicMax(dispatch_fill.x, 1 + slot / FILL_WORKGROUP_SIZE);
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
	bool is_creased = false;

	for (uint twin = 0; twin < sel_face_count * 3; twin++) {
		if (twin == self || edge_at_corner(twin) != edge) continue;

		has_twin = true;
		is_creased = dot(face_normal(face), face_normal(twin / 3)) <= crease_dot;

		// Only this lane writes its own entry, so no atomics needed
		face_edges[self].twin = twin + 1;
		face_edges[self].creased = is_creased ? 1u : 0u;

		match_twin(self, twin, is_creased);
	}

	if (!has_twin) {
		record_boundary(self, edge);
	}
}
