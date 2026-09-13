extends ComputePass
class_name NormalsWritePass

const WORKGROUP_SIZE = 256
const SIZE_PARAMS = 24


func _pre() -> void:
	push_constant.resize(SIZE_PARAMS)


func pack_params() -> PackedByteArray:
	push_constant.encode_float(0, params.local_up.x)
	push_constant.encode_float(4, params.local_up.y)
	push_constant.encode_float(8, params.local_up.z)
	push_constant.encode_u32(12, params.out_vertex_count)
	push_constant.encode_u32(16, params.out_normal_offset)
	push_constant.encode_u32(20, params.out_normal_stride)

	return push_constant


## Rerun after anything that moves verts - offset.glsl changes every wall's tilt
func compute() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.normals_write.pipeline)
	rd.compute_list_set_push_constant(compute_list, pack_params(), SIZE_PARAMS)
	rd.compute_list_bind_uniform_set(compute_list, sets.normals_sum, 0)
	rd.compute_list_bind_uniform_set(compute_list, sets.out_mesh, 1)
	rd.compute_list_dispatch(compute_list, workgroups(params.out_vertex_count, WORKGROUP_SIZE), 1, 1)
	rd.compute_list_end()
