# Blanket

Procedural mesh surface cover for Godot 4.

Can be used to generate a blanket snow, a mound of dirt, a pile of autumn leaves.

## Features
- Smooth animated height/depth
- Slope threshold / upward facing angle
- Rotate or scale a mesh and the cover rebuilds itself
- One node per scene to cover all meshes
- Individual mesh targetting
- Exclusion by group
- Advanced snow shader included

## How it works

Everything runs on the GPU through compute shaders.

All meshes are checked for upward faces. The placement of the Blanket node controls which meshes are eligible - only siblings - place directly under scene root to cover the whole scene.

Upward faces are identified, extruded and bevelled through a handful of compute dispatches, no mesh data copied back to the CPU. This happens as a one-time bake at initialization.

The resultant generated mesh is inserted as an additional surface on the same mesh.

Depth can be animated at runtime cheaply without a rebake.

No changes to meshes are ever persisted.

## Requirements

- Godot 4.8 — needs vertex buffer RIDs
- Forward+ or Mobile renderer — Compatibility has no compute support
- Desktop recommended; mobile GPU compute drivers are unreliable
- Meshes should be `ArrayMesh` with normals and vertex colours, otherwise Blanket will attempt to convert at runtime

## Usage

Add a `Blanket` node as a sibling of whatever you want covered. Likewise, place directly under scene root like you would `WorldEnvironment` if you want everything covered.

To skip a mesh, assign it the `blanket_exclude` group. In case of imported meshes, any parent with this group works too.

For per-mesh control, add a `BlanketInstance` directly under a `MeshInstance3D`. Blanket leaves hand-placed instances alone, so their own settings stick.
