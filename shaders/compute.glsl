#[compute]
#version 450

layout(constant_id = 0) const float CONSTANT_0 = 0.0;
layout(constant_id = 1) const float CONSTANT_1 = 0.0;
layout(local_size_x = 4, local_size_y = 2) in;
layout(set = 0, binding = 0, std430) buffer DataStorageBuffer {
    uint counter;
    vec2 constants;

    float storage_data[];
};
layout(push_constant, std430) uniform PushParams {
    float push_data[4];
};

void main() {
    uint idx = gl_LocalInvocationIndex;
    uint prev = atomicAdd(counter, 1u);

    // Each invocation is uniquely identified by idx and touches only its own corresponding array index
    storage_data[idx] = push_data[idx];

    // With our persistent storage buffer, the data doesn't disappear until we destroy the buffer ourselves,
    // so we could keep adding:
    //storage_data[idx] += push_data[idx];

    // Only run this on invocation 0, don't need to run it 8 times
    if (idx == 0) {
        constants = vec2(CONSTANT_0, CONSTANT_1);
    }
}
