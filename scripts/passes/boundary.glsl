// Skirt each boundary edge: a fan at each rim corner, a centred quad above it,
// flat wall below. Everything lies on the rim at rest - W is what raises it
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types : require

const uint COLOR_WALL = 0xFF20C0E0; // Amber
const float RISE_INNER = 0.5; // Where the wall folds, as a fraction of depth
const float RISE_CENTER = 0.75; // Midway between the fold and the surface
// Must match BoundaryPass.ARC_VERTS and BoundaryPass.FACES
const uint ARC_VERTS = 5; // Inner pair, retracted rim pair, centre
const uint FACES = 12; // 2 fans, 2 notches, 4 centre, 2 fold, 2 wall

layout(local_size_x = 64) in;

layout(push_constant, std430) uniform PushParams {
	uint sel_vertex_count; // Base of bevel_shrink's retracted slots
	uint wall_rim_base;
	uint wall_arc_base;
	uint wall_face_base;
	float bevel_width;
	uint out_color_offset;
	uint out_custom_offset;
	uint out_attribute_stride;
};

struct BoundaryEdge {
	uvec2 verts;
	uint face;
	uint corner;
};

layout(set = 0, binding = 0, scalar) restrict buffer OutVertexBuffer {
	vec3 out_positions[];
};

layout(set = 0, binding = 1, scalar) restrict buffer OutIndexBuffer {
	u16vec3 out_faces[];
};

layout(set = 0, binding = 2, std430) restrict buffer OutAttributeBuffer {
	uint out_attributes[];
};

layout(set = 1, binding = 0, scalar) restrict buffer BoundaryBuffer {
	uint boundary_count;
	BoundaryEdge boundary_edges[];
};

layout(set = 2, binding = 0, std430) restrict buffer FaceEdgeMaskBuffer {
	uint face_edge_mask[];
};

void write_vertex(uint vert, vec3 rest, float rise) {
	uint at = (out_custom_offset + vert * out_attribute_stride) / 4;

	out_positions[vert] = rest;
	out_attributes[at] = floatBitsToUint(rest.x);
	out_attributes[at + 1] = floatBitsToUint(rest.y);
	out_attributes[at + 2] = floatBitsToUint(rest.z);
	out_attributes[at + 3] = floatBitsToUint(rise); // Fraction of depth this vert travels

	out_attributes[(out_color_offset + vert * out_attribute_stride) / 4] = COLOR_WALL;
}

uint rim_vert(uint vert) {
	return wall_rim_base + vert;
}

bool is_shared(uint mask, uint edge) {
	return (mask & (1u << edge)) != 0u;
}

// bevel_shrink gives every retracted corner its own slot, addressed by face and corner
uint retracted_at(uint face, uint corner) {
	return sel_vertex_count + 3 * face + corner;
}

// The boundary edge itself is never shared, so retraction comes down to the other
// edge at that corner. Where there is none, the surface vert stands in and the
// extra triangle collapses
uint top_vert(uint face, uint corner, uint other_edge, uint fallback) {
	return is_shared(face_edge_mask[face], other_edge) ? retracted_at(face, corner) : fallback;
}

void write_quad(uint face, uvec4 ring, bool flip) {
	out_faces[face] = u16vec3(flip ? ring.xyw : ring.xyz);
	out_faces[face + 1] = u16vec3(flip ? ring.yzw : ring.xzw);
}

void main() {
	uint idx = gl_GlobalInvocationID.x;

	if (idx >= boundary_count) return;

	BoundaryEdge boundary = boundary_edges[idx];
	uvec2 edge = boundary.verts;
	uint prev = (boundary.corner + 2u) % 3u;
	uint next = (boundary.corner + 1u) % 3u;

	uint top_x = top_vert(boundary.face, boundary.corner, prev, edge.x);
	uint top_y = top_vert(boundary.face, next, next, edge.y);

	vec3 rim_x = out_positions[edge.x];
	vec3 rim_y = out_positions[edge.y];

	// Both corners fold inward, so neither may claim more than half the rim
	float span = distance(rim_x, rim_y);
	vec3 along = span > 1e-9 ? (rim_y - rim_x) / span : vec3(0.0);
	float inset = min(bevel_width, span * 0.5);

	uint inner_x = wall_arc_base + idx * ARC_VERTS;
	uint inner_y = inner_x + 1;
	uint rim_inner_x = inner_x + 2;
	uint rim_inner_y = inner_x + 3;
	uint center = inner_x + 4;

	// Redundant where edges meet, but every lane writes the same value
	write_vertex(rim_vert(edge.x), rim_x, 0.0);
	write_vertex(rim_vert(edge.y), rim_y, 0.0);

	// The fold and its footing retract by the same amount, one raised one not
	write_vertex(inner_x, rim_x + along * inset, RISE_INNER);
	write_vertex(inner_y, rim_y - along * inset, RISE_INNER);
	write_vertex(rim_inner_x, rim_x + along * inset, 0.0);
	write_vertex(rim_inner_y, rim_y - along * inset, 0.0);
	write_vertex(center, mix(rim_x, rim_y, 0.5), RISE_CENTER);

	uint face_base = wall_face_base + idx * FACES;

	// Corner fans - one triangle each, folding the wall around the rim vert
	out_faces[face_base] = u16vec3(inner_x, edge.x, rim_vert(edge.x));
	out_faces[face_base + 1] = u16vec3(edge.y, inner_y, rim_vert(edge.y));

	// Degenerate unless the corner retracted, in which case it closes the notch
	out_faces[face_base + 2] = u16vec3(top_x, edge.x, inner_x);
	out_faces[face_base + 3] = u16vec3(edge.y, top_y, inner_y);

	// The remaining hole, fanned off a centre vert so it shades evenly
	out_faces[face_base + 4] = u16vec3(center, top_x, inner_x);
	out_faces[face_base + 5] = u16vec3(top_y, top_x, center);
	out_faces[face_base + 6] = u16vec3(inner_y, top_y, center);
	out_faces[face_base + 7] = u16vec3(center, inner_x, inner_y);

	// The fold continues down to its footing on the rim
	out_faces[face_base + 8] = u16vec3(inner_x, rim_vert(edge.x), rim_inner_x);
	out_faces[face_base + 9] = u16vec3(rim_vert(edge.y), inner_y, rim_inner_y);

	// Flat wall below the fold
	write_quad(face_base + 10, uvec4(inner_y, inner_x, rim_inner_x, rim_inner_y), idx % 2 == 1);
}
