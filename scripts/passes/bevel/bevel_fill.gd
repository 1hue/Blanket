extends ComputePass
class_name BevelFillPass

const SIZE_PARAMS = 24


func _pre() -> void:
	push_constant.resize(SIZE_PARAMS)


func pack_params() -> PackedByteArray:
	push_constant.encode_float(0, params.bevel_width)
	push_constant.encode_u32(4, params.bevel_segments)
	push_constant.encode_u32(8, params.bevel_arcs)
	push_constant.encode_u32(12, params.out_color_offset)
	push_constant.encode_u32(16, params.out_custom_offset)
	push_constant.encode_u32(20, params.out_attribute_stride)

	return push_constant


func compute() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.bevel_fill.pipeline)
	rd.compute_list_set_push_constant(compute_list, pack_params(), SIZE_PARAMS)
	rd.compute_list_bind_uniform_set(compute_list, sets.out_mesh, 0)
	rd.compute_list_bind_uniform_set(compute_list, sets.faces_scratch, 1)
	rd.compute_list_bind_uniform_set(compute_list, sets.shared_edge, 2)
	rd.compute_list_dispatch_indirect(compute_list, sets.dispatch_buffer, 48)
	rd.compute_list_end()
