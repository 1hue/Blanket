#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_16bit_storage : require
#extension GL_EXT_shader_explicit_arithmetic_types : require

layout(local_size_x = 256) in;

layout(constant_id = 0) const uint VERTEX_COUNT = 3;

layout(push_constant, std430) uniform PushParams {
    vec3 local_up; // World-up transformed into mesh local space (computed on CPU)
    float up_threshold_degrees; // Max angle from local_up for a face to qualify
    float shift_amount; // How far to move eligible vertices
};

layout(set = 0, binding = 0, scalar) restrict readonly buffer IndexBuffer {
    u16vec3 indices[]; // Indices referencing verts form triangles, 3 verts per triangle
};

layout(set = 0, binding = 1, scalar) restrict readonly buffer VertexBuffer {
    vec3 verts[VERTEX_COUNT];
    uint normals[]; // Packed normals and tangents
};

layout(set = 1, binding = 0, scalar) restrict buffer CountBuffer {
    uint counter;
    vec3 debug;
    u16vec3 eligible[];
};

vec3 oct_decode(vec2 e) {
    vec3 v = vec3(e.xy, 1.0 - abs(e.x) - abs(e.y));
    vec2 wrapped = (1.0 - abs(v.yx)) * sign(v.xy);
    v.xy = mix(v.xy, wrapped, step(v.z, 0.0));
    return normalize(v);
}

vec3 read_normal(uint vertex_index) {
    uint element_index = vertex_index * 2u;
    vec2 e = unpackUnorm2x16(normals[element_index]) * 2.0 - 1.0;
    return oct_decode(e);
}

void main() {
    // 2D
    uint idx = gl_GlobalInvocationID.x + gl_GlobalInvocationID.y * (gl_NumWorkGroups.x * gl_WorkGroupSize.x);
    uint prev = atomicAdd(counter, 1u);

    if (idx >= VERTEX_COUNT) {
        return;
    }

// 	vec3 tri[3] = vec3[](
// 		verts[indices[idx].x],
// 		verts[indices[idx].y],
// 		verts[indices[idx].z]
// 	);

    eligible[idx] = indices[idx];

    if (idx == 0) {
        vec3 normal = read_normal(idx);
    }
}
