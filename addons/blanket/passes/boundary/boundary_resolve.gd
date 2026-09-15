extends BlanketPass
class_name BoundaryResolvePass

const SIZE_PARAMS = 4


func _pre() -> void:
	push_constant.resize(SIZE_PARAMS)


func pack_params() -> PackedByteArray:
	push_constant.encode_u32(0, params.max_edges)

	return push_constant


func compute() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, BlanketShaders.boundary_resolve.pipelines[version])
	rd.compute_list_set_push_constant(compute_list, pack_params(), SIZE_PARAMS)
	rd.compute_list_bind_uniform_set(compute_list, sets.boundary, 0)
	rd.compute_list_bind_uniform_set(compute_list, sets.face_edge_mask, 1)
	rd.compute_list_bind_uniform_set(compute_list, sets.shared_edge, 2)
	rd.compute_list_bind_uniform_set(compute_list, sets.selected_faces, 3)
	rd.compute_list_dispatch_indirect(compute_list, sets.dispatch_buffer, BlanketSets.Dispatch.BOUNDARY)
	rd.compute_list_end()
