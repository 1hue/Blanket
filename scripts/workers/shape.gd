extends ComputeWorker
class_name Shape

const SIZE_PARAMS = 36

func _pre() -> void:
	push_constant.resize(SIZE_PARAMS)


func pack_params() -> PackedByteArray:
	push_constant.encode_float(0, params.local_up.x)
	push_constant.encode_float(4, params.local_up.y)
	push_constant.encode_float(8, params.local_up.z)
	push_constant.encode_float(12,params. depth)
	push_constant.encode_u32(16,params. select_vertex_count)
	push_constant.encode_u32(20,params. in_vertex_stride)
	push_constant.encode_u32(24,params. select_vertex_stride)
	push_constant.encode_u32(28,params. select_marker_offset)
	push_constant.encode_u32(32,params. select_attribute_stride)

	return push_constant


## Dispatch shape.glsl to reposition the spawned mesh surface
func compute() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.shape.pipeline)
	rd.compute_list_set_push_constant(compute_list, pack_params(), SIZE_PARAMS)
	rd.compute_list_bind_uniform_set(compute_list, in_uniform_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, out_uniform_set, 2)
	rd.compute_list_dispatch(compute_list, ceili(params.out_vertex_count / 256.0), 1, 1)
	rd.compute_list_end()
