extends BlanketPass
class_name BoundaryWritePass

const SIZE_PARAMS = 32


func _pre() -> void:
	push_constant.resize(SIZE_PARAMS)


func pack_params() -> PackedByteArray:
	push_constant.encode_u32(0, params.wall_rim_base)
	push_constant.encode_u32(4, params.wall_grid_base)
	push_constant.encode_u32(8, params.wall_face_base)
	push_constant.encode_u32(12, params.out_color_offset)
	push_constant.encode_u32(16, params.out_custom_offset)
	push_constant.encode_u32(20, params.out_attribute_stride)
	push_constant.encode_u32(24, params.max_edges)
	push_constant.encode_float(28, params.depth)

	return push_constant


func compute() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, BlanketShaders.boundary_write.pipeline)
	rd.compute_list_set_push_constant(compute_list, pack_params(), SIZE_PARAMS)
	rd.compute_list_bind_uniform_set(compute_list, sets.out_mesh, 0)
	rd.compute_list_bind_uniform_set(compute_list, sets.boundary, 1)
	rd.compute_list_bind_uniform_set(compute_list, sets.vertex_flag, 2)
	rd.compute_list_dispatch_indirect(compute_list, sets.dispatch_buffer, BlanketSets.Dispatch.BOUNDARY)
	rd.compute_list_end()
