// Fill each boundary edge's wall: a quad grid from the rim up to the surface.
// Everything lies on the rim at rest - W is what raises it
#[versions]
out_u16 = "#define OUT_INDEX_TYPE u16vec3";
out_u32 = "#define OUT_INDEX_TYPE uvec3";

#[compute]
#version 450
#VERSION_DEFINES

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types : require

#include "../common.glsl.inc"

layout(constant_id = 0) const uint WALL_SEGMENTS = 1;
layout(constant_id = 1) const uint ARCS = 1;

const uint COLS = 2 * ARCS + 2; // Both ends' resolved columns, plus the rim corners
const uint ROWS = WALL_SEGMENTS + 2; // Rim, fold, then up to the surface
const uint COLOR_WALL = 0xFF20C0E0; // Amber
const float RISE_FOLD = 0.5; // Row 1 - where the wall folds, as a fraction of depth
const float FOLD_GAP = 0.25; // Model units below the surface

layout(local_size_x = 64) in;

layout(push_constant, std430) uniform PushParams {
	uint wall_rim_base;
	uint wall_grid_base;
	uint wall_face_base;
	uint out_color_offset;
	uint out_custom_offset;
	uint out_attribute_stride;
	uint max_edges;
	float depth;
};

layout(set = 0, binding = 0, scalar) restrict buffer OutVertexBuffer {
	vec3 out_positions[];
};

layout(set = 0, binding = 1, scalar) restrict buffer OutIndexBuffer {
	OUT_INDEX_TYPE out_faces[];
};

layout(set = 0, binding = 2, std430) restrict buffer OutAttributeBuffer {
	uint out_attributes[];
};

layout(set = 1, binding = 0, scalar) restrict buffer BoundaryBuffer {
	uint boundary_count;
	uint boundary_vert_count; // unused
	BoundaryEdge boundary_edges[];
};

layout(set = 2, binding = 0, std430) restrict buffer VertexFlagBuffer {
	uint vertex_flags[];
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

// Row 0 is the rim itself. The whole column is shared with the wall next door,
// so neither may own it. Columns are allocated per boundary vert, not per
// selection vert - shared_edges stores the compact slot in the flag word
uint side_vert(uint vert, uint row) {
	uint slot = vertex_flags[vert] >> FLAG_BITS;

	return wall_rim_base + (slot - 1) * (ROWS - 1) + row;
}

// Columns 0..ARCS resolve end x, ARCS+1..COLS-1 resolve end y (outward to inward)
bool is_pinched(uint idx, uint slot) {
	return boundary_edges[idx].top[0][slot] == boundary_edges[idx].top[ARCS][slot];
}

// The top row is the surface's own verts, the sides are shared, and what's
// left is this wall's to fill. A column group whose apex never retracted has
// zero width - alias it onto its side column so the strip reads as degenerate
// to every index-based check, not just the top quad
uint grid_vert(uint idx, uint col, uint row) {
	if (col <= ARCS) {
		if (is_pinched(idx, 0)) col = 0;
	} else if (is_pinched(idx, 1)) {
		col = COLS - 1;
	}

	if (row + 1 == ROWS) {
		return col < COLS / 2
			? boundary_edges[idx].top[col][0]
			: boundary_edges[idx].top[COLS - 1 - col][1];
	}

	if (col == 0) return side_vert(boundary_edges[idx].verts.x, row);
	if (col + 1 == COLS) return side_vert(boundary_edges[idx].verts.y, row);

	return wall_grid_base + idx * ((COLS - 2) * (ROWS - 1)) + row * (COLS - 2) + col - 1;
}

float row_rise(uint row) {
	if (row == 0) return 0.0;
	if (row + 1 == ROWS) return 1.0;

	float fold = depth > 1e-6 ? max(1.0 - FOLD_GAP / depth, RISE_FOLD) : RISE_FOLD;

	return mix(fold, 1.0, float(row - 1) / float(ROWS - 2));
}

void write_quad(uint face, uvec4 ring, bool flip) {
	out_faces[face] = OUT_INDEX_TYPE(flip ? ring.xyw : ring.xyz);
	out_faces[face + 1] = OUT_INDEX_TYPE(flip ? ring.yzw : ring.xzw);
}

void main() {
	uint idx = gl_GlobalInvocationID.x;

	if (idx >= min(boundary_count, max_edges)) return;

	vec3 rim_x = out_positions[boundary_edges[idx].verts.x];
	vec3 rim_y = out_positions[boundary_edges[idx].verts.y];
	vec3 span = rim_y - rim_x;
	float length2 = dot(span, span);

	// Every row below the surface sits directly under its top-row vert,
	// projected onto the rim
	for (uint col = 0; col < COLS; col++) {
		vec3 top = out_positions[grid_vert(idx, col, ROWS - 1)];
		float t = length2 > 1e-18 ? clamp(dot(top - rim_x, span) / length2, 0.0, 1.0) : 0.0;
		vec3 rest = rim_x + span * t;

		for (uint row = 0; row + 1 < ROWS; row++) {
			write_vertex(grid_vert(idx, col, row), rest, row_rise(row));
		}
	}

	uint face_base = wall_face_base + idx * (COLS - 1) * (ROWS - 1) * 2;

	for (uint row = 0; row + 1 < ROWS; row++) {
		for (uint col = 0; col + 1 < COLS; col++) {
			uint face = face_base + (row * (COLS - 1) + col) * 2;

			// Side columns are shared, so their diagonals mirror rather than alternate
			bool side = col == 0 || col + 2 == COLS;
			bool flip = side ? col > 0 : col % 2 == 1;

			write_quad(face, uvec4(
				grid_vert(idx, col, row),
				grid_vert(idx, col + 1, row),
				grid_vert(idx, col + 1, row + 1),
				grid_vert(idx, col, row + 1)
			), flip);
		}
	}
}
