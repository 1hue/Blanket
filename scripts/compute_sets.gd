extends RefCounted
class_name ComputeSets

# TODO Clean up vars
var rd: RenderingDevice
var surface: ComputeSurface

var in_mesh: RID # 0 = Verts, 1 = Indices, 2 = Attributes
var out_mesh: RID
## 0 = faces_dedupe, 1 = faces_write, 2 = shared_edges, 3 = bevel_shrink, 4 = bevel_fill
var dispatch_buffer: RID
var dispatch: RID

#region Faces
var faces_scratch: RID # Vertex + Index buffer
var index_scratch_buffer: RID
var vertex_scratch_buffer: RID
var faces_table: RID
var faces_table_buffer: RID
#endregion

#region Bevel
var shared_edge: RID
var shared_edge_buffer: RID
var bevel_shrink_dispatch_buffer: RID
var bevel_out: RID
var shared_mask_buffer: RID
var shared_mask: RID
var corner_edge_buffer: RID
#endregion

var normals_sum: RID
var normals_sum_buffer: RID

var smooth_sum: RID
var smooth_sum_buffer: RID

var debug: RID


func _init(p_surface: ComputeSurface) -> void:
	rd = RenderingServer.get_rendering_device()
	surface = p_surface

	init_in_mesh_set()
	init_indirect_dispatch()


func init_in_mesh_set() -> void:
	var vertex_buffer := RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(surface.mesh_rid, surface.source_idx)
	var index_buffer := RenderingServer.mesh_surface_get_index_buffer_rd_rid(surface.mesh_rid, surface.source_idx)
	var attribute_buffer := RenderingServer.mesh_surface_get_attribute_buffer_rd_rid(surface.mesh_rid, surface.source_idx)

	in_mesh = rd.uniform_set_create([
		ComputeUtil.create_uniform([vertex_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
		ComputeUtil.create_uniform([index_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 1),
		ComputeUtil.create_uniform([attribute_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 2),
	], SurfaceShaders.faces_select.shader, 0)


func init_indirect_dispatch() -> void:
	dispatch_buffer = dispatch_buffer_create(4)
	dispatch = rd.uniform_set_create([
		ComputeUtil.create_uniform([dispatch_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
	], SurfaceShaders.faces_select.shader, 2)


func dispatch_buffer_create(count := 1, init: PackedInt32Array = []) -> RID:
	var size := count * 12
	var bytes := PackedByteArray()
	bytes.resize(size)

	for i in count * 3:
		bytes.encode_u32(i * 4, init[i] if i < init.size() else 1)

	return rd.storage_buffer_create(size, bytes, RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT)


## Free scratch buffers after bake
#func cleanup_bake() -> void:
	#for rid in [faces_set, edges_set, faces_dispatch_set, edges_dispatch_set]:
		#if rid.is_valid():
			#rd.free_rid(rid)


func _notification(what) -> void:
	if what != NOTIFICATION_PREDELETE:
		return

	for rid in [in_mesh, dispatch, dispatch_buffer]: # Free uniform set -> free buffer
		if rid.is_valid():
			rd.free_rid(rid)
