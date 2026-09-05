extends ComputePass
class_name FacesWritePass

const VERTEX_STRIDE = 12 # vec3
const INDEX_STRIDE = 12 # uvec3 for simplicity

## Self-made scratch buffers - can't allocate the final mesh surface before shared_count is known.
var faces_out_set: RID
var vertex_buffer: RID
var index_buffer: RID


func _pre() -> void:
	pass


## Holds the deduped selection. The real surface is sized in shared_edges, once shared_count is known.
func allocate() -> void:
	var counts := rd.buffer_get_data(sets.faces_select_buffer, 0, 8)
	params.selected_face_count = counts.decode_u32(0)
	params.selected_vertex_count = counts.decode_u32(4)

	var verts := maxi(params.selected_vertex_count, 1)
	var faces := maxi(params.selected_face_count, 1)

	vertex_buffer = rd.storage_buffer_create(align_buffer(verts * VERTEX_STRIDE))
	index_buffer = rd.storage_buffer_create(align_buffer(faces * INDEX_STRIDE))

	faces_out_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([vertex_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
		ComputeUtil.create_uniform([index_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 1),
	], SurfaceShaders.faces_write.shader, 4)

	sets.faces_out = faces_out_set


func compute() -> void:
	allocate()

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.faces_write.pipeline)
	rd.compute_list_bind_uniform_set(compute_list, sets.in_mesh, 0)
	rd.compute_list_bind_uniform_set(compute_list, sets.faces_select, 1)
	rd.compute_list_bind_uniform_set(compute_list, sets.faces_table, 2)
	rd.compute_list_bind_uniform_set(compute_list, sets.faces_slot, 3)
	rd.compute_list_bind_uniform_set(compute_list, faces_out_set, 4)
	rd.compute_list_dispatch_indirect(compute_list, sets.faces_write_dispatch_buffer, 0)
	rd.compute_list_end()


func _notification(what) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	for rid in [faces_out_set, vertex_buffer, index_buffer]:
		if rid.is_valid():
			rd.free_rid(rid)
