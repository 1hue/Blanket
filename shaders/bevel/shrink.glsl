// Shrink each face toward its centroid. Corner index becomes the new vertex index.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types_int16 : require

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	float shrink; // 0 = unchanged, 1 = collapsed to centroid
	uint in_face_count;
	uint in_corner_count;
	uint out_color_offset;
	uint out_attribute_stride;
};

layout(set = 0, binding = 0, scalar) restrict readonly buffer InVertexBuffer {
	vec3 in_positions[];
};

layout(set = 0, binding = 1, scalar) restrict readonly buffer InIndexBuffer {
	u16vec3 in_faces[];
};

layout(set = 1, binding = 0, scalar) restrict writeonly buffer OutVertexBuffer {
	vec3 out_positions[];
};

layout(set = 1, binding = 1, scalar) restrict writeonly buffer OutIndexBuffer {
	u16vec3 out_faces[];
};

layout(set = 1, binding = 2, std430) restrict writeonly buffer OutAttributeBuffer {
	uint out_attributes[];
};

vec3[3] get_face_positions(uint face) {
	uvec3 corners = uvec3(in_faces[face]);
	return vec3[3](
		in_positions[corners.x],
		in_positions[corners.y],
		in_positions[corners.z]
	);
}

bool edges_match(vec3 a0, vec3 a1, vec3 b0, vec3 b1) {
	return (a0 == b0 && a1 == b1) || (a0 == b1 && a1 == b0);
}

struct SharedEdges {
	bool ab; // edge 0
	bool ba; // edge 0
	bool bc; // edge 1
	bool cb; // edge 1
	bool ca; // edge 2
	bool ac; // edge 2
};

SharedEdges is_face_shared(uint face) {
	vec3[3] positions_self = get_face_positions(face);
	SharedEdges result = SharedEdges(false, false, false, false, false, false);

	for (uint f = 0u; f < in_face_count; f++) {
		if (face == f) continue; // Don't compare with self

		vec3[3] positions_other = get_face_positions(f);

		// Go over each edge in face
		for (uint i_self = 0u; i_self < 3u; i_self++) {
			vec3 self_a = positions_self[i_self];
			vec3 self_b = positions_self[(i_self + 1u) % 3u];

			for (uint i_other = 0u; i_other < 3u; i_other++) {
				vec3 other_a = positions_other[i_other];
				vec3 other_b = positions_other[(i_other + 1u) % 3u];

				if (edges_match(self_a, self_b, other_a, other_b)) {
					if (i_self == 0u) {
						result.ab = true;
						result.ba = true;
						break;
					}
					if (i_self == 1u) {
						result.bc = true;
						result.cb = true;
						break;
					}
					if (i_self == 2u) {
						result.ca = true;
						result.ac = true;
						break;
					}
				}
			}
		}
	}

	return result;
}

void write_out_color(uint out_index, vec4 color) {
	uint word = (out_color_offset + out_index * out_attribute_stride) / 4u;
	out_attributes[word] = packUnorm4x8(color);
}

void main() {
	uint face = gl_GlobalInvocationID.x + gl_GlobalInvocationID.y * (gl_NumWorkGroups.x * gl_WorkGroupSize.x);

	if (face >= in_face_count) {
		return;
	}

	uvec3 corners = uvec3(in_faces[face]);
	vec3 a = in_positions[corners.x];
	vec3 b = in_positions[corners.y];
	vec3 c = in_positions[corners.z];
	vec3 center = (a + b + c) / 3.0;

	SharedEdges is_shared = is_face_shared(face);

	// Write vert coords
	uint base = face * 3u;
	out_positions[base] = mix(a, mix(b, c, is_shared.ab && is_shared.ac ? 0.5 : is_shared.ab ? 1 : 0), is_shared.ab || is_shared.ac ? shrink : 0);

	out_positions[base + 1u] = mix(b, mix(c, a, is_shared.bc && is_shared.ba ? 0.5 : is_shared.bc ? 1 : 0), is_shared.bc || is_shared.ba ? shrink : 0);

	out_positions[base + 2u] = mix(c, mix(a, b, is_shared.ca && is_shared.cb ? 0.5 : is_shared.ca ? 1 : 0), is_shared.ca || is_shared.cb ? shrink : 0);

	// Write indices
	out_faces[face] = u16vec3(base, base + 1u, base + 2u);

	// Red if a vert's either edge is shared
	vec4 color_a = (is_shared.ab || is_shared.ac) ? vec4(1.0, 0.0, 0.0, 1.0) : vec4(1.0);
	vec4 color_b = (is_shared.bc || is_shared.ba) ? vec4(1.0, 0.0, 0.0, 1.0) : vec4(1.0);
	vec4 color_c = (is_shared.ca || is_shared.cb) ? vec4(1.0, 0.0, 0.0, 1.0) : vec4(1.0);

	write_out_color(base, color_a);
	write_out_color(base + 1u, color_b);
	write_out_color(base + 2u, color_c);
}
