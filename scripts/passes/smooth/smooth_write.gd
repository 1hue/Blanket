extends ComputePass
class_name SmoothWritePass

const SIZE_PARAMS = 16


func _pre() -> void:
	push_constant.resize(SIZE_PARAMS)


func pack_params() -> PackedByteArray:
	push_constant.encode_float(0, params.smooth_strength)
	push_constant.encode_u32(4, params.bevel_vertex_count)
	push_constant.encode_u32(8, params.bevel_marker_offset)
	push_constant.encode_u32(12, params.bevel_attribute_stride)

	return push_constant


## Rerun after anything that moves verts - shape.glsl changes every wall's tilt.
func compute() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.smooth_write.pipeline)
	rd.compute_list_set_push_constant(compute_list, pack_params(), SIZE_PARAMS)
	rd.compute_list_bind_uniform_set(compute_list, uniforms.smooth_sum_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, uniforms.bevel_out_set, 1)
	rd.compute_list_dispatch(compute_list, ceili(params.bevel_vertex_count / 256.0), 1, 1)
	rd.compute_list_end()
