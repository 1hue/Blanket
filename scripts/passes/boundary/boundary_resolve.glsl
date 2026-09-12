// Resolve each boundary endpoint to the column of verts its wall's top edge meets
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types : require

#include "../common.glsl.inc"

layout(constant_id = 0) const uint SEGMENTS = 1;
layout(constant_id = 1) const uint RINGS = 1;

const uint RING_STEPS = SEGMENTS * 2; // Segments across a ring, both sides of the crease
const uint RING_COUNT = RING_STEPS + 1;

layout(local_size_x = 64) in;

layout(set = 0, binding = 0, scalar) restrict buffer BoundaryBuffer {
	uint boundary_count;
	BoundaryEdge boundary_edges[];
};

layout(set = 1, binding = 0, std430) restrict buffer FaceEdgeMaskBuffer {
	uint face_edge_mask[];
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

bool is_shared(uint mask, uint edge) {
	return (mask & (1u << edge)) != 0u;
}

// bevel_shrink gives every retracted corner its own slot, addressed by face and corner
uint retracted_at(uint face, uint corner) {
	return sel_vertex_count + 3 * face + corner;
}

// bevel_fill lays its fans out per shared edge - mirror its addressing exactly
uint ring_vert(uint idx, uint end, uint side, uint ring) {
	uint fan_verts = (RINGS - 1) * RING_COUNT + RING_COUNT - 2;
	uint inner_base = sel_vertex_count + sel_face_count * 3 + idx * fan_verts * 2;

	return inner_base + (end * (RINGS - 1) + ring - 1) * RING_COUNT + side * RING_STEPS;
}

// The inner rings sit on the segment from the apex out to the retracted vert,
// so they land on this wall's top edge. Verts are deduped by position, so the
// first shared edge at this apex is as good as any
void resolve(uint idx, uint slot, uint apex, uint retracted) {
	boundary_edges[idx].top[0][slot] = apex;
	boundary_edges[idx].top[RINGS][slot] = retracted;

	if (RINGS < 2) return;

	for (uint i = 0; i < shared_edge_count; i++) {
		for (uint end = 0; end < 2; end++) {
			if (shared_edges[i].apexes[end] != apex) continue;

			// Which side of the ring runs toward our retracted vert
			uint side = shared_edges[i].retracted[0][end] == retracted ? 0u : 1u;

			for (uint ring = 1; ring < RINGS; ring++) {
				boundary_edges[idx].top[ring][slot] = ring_vert(i, end, side, ring);
			}

			return;
		}
	}

	// No fan here - collapse the column onto the retracted vert
	for (uint ring = 1; ring < RINGS; ring++) {
		boundary_edges[idx].top[ring][slot] = retracted;
	}
}

void main() {
	uint idx = gl_GlobalInvocationID.x;

	if (idx >= boundary_count) return;

	uvec2 verts = boundary_edges[idx].verts;
	uint face = boundary_edges[idx].face;
	uint corner = boundary_edges[idx].corner;
	uint mask = face_edge_mask[face];
	uint prev = (corner + 2u) % 3u;
	uint next = (corner + 1u) % 3u;

	// The boundary edge is never shared, so retraction comes down to the
	// corner's other edge. Where there is none, the column collapses
	uint retracted_x = is_shared(mask, prev) ? retracted_at(face, corner) : verts.x;
	uint retracted_y = is_shared(mask, next) ? retracted_at(face, next) : verts.y;

	resolve(idx, 0, verts.x, retracted_x);
	resolve(idx, 1, verts.y, retracted_y);

// 	if (idx == 0 && boundary_count > 1) {
// 		boundary_edges[1].face = RINGS;
// 		boundary_edges[1].corner = boundary_edges[1].top.length();
// 	}
}
