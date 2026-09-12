// Retract each selected face from its shared edges
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types : require

const float MITER_LIMIT = 2.0; // Multiples of width a sharp corner may travel
const float MIN_SCALE = 0.05; // Smallest the face may shrink to
const uint COLOR_RETRACTED = 0xFF1CA038; // Gasoline green

// X = face, Y = corner
layout(local_size_x = 64, local_size_y = 3) in;

layout(push_constant, std430) uniform PushParams {
	float bevel_width; // Inset distance from each shared edge, model space
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

layout(set = 1, binding = 0, scalar) restrict buffer SelectedVertexBuffer {
	uint sel_vertex_count;
	vec3 sel_positions[];
};

layout(set = 1, binding = 1, scalar) restrict buffer SelectedIndexBuffer {
	uint sel_face_count;
	uvec3 sel_faces[];
};

// Bit c set = edge c of this face is shared. Retraction reads only this.
layout(set = 2, binding = 0, std430) restrict buffer FaceEdgeMaskBuffer {
	uint face_edge_mask[];
};

// Edge c runs from corner c to corner c+1, so corner c sits on edges c and c-1
uint next_corner(uint corner) {
	return (corner + 1) % 3;
}

uint prev_corner(uint corner) {
	return (corner + 2) % 3;
}

bool is_shared(uint mask, uint edge) {
	return (mask & (1 << edge)) != 0;
}

bool is_retracted(uint mask, uint corner) {
	return is_shared(mask, corner) || is_shared(mask, prev_corner(corner));
}

uint retracted_at(uint face_idx, uint corner) {
	return sel_vertex_count + 3 * face_idx + corner;
}

// Insetting from every side collapses the face at the inradius, A/s. Cap
// below it so the worst case is a tiny copy of the original, never an
// inverted one. Edges that aren't shared don't inset, so this is loose
// for boundary faces - which is fine, it only ever clamps
float max_width(uvec3 face) {
	mat3 p = mat3(sel_positions[face.x], sel_positions[face.y], sel_positions[face.z]);
	float perimeter = distance(p[0], p[1]) + distance(p[1], p[2]) + distance(p[2], p[0]);
	if (perimeter < 1e-9) return 0.0;

	float inradius = length(cross(p[1] - p[0], p[2] - p[0])) / perimeter;

	return inradius * (1.0 - MIN_SCALE);
}

// Corner c lies on edges c and c-1. Each contributes a line: offset inward
// by the width if shared, left in place if not. The corner is their
// intersection, so a boundary edge holds the corner on itself and the
// silhouette is preserved
vec3 inset_corner(uvec3 face, uint mask, uint corner, float width) {
	vec3 apex = sel_positions[face[corner]];
	vec3 to_next = sel_positions[face[next_corner(corner)]] - apex;
	vec3 to_prev = sel_positions[face[prev_corner(corner)]] - apex;
	vec3 normal = cross(to_next, to_prev);
	float area2 = length(normal);
	if (area2 < 1e-9) return apex; // Degenerate face, no plane to work in

	// 2D basis in the face plane, with the next edge along x
	vec3 ex = normalize(to_next);
	vec3 ey = cross(normal / area2, ex);
	vec2 prev2 = vec2(dot(to_prev, ex), dot(to_prev, ey));

	// Inward normals: prev2 is on the interior side, so ey points inward
	// for the next edge. Mirror that to get the prev edge's normal
	vec2 n_next = vec2(0.0, sign(prev2.y));
	vec2 n_prev = vec2(-prev2.y, prev2.x) / length(prev2) * -sign(prev2.y);
	float d_next = is_shared(mask, corner) ? width : 0.0;
	float d_prev = is_shared(mask, prev_corner(corner)) ? width : 0.0;

	// Solve for p with dot(p, n) = d on both offset lines
	float det = n_next.x * n_prev.y - n_next.y * n_prev.x;
	if (abs(det) < 1e-6) return apex; // Parallel edges, no intersection

	vec2 p = vec2(
		d_next * n_prev.y - d_prev * n_next.y,
		d_prev * n_next.x - d_next * n_prev.x
	) / det;

	// A sharp corner intersects far out on the bisector - cap the travel
	float reach = length(p);
	if (reach > MITER_LIMIT * width) p *= MITER_LIMIT * width / reach;

	return apex + p.x * ex + p.y * ey;
}

void write_color(uint vert, uint color) {
	out_attributes[(out_color_offset + vert * out_attribute_stride) / 4] = color;
}

void write_vertex(uint vert, vec3 position) {
	uint at = (out_custom_offset + vert * out_attribute_stride) / 4;

	out_positions[vert] = position;
	out_attributes[at] = floatBitsToUint(position.x);
	out_attributes[at + 1] = floatBitsToUint(position.y);
	out_attributes[at + 2] = floatBitsToUint(position.z);
	out_attributes[at + 3] = floatBitsToUint(1.0); // Movable

	write_color(vert, COLOR_RETRACTED);
}

void main() {
	uint face_idx = gl_GlobalInvocationID.x;
	uint corner = gl_GlobalInvocationID.y;
	if (face_idx >= sel_face_count) return;

	uint mask = face_edge_mask[face_idx];
	uvec3 face = sel_faces[face_idx];

	if (corner == 0) {
		uvec3 repointed = face;

		for (uint i = 0; i < 3; ++i) {
			if (is_retracted(mask, i)) repointed[i] = retracted_at(face_idx, i);
		}

		out_faces[face_idx] = u16vec3(repointed);
	}

	if (!is_retracted(mask, corner)) return;

	// A retracted vert is new geometry, so it carries no boundary flag
	uint slot = retracted_at(face_idx, corner);
	vec3 position = inset_corner(face, mask, corner, min(bevel_width, max_width(face)));

	write_vertex(slot, position);
}
