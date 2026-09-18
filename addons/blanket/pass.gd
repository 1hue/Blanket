# SPDX-FileCopyrightText: © 2026 1hue
# SPDX-License-Identifier: MIT

@abstract
extends RefCounted
class_name BlanketPass

var rd: RenderingDevice
var mesh: ArrayMesh
var mesh_rid: RID:
	get: return mesh.get_rid()
var surface: BlanketSurface
var params: BlanketParams
var sets: BlanketSets
var push_constant: PackedByteArray
var version := &""


## Bootleg dependency injection
func _init(p_mesh: ArrayMesh, p_surface: BlanketSurface, p_params: BlanketParams, p_sets: BlanketSets) -> void:
	rd = RenderingServer.get_rendering_device()
	mesh = p_mesh
	surface = p_surface
	params = p_params
	sets = p_sets

	_pre()


func align_buffer(size: int) -> int:
	return snappedi(size + 1, 4)


func workgroups(count: int, workgroup_axis_size: int) -> int:
	return ceili(count / float(workgroup_axis_size))


## Bootleg barrier because Godot's indirect dispatch is wonky - results in mesh holes due to incorrect dispatch values
func sync_dispatch() -> void:
	rd.buffer_get_data(sets.dispatch_buffer)


func free_rids(rids: Array[RID]) -> void:
	for rid in rids:
		if rid:
			rd.free_rid(rid)


## Equivalent to _init but saves passing a train of params
@abstract func _pre() -> void
@abstract func compute() -> void
