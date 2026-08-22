extends ComputePass
class_name NormalsWritePass

const SIZE_PARAMS = 12


func _pre() -> void:
	push_constant.resize(SIZE_PARAMS)


func pack_params() -> PackedByteArray:
	push_constant.encode_u32(0, params.bevel_vertex_count)
	push_constant.encode_u32(4, params.bevel_normal_offset)
	push_constant.encode_u32(8, params.bevel_normal_stride)

	return push_constant


## Rerun after anything that moves verts - shape.glsl changes every wall's tilt
func compute() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.normals_write.pipeline)
	rd.compute_list_set_push_constant(compute_list, pack_params(), SIZE_PARAMS)
	rd.compute_list_bind_uniform_set(compute_list, uniforms.normals_sum_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, uniforms.bevel_out_set, 1)
	rd.compute_list_dispatch(compute_list, ceili(params.bevel_vertex_count / 256.0), 1, 1)
	rd.compute_list_end()
