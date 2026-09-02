// Retract each selected face from its shared edges, and repoint the face at the result.
// X = face, Y = corner.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types : require

const uint NONE = 0xFFFFFFFFu;

layout(local_size_x = 64, local_size_y = 3) in;

layout(push_constant, std430) uniform PushParams {
	float shrink; // 0 = unchanged, 1 = moved onto the opposite corner
	uint selected_vertex_count;
	uint selected_face_count;
	uint out_custom_offset;
	uint out_attribute_stride;
};

struct SharedEdge {
	uvec2 apexes; // Original ends of edge A_B, sorted
	uvec2 corners; // The two face corners sharing it, face * 3 + corner
	uvec2 retracted[2]; // [A1_A2, B1_B2], one per apex, ordered as corners
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

layout(set = 1, binding = 0, scalar) restrict buffer SharedEdgeBuffer {
	uint shared_count;
	uint retracted_count; // Verts claimed so far, past selected_vertex_count
	layout(offset = 16) SharedEdge shared_edges[];
};

// Prefilled with NONE, so an unshared corner needs no sentinel of its own
layout(set = 1, binding = 1, std430) restrict buffer CornerEdgeBuffer {
	uint corner_edges[]; // Edge slot leaving each corner, indexed face * 3 + corner
};

// One run of retracted verts per face, claimed by its first corner
shared uint face_base[gl_WorkGroupSize.x];

uint next_corner(uint corner) {
	return (corner + 1) % 3;
}

uint prev_corner(uint corner) {
	return (corner + 2) % 3;
}

uint edge_at(uint face, uint corner) {
	return corner_edges[face * 3 + corner];
}

// A corner moves if either the edge leaving it or the edge arriving is shared
bool needs_vert(uint face, uint corner) {
	return edge_at(face, corner) != NONE || edge_at(face, prev_corner(corner)) != NONE;
}

// Retreats toward the corner opposite whichever edge is shared, or between both.
// Weights are 0 or 1, so an unshared edge contributes nothing without a branch.
vec3 inset(vec3 self, vec3 toward_next, vec3 toward_prev, float next_weight, float prev_weight) {
	return mix(
		self,
		(toward_next * next_weight + toward_prev * prev_weight) / (next_weight + prev_weight),
		shrink
	);
}

// The retracted vert inherits whether it may move
void copy_custom(uint from, uint to) {
	uint source = (out_custom_offset + from * out_attribute_stride) / 4;
	uint target = (out_custom_offset + to * out_attribute_stride) / 4;

	out_attributes[target + 3] = out_attributes[source + 3];
}

// The apex it started from picks the pair, the corner that owns the edge picks the half,
// so all four writers of a slot land somewhere different and nothing races
void publish(uint slot, uint owner, uint apex, uint vert) {
	if (slot == NONE) return;

	uint pair = apex == shared_edges[slot].apexes.x ? 0 : 1;
	uint side = owner == shared_edges[slot].corners.x ? 0 : 1;

	shared_edges[slot].retracted[pair][side] = vert;
}

void main() {
	uint face = gl_GlobalInvocationID.x;
	uint corner = gl_LocalInvocationID.y;
	// Out of range invocations stay resident: the barrier below is group wide
	bool in_range = face < selected_face_count;

	uvec3 corners = in_range ? uvec3(out_faces[face]) : uvec3(0);

	// Every corner reads all three, so each derives its own rank without sharing
	bvec3 needs = bvec3(
		in_range && needs_vert(face, 0),
						in_range && needs_vert(face, 1),
						in_range && needs_vert(face, 2)
	);

	// The face claims one contiguous run, so corners left in place cost nothing
	if (corner == 0 && any(needs)) {
		uint wanted = uint(needs.x) + uint(needs.y) + uint(needs.z);

		face_base[gl_LocalInvocationID.x] =
		selected_vertex_count + atomicAdd(retracted_count, wanted);
	}

	// Everyone is done reading out_faces, and the run is claimed
	barrier();

	if (!in_range || !any(needs)) return;

	uint base = face_base[gl_LocalInvocationID.x];
	uvec3 rank = uvec3(0, uint(needs.x), uint(needs.x) + uint(needs.y));

	// One invocation assembles, so the three corners do not race on one vector
	if (corner == 0) {
		out_faces[face] = u16vec3(
			needs.x ? base + rank.x : corners.x,
			needs.y ? base + rank.y : corners.y,
			needs.z ? base + rank.z : corners.z
		);
	}

	if (!needs[corner]) return;

	uint prev = prev_corner(corner);
	uint retracted = base + rank[corner];

	out_positions[retracted] = inset(
		out_positions[corners[corner]],
		out_positions[corners[prev]],
		out_positions[corners[next_corner(corner)]],
									 float(edge_at(face, corner) != NONE),
									 float(edge_at(face, prev) != NONE)
	);
	copy_custom(corners[corner], retracted);

	// This corner sits on the edge leaving it and on the one arriving from behind
	publish(edge_at(face, corner), face * 3 + corner, corners[corner], retracted);
	publish(edge_at(face, prev), face * 3 + prev, corners[corner], retracted);
}
