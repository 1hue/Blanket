// Normalize the accumulated sums into the surface's packed normals.
#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require

layout(local_size_x = 256) in;

layout(push_constant, std430) uniform PushParams {
	uint out_normal_offset;
	uint out_normal_stride;
};

layout(set = 1, binding = 0, scalar) restrict readonly buffer OutVertexBuffer {
	vec3 out_positions[];
};

layout(set = 1, binding = 1, std430) restrict buffer OutVertexWords {
	uint out_words[]; // Same buffer as out_positions, reached as raw words for the normal block
};

layout(set = 3, binding = 0, std430) restrict readonly buffer NormalSumBuffer {
	float normal_sums[];
};

uint oct_encode(vec3 n) {
	vec3 a = n / (abs(n.x) + abs(n.y) + abs(n.z));
	vec2 e = a.z >= 0 ? a.xy : (1 - abs(a.yx)) * sign(a.xy);
	return packUnorm2x16(fma(e, vec2(0.5), vec2(0.5)));
}

void main() {
	uint vert = gl_GlobalInvocationID.x;

	if (vert >= uint(out_positions.length())) return;

	uint base = vert * 3;
	vec3 sum = vec3(normal_sums[base], normal_sums[base + 1], normal_sums[base + 2]);

	// Orphaned verts have no faces, so nothing summed into them
	vec3 normal = dot(sum, sum) > 0 ? normalize(sum) : vec3(0, 1, 0);

	uint word = (out_normal_offset + vert * out_normal_stride) / 4;
	out_words[word] = oct_encode(normal);
	out_words[word + 1] = 0; // Tangent placeholder
}
