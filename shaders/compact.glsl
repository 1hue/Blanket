#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : enable

layout(local_size_x = 256) in;

layout(constant_id = 0) const uint VERTEX_COUNT = 24;

layout(push_constant, std430) uniform PushParams {
    vec3 local_up; // World-up transformed into mesh local space (computed on CPU)
    float shift_amount; // How far to move eligible vertices
    float up_threshold_degrees; // Max angle from local_up for a face to qualify
};

layout(set = 0, binding = 0, scalar) restrict readonly buffer IndexBuffer {
    uvec3 indices[]; // 3 per triangle
};

layout(set = 0, binding = 1, scalar) restrict readonly buffer SourceVertexBuffer {
    vec3 source_verts[VERTEX_COUNT];
    uint source_normals[]; // Packed normals and tangents
};

layout(set = 0, binding = 2, scalar) restrict writeonly buffer VertexBuffer {
    vec3 verts[VERTEX_COUNT];
};

layout(set = 0, binding = 3, scalar) restrict buffer DebugBuffer {
    vec3 debug;
};

vec3 oct_decode(vec2 e) {
    vec3 v = vec3(e.xy, 1.0 - abs(e.x) - abs(e.y));
    vec2 wrapped = (1.0 - abs(v.yx)) * sign(v.xy);
    v.xy = mix(v.xy, wrapped, step(v.z, 0.0));
    return normalize(v);
}

vec3 read_normal(uint vertex_index) {
    uint element_index = vertex_index * 2u;
    vec2 e = unpackUnorm2x16(source_normals[element_index]) * 2.0 - 1.0;
    return oct_decode(e);
}

void main() {
    // 2D
    uint idx = gl_GlobalInvocationID.x + gl_GlobalInvocationID.y * (gl_NumWorkGroups.x * gl_WorkGroupSize.x);

    if (idx >= source_verts.length()) {
        return;
    }

    vec3 tri[3] = vec3[](
        source_verts[indices[idx].x],
        source_verts[indices[idx].y],
        source_verts[indices[idx].z]
    );

    vec3 normal = read_normal(idx);
    debug = normal;
}
