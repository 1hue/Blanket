extends RefCounted
class_name ComputeUniforms

var rd: RenderingDevice
var surface: ComputeSurface
var source_set: RID # 0 = Verts, 1 = Indices, 2 = Attributes
var faces_dispatch_buffer: RID
var edges_dispatch_buffer: RID

var shrink_dispatch_buffer: RID
var bevel_out_set: RID
var shared_edge_set: RID


func _init(p_surface: ComputeSurface) -> void:
	rd = RenderingServer.get_rendering_device()
	surface = p_surface

	_init_source_set()


func _init_source_set() -> void:
	var vertex_buffer := RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(surface.mesh_rid, surface.source_idx)
	var index_buffer := RenderingServer.mesh_surface_get_index_buffer_rd_rid(surface.mesh_rid, surface.source_idx)
	var attribute_buffer := RenderingServer.mesh_surface_get_attribute_buffer_rd_rid(surface.mesh_rid, surface.source_idx)

	source_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([vertex_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
		ComputeUtil.create_uniform([index_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 1),
		ComputeUtil.create_uniform([attribute_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 2),
	], SurfaceShaders.select_faces.shader, 0)


## Free scratch buffers after bake
#func cleanup_bake() -> void:
	#for rid in [faces_set, edges_set, faces_dispatch_set, edges_dispatch_set]:
		#if rid.is_valid():
			#rd.free_rid(rid)


func _notification(what) -> void:
	if what != NOTIFICATION_PREDELETE:
		return

	for rid in [source_set]: # Free uniform set -> free buffer
		if rid.is_valid():
			rd.free_rid(rid)
