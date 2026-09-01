// List every edge shared by two selected faces, and mark the verts on the boundary.
// X = face, Y = edge.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types : require

const uint NONE = 0xFFFFFFFFu;
const uint FILL_GROUP_SIZE = 256;

layout(local_size_x = 64, local_size_y = 3) in;

layout(push_constant, std430) uniform PushParams {
	uint selected_vertex_count; // Where the retracted corners will begin
	uint selected_face_count;
	uint out_custom_offset;
	uint out_attribute_stride;
};

layout(set = 0, binding = 0, scalar) restrict writeonly buffer OutVertexBuffer {
	vec3 out_positions[]; // Unused
};

layout(set = 0, binding = 1, scalar) restrict buffer OutIndexBuffer {
	u16vec3 out_faces[];
};

layout(set = 0, binding = 2, std430) restrict writeonly buffer OutAttributeBuffer {
	uint out_attributes[];
};

layout(set = 1, binding = 0, scalar) restrict buffer SharedEdgeBuffer {
	uint shared_count;
	uvec4 shared_edges[]; // Retracted corner indices: this face's edge, then the twin's
};

layout(set = 2, binding = 0, std430) restrict writeonly buffer DispatchBuffer {
	uvec3 dispatch; // Indirect args for bevel_fill.glsl
};

uint next_corner(uint corner) {
	return (corner + 1) % 3;
}

// Edge `corner` runs from that corner to the next one round
u16vec2 edge_at(u16vec3 corners, uint corner) {
	if (corner == 0) return corners.xy;
	if (corner == 1) return corners.yz;

	return corners.zx;
}

// Correctly wound neighbours run their shared edge in opposite directions
uint matching_corner(u16vec3 corners, u16vec2 edge) {
	if (edge == corners.yx) return 0;
	if (edge == corners.zy) return 1;
	if (edge == corners.xz) return 2;

	return NONE;
}

uint find_twin(u16vec2 edge, uint face) {
	for (uint other = 0; other < selected_face_count; other++) {
		if (other == face) continue;

		uint corner = matching_corner(out_faces[other], edge);

		if (corner != NONE) return other * 3 + corner;
	}

	return NONE;
}

// Shrink will write the retracted corners at these slots, so fill can name them now
void append_edge(uint face, uint corner, uint twin) {
	uint base = selected_vertex_count + face * 3;
	uint twin_base = selected_vertex_count + twin / 3 * 3;
	uint twin_corner = twin % 3;

	uint slot = atomicAdd(shared_count, 1);
	shared_edges[slot] = uvec4(
		base + corner,
		base + next_corner(corner),
		twin_base + twin_corner,
		twin_base + next_corner(twin_corner)
	);

	atomicMax(dispatch.x, (slot + FILL_GROUP_SIZE) / FILL_GROUP_SIZE);
}

// w = 0 anchors the vert, so nothing downstream moves it
void anchor(uint vert) {
	uint word = (out_custom_offset + vert * out_attribute_stride) / 4;
	out_attributes[word + 3] = floatBitsToUint(0);
}

void main() {
	uint face = gl_GlobalInvocationID.x;
	uint corner = gl_LocalInvocationID.y;

	// Fill repoints every selected face too, so its dispatch must cover them all
	atomicMax(dispatch.x, (selected_face_count + FILL_GROUP_SIZE - 1) / FILL_GROUP_SIZE);
	dispatch.y = 1;
	dispatch.z = 1;

	if (face >= selected_face_count) return;

	u16vec2 edge = edge_at(out_faces[face], corner);
	uint twin = find_twin(edge, face);

	if (twin == NONE) {
		// Nothing on the far side, so both ends anchor the selection
		anchor(edge.x);
		anchor(edge.y);
		return;
	}

	// Both faces find each other, so only the lower corner lists the edge
	if (face * 3 + corner > twin) return;

	append_edge(face, corner, twin);
}
