# Blanket

Procedural mesh surface cover for Godot 4.

Can be used to generate a blanket of snow 🏔️, mounds of dirt, or piles of autumn leaves 🍂. Eliminates the need to modify your meshes individually - uniform effects should happen automatically!

## Features
- Smooth animated height/depth
- Slope threshold / upward facing angle
- Rotate or scale a mesh and the cover rebuilds itself
- One node per scene to cover all meshes
- Individual mesh targetting
- Exclusion by group
- Advanced sparkling snow shader included

## How it works

Everything runs on the GPU through compute shaders. GDExtension not needed.

Meshes are checked for upward faces. The placement of the Blanket node controls which meshes are eligible - only siblings - place directly under scene root to cover the whole scene.

Upward faces are identified, extruded and bevelled through a handful of compute dispatches, no mesh data copied back to the CPU. This happens as a one-time bake at initialization.

The resultant generated geometry is inserted as an additional surface on the same mesh. Then textured via a `ShaderMaterial`.

Depth can be animated at runtime cheaply without a rebake.

No changes to meshes are ever persisted.

## Requirements

- Godot 4.8 - needs [mesh buffer RIDs](https://github.com/godotengine/godot/pull/118973)
- Forward+ or Mobile renderer - Compatibility has no compute support
- Desktop recommended; mobile GPU compute drivers are unreliable
- Meshes should be `ArrayMesh` with normals, otherwise Blanket will attempt to convert at runtime

## Usage

Add a `Blanket` node as a sibling of whatever you want covered. Likewise, place directly under scene root like you would `WorldEnvironment` if you want everything covered.

To skip a mesh, assign it the `blanket_exclude` group. In case of imported meshes, any parent with this group works too.

For per-mesh control, add a `BlanketInstance` directly under a `MeshInstance3D`. Blanket leaves hand-placed instances alone, so their own settings stick.

## Acknowledgements

- Thanks to [@Bonkahe](https://github.com/Bonkahe) for compute shader inspiration in [SunshineClouds](https://github.com/Bonkahe/SunshineClouds2).
