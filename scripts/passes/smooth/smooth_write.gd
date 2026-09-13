extends BlanketPass
class_name SmoothWritePass

const WORKGROUP_SIZE = 256
const SIZE_PARAMS = 16


func _pre() -> void:
	push_constant.resize(SIZE_PARAMS)


func pack_params() -> PackedByteArray:
	push_constant.encode_u32(0, params.wall_rim_base)
	push_constant.encode_u32(4, params.out_vertex_count)
	push_constant.encode_u32(8, params.out_custom_offset)
	push_constant.encode_u32(12, params.out_attribute_stride)

	return push_constant


func compute() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, BlanketShaders.smooth_write.pipeline)
	rd.compute_list_set_push_constant(compute_list, pack_params(), SIZE_PARAMS)
	rd.compute_list_bind_uniform_set(compute_list, sets.smooth_sum, 0)
	rd.compute_list_bind_uniform_set(compute_list, sets.out_mesh, 1)
	rd.compute_list_dispatch(compute_list, workgroups(params.out_vertex_count, WORKGROUP_SIZE), 1, 1)
	rd.compute_list_end()
