extends RefCounted
class_name BlanketSets

## dispatch_buffer offsets of each uvec3(X,Y,Z)
enum Dispatch {
	DEDUPE = 0 * 12,
	FACES = 1 * 12,
	EDGES = 2 * 12,
	OUT_MESH = 3 * 12,
	SHRINK = 4 * 12,
	FILL = 5 * 12,
	BOUNDARY = 6 * 12,
}

# TODO Clean up vars
var rd: RenderingDevice
var surface: BlanketSurface

var in_mesh: RID # 0 = Verts, 1 = Indices, 2 = Attributes
var out_mesh: RID
## 0 = faces_dedupe, 1 = faces_write, 2 = shared_edges, 3 = out_mesh, 4 = bevel_shrink, 5 = bevel_fill, 6 = boundary
var dispatch_buffer: RID
var dispatch: RID

#region Faces
var selected_faces: RID # Vertex + Index buffer
var selected_index_buffer: RID
var selected_vertex_buffer: RID
var faces_table: RID
var faces_table_buffer: RID
#endregion

#region Bevel
var shared_edge: RID
var shared_edge_buffer: RID
var face_edge_mask: RID
var face_edge_mask_buffer: RID
var vertex_flag: RID
var vertex_flag_buffer: RID
var boundary: RID
var boundary_buffer: RID
#endregion

var normals_sum: RID
var normals_sum_buffer: RID

var smooth_sum: RID
var smooth_sum_buffer: RID

var debug: RID


func _init(p_surface: BlanketSurface) -> void:
	rd = RenderingServer.get_rendering_device()
	surface = p_surface

	init_in_mesh_set()
	init_indirect_dispatch()


func init_in_mesh_set() -> void:
	var vertex_buffer := RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(surface.mesh_rid, surface.source_idx)
	var index_buffer := RenderingServer.mesh_surface_get_index_buffer_rd_rid(surface.mesh_rid, surface.source_idx)
	var attribute_buffer := RenderingServer.mesh_surface_get_attribute_buffer_rd_rid(surface.mesh_rid, surface.source_idx)

	in_mesh = rd.uniform_set_create([
		BlanketUtil.create_uniform([vertex_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
		BlanketUtil.create_uniform([index_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 1),
		BlanketUtil.create_uniform([attribute_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 2),
	], BlanketShaders.select.shader, 0)


func init_indirect_dispatch() -> void:
	dispatch_buffer = dispatch_buffer_create(Dispatch.BOUNDARY / 12 + 1)
	dispatch = rd.uniform_set_create([
		BlanketUtil.create_uniform([dispatch_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
	], BlanketShaders.select.shader, 2)


func dispatch_buffer_create(count := 1, init: PackedInt32Array = []) -> RID:
	var size := count * 12
	var bytes := PackedByteArray()
	bytes.resize(size)

	for i in count * 3:
		bytes.encode_u32(i * 4, init[i] if i < init.size() else 1)

	return rd.storage_buffer_create(size, bytes, RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT)


## Free scratch buffers after bake
#func cleanup_bake() -> void:
	#for rid in [faces_set, edges_set]:
		#if rid.is_valid():
			#rd.free_rid(rid)


func _notification(what) -> void:
	if what != NOTIFICATION_PREDELETE:
		return

	for rid in [in_mesh, dispatch, dispatch_buffer]: # Free uniform set -> free buffer
		if rid.is_valid():
			rd.free_rid(rid)
