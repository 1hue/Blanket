@abstract
extends RefCounted
class_name ComputeWorker

var rd: RenderingDevice
var mesh: ArrayMesh
var mesh_rid: RID:
	get: return mesh.get_rid()
var surface: ComputeSurface
var params: ComputeParams
var push_constant: PackedByteArray
var uniforms: ComputeUniforms


## Bootleg dependency injection
func _init(p_mesh: ArrayMesh, p_surface: ComputeSurface, p_params: ComputeParams, p_uniforms: ComputeUniforms) -> void:
	rd = RenderingServer.get_rendering_device()
	mesh = p_mesh
	surface = p_surface
	params = p_params
	uniforms = p_uniforms

	_pre()

@abstract func _pre() -> void
@abstract func compute() -> void
