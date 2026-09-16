extends BlanketPass
class_name NormalsSumPass

const WORKGROUP_SIZE = 256
const SIZE_PARAMS = 20

var buffer: RID
var buffer_size: int
var uniform_set: RID


func _pre() -> void:
	version = &"out_u32" if params.out_index_stride == 4 else &"out_u16"

	push_constant.resize(SIZE_PARAMS)


## The out mesh only exists after OutMeshPass, so the buffer can't be sized in _pre
func init_buffer() -> void:
	var size := align_buffer(params.out_vertex_count * 12)

	if buffer.is_valid() and size == buffer_size:
		return

	free_rids([uniform_set, buffer])

	buffer_size = size
	buffer = rd.storage_buffer_create(buffer_size)

	uniform_set = rd.uniform_set_create([
		BlanketUtil.create_uniform([buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER),
	], BlanketShaders.normals_sum.shaders[version], 0)

	sets.normals_sum_buffer = buffer
	sets.normals_sum = uniform_set


func pack_params() -> PackedByteArray:
	push_constant.encode_float(0, params.local_up.x)
	push_constant.encode_float(4, params.local_up.y)
	push_constant.encode_float(8, params.local_up.z)
	push_constant.encode_u32(12, params.out_face_count)
	push_constant.encode_u32(16, params.wall_rim_base)

	return push_constant


## Rerun after anything that moves verts - offset.glsl changes every wall's tilt
func compute() -> void:
	init_buffer()
	rd.buffer_clear(buffer, 0, buffer_size)

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, BlanketShaders.normals_sum.pipelines[version])
	rd.compute_list_set_push_constant(compute_list, pack_params(), SIZE_PARAMS)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, sets.out_mesh, 1)
	rd.compute_list_dispatch(compute_list, workgroups(params.out_face_count, WORKGROUP_SIZE), 1, 1)
	rd.compute_list_end()


func _notification(what) -> void:
	if what == NOTIFICATION_PREDELETE:
		for rid in [uniform_set, buffer]:
			if rid:
				rd.free_rid(rid)
