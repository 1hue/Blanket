# SPDX-FileCopyrightText: © 2026 1hue
# SPDX-License-Identifier: MIT

## Collection of compute passes per mesh surface.
extends RefCounted
class_name BlanketPipeline

var mesh: ArrayMesh
var mesh_rid: RID:
	get: return mesh.get_rid()
var rd: RenderingDevice
var params: BlanketParams
var sets: BlanketSets
var surface: BlanketSurface
var debug: BlanketDebug
var select_passes: Array[BlanketPass]
var build_passes: Array[BlanketPass]
var update_passes: Array[BlanketPass]


func _init(p_mesh: ArrayMesh, surface_idx: int, global_transform: Transform3D) -> void:
	rd = RenderingServer.get_rendering_device()
	assert(rd != null, "No RenderingDevice - compute shaders require Forward+ or Mobile renderer")
	assert(BlanketShaders is Node, "BlanketShaders autoload missing - check Project Settings > Autoload")
	assert(p_mesh != null, "Mesh is null")
	assert(surface_idx >= 0 and surface_idx < p_mesh.get_surface_count(),
		"Surface %d out of range on %s (%d surfaces)" % [surface_idx, p_mesh, p_mesh.get_surface_count()])

	mesh = p_mesh
	surface = BlanketSurface.new(p_mesh, surface_idx)
	sets = BlanketSets.new(surface)
	params = BlanketParams.new(surface, global_transform)
	debug = BlanketDebug.new(p_mesh, surface, sets, params)

	select_passes = [
		SelectPass.new(mesh, surface, params, sets),
		DedupePass.new(mesh, surface, params, sets),
		FacesPass.new(mesh, surface, params, sets),
		EdgesPass.new(mesh, surface, params, sets),
		OutMeshPass.new(mesh, surface, params, sets),
	]

	build_passes = [
		ShrinkPass.new(mesh, surface, params, sets),
		FillPass.new(mesh, surface, params, sets),
		BoundaryResolvePass.new(mesh, surface, params, sets),
		BoundaryWritePass.new(mesh, surface, params, sets),
	]

	update_passes = [
		OffsetPass.new(mesh, surface, params, sets),
		SmoothPass.new(mesh, surface, params, sets),
		NormalsSumPass.new(mesh, surface, params, sets),
		NormalsWritePass.new(mesh, surface, params, sets),
	]


func bake() -> void:
	#sets.clear_dispatch()

	for select_pass in select_passes:
		select_pass.compute()

	if params.is_out_mesh_empty:
		return

	for build_pass in build_passes:
		build_pass.compute()

	update()
	#debug.dump()


func update() -> void:
	if params.is_out_mesh_empty:
		push_warning("BlanketPipeline: is_out_mesh_empty")
		return

	for update_pass in update_passes:
		update_pass.compute()
