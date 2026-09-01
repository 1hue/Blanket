// Retract each selected face from its shared edges.
// X = face, Y = corner.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types : require

layout(local_size_x = 64, local_size_y = 3) in;

layout(push_constant, std430) uniform PushParams {
	float shrink; // 0 = unchanged, 1 = moved onto opposite corner
	uint selected_vertex_count;
	uint selected_face_count;
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

layout(set = 1, binding = 0, scalar) restrict buffer SharedEdgeBuffer {
	uint shared_count;
	uvec4 shared_edges[];
};

uint next_corner(uint corner) {
	return (corner + 1) % 3;
}

uint prev_corner(uint corner) {
	return (corner + 2) % 3;
}

// The list holds retracted corner indices, so an edge is present under either face's name
bool is_shared(uint retracted_corner) {
	for (uint i = 0; i < shared_count; i++) {
		uvec4 edge = shared_edges[i];

		if (edge.x == retracted_corner) return true;
		if (edge.z == retracted_corner) return true;
	}

	return false;
}

// Retreats toward the corner opposite whichever edge is shared, or between both.
// Weights are 0 or 1, so an unshared edge contributes nothing without a branch.
vec3 inset(vec3 self, vec3 toward_next, vec3 toward_prev, float next_weight, float prev_weight) {
	float total = next_weight + prev_weight;

	if (total == 0) return self;

	vec3 target = (toward_next * next_weight + toward_prev * prev_weight) / total;

	return mix(self, target, shrink);
}

// The retracted corner inherits where it came from and whether it may move
void copy_custom(uint from, uint to) {
	uint source = (out_custom_offset + from * out_attribute_stride) / 4;
	uint target = (out_custom_offset + to * out_attribute_stride) / 4;

	out_attributes[target] = out_attributes[source];
	out_attributes[target + 1] = out_attributes[source + 1];
	out_attributes[target + 2] = out_attributes[source + 2];
	out_attributes[target + 3] = out_attributes[source + 3];
}

void main() {
	uint face = gl_GlobalInvocationID.x;
	uint corner = gl_GlobalInvocationID.y;

	if (face >= selected_face_count) return;

	u16vec3 corners = out_faces[face];
	uint base = selected_vertex_count + face * 3;
	uint prev = prev_corner(corner);

	// This corner sits on its own edge and on the one arriving from the previous corner
	bool own_shared = is_shared(base + corner);
	bool prev_shared = is_shared(base + prev);

	vec3 self = out_positions[corners[corner]];
	vec3 next = out_positions[corners[next_corner(corner)]];
	vec3 behind = out_positions[corners[prev]];

	uint retracted = base + corner;

	out_positions[retracted] = inset(
		self,
		behind,
		next,
		own_shared ? 1 : 0,
		prev_shared ? 1 : 0
	);
	copy_custom(corners[corner], retracted);
}
