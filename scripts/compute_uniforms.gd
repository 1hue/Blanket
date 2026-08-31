extends RefCounted
class_name ComputeUniforms

# TODO Clean up vars
var rd: RenderingDevice
var surface: ComputeSurface

#region Faces
var faces_set: RID
var faces_buffer: RID
var faces_dedupe_dispatch_buffer: RID
var faces_table_buffer: RID
var faces_table_set: RID
var faces_slot_buffer: RID
var faces_slot_set: RID
var faces_write_dispatch_buffer: RID
#endregion

var source_set: RID # 0 = Verts, 1 = Indices, 2 = Attributes
var out_set: RID

var bevel_shrink_dispatch_buffer: RID
var bevel_out_set: RID
var shared_edge_set: RID
var shared_edge: RID
var fill_dispatch_buffer: RID

var normals_sum: RID
var normals_sum_set: RID

var smooth_sum: RID
var smooth_sum_set: RID

var debug: RID


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
	], SurfaceShaders.faces_select.shader, 0)


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
