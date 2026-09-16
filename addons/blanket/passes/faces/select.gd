extends BlanketPass
class_name SelectPass

const SIZE_PARAMS = 32
const VERTEX_STRIDE = 12 # vec3
const INDEX_STRIDE = 12 # uvec3 for simplicity

var selected_faces_set: RID
var selected_index_buffer: RID
var selected_vertex_buffer: RID


func _pre() -> void:
	version = &"in_u32" if params.in_index_stride == 4 else &"in_u16"

	push_constant.resize(SIZE_PARAMS)

	init_in_mesh_set()
	init_selected_faces_buffers()



func init_in_mesh_set() -> void:
	var vertex_buffer := RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(surface.mesh_rid, surface.source_idx)
	var index_buffer := RenderingServer.mesh_surface_get_index_buffer_rd_rid(surface.mesh_rid, surface.source_idx)
	var attribute_buffer := RenderingServer.mesh_surface_get_attribute_buffer_rd_rid(surface.mesh_rid, surface.source_idx)

	sets.in_mesh = rd.uniform_set_create([
		BlanketUtil.create_uniform([vertex_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
		BlanketUtil.create_uniform([index_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 1),
		BlanketUtil.create_uniform([attribute_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 2),
	], BlanketShaders.select.shaders[version], 0)


func init_selected_faces_buffers() -> void:
	var max_verts := mini(params.in_vertex_count, params.in_face_count * 3)
	var vertex_size := align_buffer(4 + maxi(max_verts, 1) * VERTEX_STRIDE)
	var index_size := align_buffer(4 + maxi(params.in_face_count, 1) * INDEX_STRIDE)

	selected_vertex_buffer = rd.storage_buffer_create(vertex_size)
	selected_index_buffer = rd.storage_buffer_create(index_size)

	selected_faces_set = rd.uniform_set_create([
		BlanketUtil.create_uniform([selected_vertex_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
		BlanketUtil.create_uniform([selected_index_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 1),
	], BlanketShaders.select.shaders[version], 1)

	sets.selected_faces = selected_faces_set
	sets.selected_index_buffer = selected_index_buffer
	sets.selected_vertex_buffer = selected_vertex_buffer


func pack_params() -> PackedByteArray:
	push_constant.encode_float(0, params.local_up.x)
	push_constant.encode_float(4, params.local_up.y)
	push_constant.encode_float(8, params.local_up.z)
	push_constant.encode_float(12, params.upright_dot)
	push_constant.encode_u32(16, params.in_vertex_count)
	push_constant.encode_u32(20, params.in_face_count)
	push_constant.encode_u32(24, params.in_normal_offset)
	push_constant.encode_u32(28, params.in_normal_stride)

	return push_constant


func compute() -> void:
	# Clear the counts - buffers not always zeroed
	rd.buffer_clear(selected_index_buffer, 0, 4)
	rd.buffer_clear(selected_vertex_buffer, 0, 4)

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, BlanketShaders.select.pipelines[version])
	rd.compute_list_set_push_constant(compute_list, pack_params(), SIZE_PARAMS)
	rd.compute_list_bind_uniform_set(compute_list, sets.in_mesh, 0)
	rd.compute_list_bind_uniform_set(compute_list, selected_faces_set, 1)
	rd.compute_list_bind_uniform_set(compute_list, sets.dispatch, 2)
	rd.compute_list_dispatch(compute_list, workgroups(params.in_face_count, 256), 1, 1)
	rd.compute_list_end()


func _notification(what) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	for rid in [selected_faces_set, selected_index_buffer, selected_vertex_buffer]:
		if rid:
			rd.free_rid(rid)
