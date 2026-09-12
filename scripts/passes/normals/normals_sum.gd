extends ComputePass
class_name NormalsSumPass

const WORKGROUP_SIZE = 256
const SIZE_PARAMS = 4

var buffer: RID
var buffer_size: int
var uniform_set: RID


func _pre() -> void:
	push_constant.resize(SIZE_PARAMS)


## The out mesh only exists after OutMeshPass, so the buffer can't be sized in _pre
func init_buffer() -> void:
	var size := align_buffer(params.out_vertex_count * 12)

	if buffer.is_valid() and size == buffer_size:
		return

	buffer_size = size
	buffer = rd.storage_buffer_create(buffer_size)

	uniform_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER),
	], SurfaceShaders.normals_sum.shader, 0)

	sets.normals_sum_buffer = buffer
	sets.normals_sum = uniform_set


func pack_params() -> PackedByteArray:
	push_constant.encode_u32(0, params.out_face_count)

	return push_constant


## Rerun after anything that moves verts - offset.glsl changes every wall's tilt
func compute() -> void:
	init_buffer()
	rd.buffer_clear(buffer, 0, buffer_size)

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.normals_sum.pipeline)
	rd.compute_list_set_push_constant(compute_list, pack_params(), SIZE_PARAMS)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, sets.out_mesh, 1)
	rd.compute_list_dispatch(compute_list, ceili(params.out_face_count / float(WORKGROUP_SIZE)), 1, 1)
	rd.compute_list_end()


func _notification(what) -> void:
	if what == NOTIFICATION_PREDELETE:
		for rid in [uniform_set, buffer]:
			if rid.is_valid():
				rd.free_rid(rid)
