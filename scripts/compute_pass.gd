@abstract
extends RefCounted
class_name ComputePass

var rd: RenderingDevice
var mesh: ArrayMesh
var mesh_rid: RID:
	get: return mesh.get_rid()
var surface: ComputeSurface
var params: ComputeParams
var push_constant: PackedByteArray
var sets: ComputeSets


## Bootleg dependency injection
func _init(p_mesh: ArrayMesh, p_surface: ComputeSurface, p_params: ComputeParams, p_sets: ComputeSets) -> void:
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


func free_rids(rids: Array[RID]) -> void:
	for rid in rids:
		if rid.is_valid():
			rd.free_rid(rid)

@abstract func _pre() -> void
@abstract func compute() -> void
