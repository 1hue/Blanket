// Fill each boundary edge's wall: a quad grid from the rim up to the surface.
// Everything lies on the rim at rest - W is what raises it
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types : require

#include "../common.glsl.inc"

const uint COLOR_WALL = 0xFF20C0E0; // Amber
const float RISE_FOLD = 0.5; // Row 1 - where the wall folds, as a fraction of depth

layout(constant_id = 0) const uint SEGMENTS = 1;
layout(constant_id = 1) const uint RINGS = 1;

const uint COLS = 2 * RINGS + 2; // Both ends' resolved columns, plus the rim corners
const uint ROWS = SEGMENTS + 2; // Rim, fold, then up to the surface

layout(local_size_x = 64) in;

layout(push_constant, std430) uniform PushParams {
	uint wall_rim_base;
	uint wall_grid_base;
	uint wall_face_base;
	uint out_color_offset;
	uint out_custom_offset;
	uint out_attribute_stride;
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
// so neither may own it
uint side_vert(uint vert, uint row) {
	return wall_rim_base + vert * (ROWS - 1) + row;
}

// The top row is the surface's own verts, the sides are shared, and what's
// left is this wall's to fill
uint grid_vert(uint idx, uint col, uint row) {
	if (row + 1 == ROWS) {
		return col < COLS / 2
		? boundary_edges[idx].top[col][0]
		: boundary_edges[idx].top[COLS - 1 - col][1];
	}

	if (col == 0) return side_vert(boundary_edges[idx].verts.x, row);
	if (col + 1 == COLS) return side_vert(boundary_edges[idx].verts.y, row);

	return wall_grid_base + idx * ((COLS - 2) * (ROWS - 1)) + row * (COLS - 2) + col - 1;
}

// Rows run 0 at the rim, 1 at the fold, then uniformly up to the surface
float row_rise(uint row) {
	if (row == 0) return 0.0;
	if (row + 1 == ROWS) return 1.0;

	return mix(RISE_FOLD, 1.0, float(row - 1) / float(ROWS - 2));
}

void write_quad(uint face, uvec4 ring, bool flip) {
	out_faces[face] = u16vec3(flip ? ring.xyw : ring.xyz);
	out_faces[face + 1] = u16vec3(flip ? ring.yzw : ring.xzw);
}

void main() {
	uint idx = gl_GlobalInvocationID.x;

	if (idx >= boundary_count) return;

// 	if (idx == 0) {
// 		boundary_edges[0].face = RINGS;
// 		boundary_edges[0].corner = boundary_edges[0].top.length();
// 	}
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
