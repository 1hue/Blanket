extends ComputePass
class_name BevelShrinkPass

const SIZE_PARAMS = 20


func _pre() -> void:
	push_constant.resize(SIZE_PARAMS)


func pack_params() -> PackedByteArray:
	push_constant.encode_float(0, params.bevel_shrink)
	push_constant.encode_u32(4, params.selected_vertex_count)
	push_constant.encode_u32(8, params.selected_face_count)
	push_constant.encode_u32(12, params.out_custom_offset)
	push_constant.encode_u32(16, params.out_attribute_stride)

	return push_constant


func compute() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.bevel_shrink.pipeline)
	rd.compute_list_set_push_constant(compute_list, pack_params(), SIZE_PARAMS)
	rd.compute_list_bind_uniform_set(compute_list, uniforms.out_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, uniforms.shared_edge_set, 1)
	rd.compute_list_dispatch(compute_list, ceili(params.selected_face_count / 64.0), 1, 1)
	rd.compute_list_end()
