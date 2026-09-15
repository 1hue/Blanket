// Normalize the accumulated sums into the surface's packed normals.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	vec3 local_up; // Model space, normalized - the fallback for verts nothing summed into
	uint out_vertex_count;
	uint out_normal_offset;
	uint out_normal_stride;
};

layout(set = 0, binding = 0, scalar) restrict buffer NormalSumBuffer {
	vec3 normal_sums[];
};

layout(set = 1, binding = 0, std430) restrict buffer OutVertexBuffer {
	uint out_words[]; // Positions, then packed normals
};

layout(set = 1, binding = 1, scalar) restrict buffer OutIndexBuffer {
	uint out_faces[]; // Unused
};

layout(set = 1, binding = 2, std430) restrict buffer OutAttributeBuffer {
	uint out_attributes[]; // Unused
};

vec2 oct_wrap(const in vec2 v) {
	return (1 - abs(v.yx)) * (step(0.0, v.xy) * 2.0 - 1.0); // TODO: can use sign()?
}

uint oct_encode(vec3 n) {
	vec3 a = n / (abs(n.x) + abs(n.y) + abs(n.z));
	vec2 e = a.z >= 0 ? a.xy : oct_wrap(a.xy);

	return packUnorm2x16(e * 0.5 + 0.5);
}

void main() {
	uint vert = gl_GlobalInvocationID.x;

	if (vert >= out_vertex_count) return;

	vec3 sum = normal_sums[vert];
	vec3 normal = dot(sum, sum) > 0.0 ? normalize(sum) : local_up;

	uint word = (out_normal_offset + vert * out_normal_stride) / 4;

	out_words[word] = oct_encode(normal);
	out_words[word + 1] = 0; // Tangent placeholder
}
