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


func dispatch_buffer_create(size := 12, init: PackedInt32Array = [1, 1, 1]) -> RID:
	var bytes := PackedByteArray()
	bytes.resize(size)

	for i in init.size():
		bytes.encode_u32(i * 4, init[i])

	return rd.storage_buffer_create(size, bytes, RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT)


func align_buffer(size: int) -> int:
	return snappedi(size + 1, 4)


@abstract func _pre() -> void
@abstract func compute() -> void
