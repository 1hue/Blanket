// SPDX-FileCopyrightText: © 2026 1hue
// SPDX-License-Identifier: MIT

// Work out which vertices each rim skirt hangs from
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types : require

#include "../common.glsl.inc"

layout(constant_id = 0) const uint BEVEL_SEGMENTS = 1;
layout(constant_id = 1) const uint ARCS = 1;

const uint SEGMENTS = BEVEL_SEGMENTS * 2;
const uint ARC_VERTS = SEGMENTS + 1;

layout(local_size_x = BOUNDARY_WORKGROUP_SIZE) in;

layout(push_constant, std430) uniform PushParams {
	uint max_edges;
};

layout(set = 0, binding = 0, scalar) restrict buffer BoundaryBuffer {
	uint boundary_count;
	uint boundary_vert_count; // unused
	BoundaryEdge boundary_edges[];
};

layout(set = 1, binding = 0, std430) restrict buffer FaceEdgeBuffer {
	FaceEdge face_edges[];
};

layout(set = 2, binding = 0, scalar) restrict buffer SharedEdgeBuffer {
	uint shared_edge_count;
	SharedEdge shared_edges[];
};

layout(set = 3, binding = 0, scalar) restrict buffer SelectedVertexBuffer {
	uint sel_vertex_count;
	vec3 sel_positions[]; // unused
};

layout(set = 3, binding = 1, scalar) restrict buffer SelectedIndexBuffer {
	uint sel_face_count;
	uvec3 sel_faces[]; // unused
};

#include "../face_edge.glsl.inc"

// bevel_fill lays its fans out per shared edge - mirror its addressing exactly
uint arc_vert(uint idx, uint end, uint side, uint arc) {
	uint fan_verts = (ARCS - 1) * ARC_VERTS + ARC_VERTS - 2;
	uint inner_base = sel_vertex_count + sel_face_count * 3 + idx * fan_verts * 2;

	return inner_base + (end * (ARCS - 1) + arc - 1) * ARC_VERTS + side * SEGMENTS;
}

// The inner arcs sit on the segment from the apex out to the retracted vert,
// so they land on this wall's top edge. Verts are deduped by position, so the
// first shared edge at this apex is as good as any
void resolve(uint idx, uint slot, uint apex, uint retracted) {
	boundary_edges[idx].top[0][slot] = apex;
	boundary_edges[idx].top[ARCS][slot] = retracted;

	if (ARCS < 2) return;

	for (uint i = 0; i < shared_edge_count; i++) {
		for (uint end = 0; end < 2; end++) {
			if (shared_edges[i].apexes[end] != apex) continue;

			// Which side of the arc runs toward our retracted vert
			uint side = shared_edges[i].retracted[0][end] == retracted ? 0u : 1u;

			for (uint arc = 1; arc < ARCS; arc++) {
				boundary_edges[idx].top[arc][slot] = arc_vert(i, end, side, arc);
			}

			return;
		}
	}

	// No fan here - collapse the column onto the retracted vert
	for (uint arc = 1; arc < ARCS; arc++) {
		boundary_edges[idx].top[arc][slot] = retracted;
	}
}

void main() {
	uint idx = gl_GlobalInvocationID.x;

	// boundary_count counts attempts, not slots - overflow ones were never written
	if (idx >= min(boundary_count, max_edges)) return;

	uvec2 verts = boundary_edges[idx].verts;
	uint face = boundary_edges[idx].face;
	uint corner = boundary_edges[idx].corner;
	uint prev = prev_corner(corner);
	uint next = next_corner(corner);

	// The boundary edge is never shared, so retraction comes down to the corner's other edge.
	// Where there is none, the column collapses
	uint retracted_x = is_creased(face, prev) ? retracted_at(face, corner) : verts.x;
	uint retracted_y = is_creased(face, next) ? retracted_at(face, next) : verts.y;

	resolve(idx, 0, verts.x, retracted_x);
	resolve(idx, 1, verts.y, retracted_y);
}
