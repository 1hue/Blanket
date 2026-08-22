extends ComputePass
class_name SelectionWorker

const SIZE_PARAMS = 24

var normal_sum_buffer: RID
var normal_sum_size: int
var normal_sum_uniform_set: RID


func _pre() -> void:
	normal_sum_size = params.out_vertex_count * 12
	normal_sum_buffer = rd.storage_buffer_create(normal_sum_size)

	normal_sum_uniform_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([normal_sum_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
	], SurfaceShaders.bevel_normals.shader, 3)


## Rerun after anything that moves verts - shape.glsl changes every wall's tilt
func compute() -> void:
	rd.buffer_clear(normal_sum_buffer, 0, normal_sum_size)

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.bevel_normals.pipeline)
	#rd.compute_list_bind_uniform_set(compute_list, out_uniform_set, 1)
	rd.compute_list_bind_uniform_set(compute_list, normal_sum_uniform_set, 3)
	rd.compute_list_dispatch(compute_list, ceili(params.out_index_count / 3.0 / 256.0), 1, 1)
	rd.compute_list_end()

	compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.bevel_normals_finish.pipeline)
	rd.compute_list_set_push_constant(compute_list, pack_params(), SIZE_PARAMS)
	#rd.compute_list_bind_uniform_set(compute_list, out_uniform_set, 1)
	rd.compute_list_bind_uniform_set(compute_list, normal_sum_uniform_set, 3)
	rd.compute_list_dispatch(compute_list, ceili(params.out_vertex_count / 256.0), 1, 1)
	rd.compute_list_end()


func pack_params() -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(SIZE_PARAMS)
	bytes.encode_float(0, params.local_up.x)
	bytes.encode_float(4, params.local_up.y)
	bytes.encode_float(8, params.local_up.z)
	bytes.encode_float(12, params.depth)
	bytes.encode_u32(16, params.out_vertex_count)
	bytes.encode_u32(20, params.in_vertex_stride)
	bytes.encode_u32(24, params.out_vertex_stride)
	bytes.encode_u32(28, params.out_marker_offset)
	bytes.encode_u32(32, params.out_attribute_stride)
	return bytes
