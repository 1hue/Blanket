extends ComputePass
class_name BevelFillPass

const SIZE_PARAMS = 28


func _pre() -> void:
	push_constant.resize(SIZE_PARAMS)


func pack_params() -> PackedByteArray:
	push_constant.encode_float(0, params.bevel_shrink)
	push_constant.encode_u32(4, params.bevel_segments)
	push_constant.encode_u32(8, params.bevel_arcs)
	push_constant.encode_u32(12, params.selected_vertex_count)
	push_constant.encode_u32(16, params.selected_face_count)
	push_constant.encode_u32(20, params.out_custom_offset)
	push_constant.encode_u32(24, params.out_attribute_stride)

	return push_constant


func compute() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.bevel_fill.pipeline)
	rd.compute_list_set_push_constant(compute_list, pack_params(), SIZE_PARAMS)
	rd.compute_list_bind_uniform_set(compute_list, uniforms.out_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, uniforms.shared_edge_set, 1)
	rd.compute_list_dispatch_indirect(compute_list, uniforms.bevel_fill_dispatch_buffer, 0)
	rd.compute_list_end()
