// Fill each boundary edge's wall: a quad grid from the rim up to the surface.
// Everything lies on the rim at rest - W is what raises it
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types : require

const uint COLOR_WALL = 0xFF20C0E0; // Amber
const float RISE_FOLD = 0.5;

layout(local_size_x = 64) in;

layout(push_constant, std430) uniform PushParams {
	uint wall_rim_base;
	uint wall_grid_base;
	uint wall_face_base;
	uint steps; // Subdivisions along each ring, per side of the crease
	uint rings; // Rings from the apex out to the retracted verts
	uint out_color_offset;
	uint out_custom_offset;
	uint out_attribute_stride;
};

struct BoundaryEdge {
	uvec2 verts;
	uint face;
	uint corner;
	uvec2 top[4];
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

BoundaryEdge boundary;
uint cols; // 2 per end, plus the two rim corners
uint rows; // Rim, fold, then up to the surface

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

uint side_vert(uint vert, uint row) {
	return wall_rim_base + vert * (rows - 1) + row;
}

uint grid_vert(uint idx, uint col, uint row) {
	if (row + 1 == rows) {
		return col < cols / 2 ? boundary.top[col][0] : boundary.top[cols - 1 - col][1];
	}

	if (col == 0) return side_vert(boundary.verts.x, row);
	if (col + 1 == cols) return side_vert(boundary.verts.y, row);

	return wall_grid_base + idx * ((cols - 2) * (rows - 1)) + row * (cols - 2) + col - 1;
}

// Rows run 0 at the rim, 1 at the fold, then uniformly up to the surface
float row_rise(uint row) {
	if (row == 0) return 0.0;
	if (row + 1 == rows) return 1.0;

	return mix(RISE_FOLD, 1.0, float(row - 1) / float(rows - 2));
}

void write_quad(uint face, uvec4 ring, bool flip) {
	out_faces[face] = u16vec3(flip ? ring.xyw : ring.xyz);
	out_faces[face + 1] = u16vec3(flip ? ring.yzw : ring.xzw);
}

void main() {
	uint idx = gl_GlobalInvocationID.x;

	if (idx >= boundary_count) return;

	boundary = boundary_edges[idx];
	cols = 2 * rings + 2;
	rows = steps + 2;

	vec3 rim_x = out_positions[boundary.verts.x];
	vec3 rim_y = out_positions[boundary.verts.y];
	vec3 span = rim_y - rim_x;
	float length2 = dot(span, span);

	// Every row below the surface sits directly under its top-row vert,
	// projected onto the rim
	for (uint col = 0; col < cols; col++) {
		vec3 top = out_positions[grid_vert(idx, col, rows - 1)];
		float t = length2 > 1e-18 ? clamp(dot(top - rim_x, span) / length2, 0.0, 1.0) : 0.0;
		vec3 rest = rim_x + span * t;

		for (uint row = 0; row + 1 < rows; row++) {
			write_vertex(grid_vert(idx, col, row), rest, row_rise(row));
		}
	}

	uint face_base = wall_face_base + idx * (cols - 1) * (rows - 1) * 2;

	for (uint row = 0; row + 1 < rows; row++) {
		for (uint col = 0; col + 1 < cols; col++) {
			uint face = face_base + (row * (cols - 1) + col) * 2;

			// Side columns are shared, so their diagonals mirror rather than alternate
			bool side = col == 0 || col + 2 == cols;
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
