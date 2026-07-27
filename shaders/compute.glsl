#[compute]
#version 450

#extension GL_EXT_scalar_block_layout : enable

layout(local_size_x = 1, local_size_y = 1) in;

layout(push_constant, std430) uniform PushParams {
    uint vertex_count;
    uint debug_in;
};

layout(set = 0, binding = 0, std430) buffer DataStorageBuffer {
    uint counter;
    uint debug_out;
};

layout(set = 1, binding = 0, scalar) buffer MeshBuffer {
    vec3 verts[];
};

void moveVerts(inout vec3 v) {
    v *= 2.0;
}

void main() {
    uint idx = gl_LocalInvocationIndex;
    uint prev = atomicAdd(counter, 1u);
    debug_out = debug_in;

    moveVerts(verts[0]);
}
