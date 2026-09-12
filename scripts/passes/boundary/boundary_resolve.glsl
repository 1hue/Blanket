// Resolve each boundary endpoint to the column of verts its wall's top edge meets
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types : require

layout(local_size_x = 64) in;

layout(push_constant, std430) uniform PushParams {
	uint steps; // Subdivisions along each ring, per side of the crease
	uint rings; // Rings from the apex out to the retracted verts
};

struct SharedEdge {
	uvec2 faces;
	uvec2 apexes;
	uvec2 retracted[2]; // Per face, in apex order
};

struct BoundaryEdge {
	uvec2 verts;
	uint face;
	uint corner;
	uvec2 top[4];
};

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
};

layout(set = 3, binding = 1, scalar) restrict buffer SelectedIndexBuffer {
	uint sel_face_count;
};

bool is_shared(uint mask, uint edge) {
	return (mask & (1u << edge)) != 0u;
}

uint retracted_at(uint face, uint corner) {
	return sel_vertex_count + 3 * face + corner;
}

// bevel_fill lays its fans out per shared edge - mirror its addressing exactly
uint ring_vert(uint idx, uint end, uint side, uint ring) {
	uint ring_steps = steps * 2;
	uint ring_count = ring_steps + 1;
	uint fan_verts = (rings - 1) * ring_count + ring_count - 2;
	uint inner_base = sel_vertex_count + sel_face_count * 3 + idx * fan_verts * 2;

	return inner_base + (end * (rings - 1) + ring - 1) * ring_count + side * ring_steps;
}

// The inner rings sit on the segment from the apex out to the retracted vert,
// so they land on this wall's top edge. Verts are deduped by position, so the
// first shared edge at this apex is as good as any
void resolve(uint idx, uint slot, uint apex, uint retracted) {
	boundary_edges[idx].top[0][slot] = apex;
	boundary_edges[idx].top[rings][slot] = retracted;

	if (rings < 2) return;

	for (uint i = 0; i < shared_edge_count; i++) {
		SharedEdge edge = shared_edges[i];

		for (uint end = 0; end < 2; end++) {
			if (edge.apexes[end] != apex) continue;

			// Which side of the ring runs toward our retracted vert
			uint side = edge.retracted[0][end] == retracted ? 0u : 1u;

			for (uint ring = 1; ring < rings; ring++) {
				boundary_edges[idx].top[ring][slot] = ring_vert(i, end, side, ring);
			}

			return;
		}
	}

	// No fan here - collapse the row onto the retracted vert
	for (uint ring = 1; ring < rings; ring++) {
		boundary_edges[idx].top[ring][slot] = retracted;
	}
}

void main() {
	uint idx = gl_GlobalInvocationID.x;

	if (idx >= boundary_count) return;

	BoundaryEdge boundary = boundary_edges[idx];
	uint mask = face_edge_mask[boundary.face];
	uint prev = (boundary.corner + 2u) % 3u;
	uint next = (boundary.corner + 1u) % 3u;

	// The boundary edge is never shared, so retraction comes down to the
	// corner's other edge. Where there is none, the column collapses
	uint retracted_x = is_shared(mask, prev) ? retracted_at(boundary.face, boundary.corner) : boundary.verts.x;
	uint retracted_y = is_shared(mask, next) ? retracted_at(boundary.face, next) : boundary.verts.y;

	resolve(idx, 0, boundary.verts.x, retracted_x);
	resolve(idx, 1, boundary.verts.y, retracted_y);
}
