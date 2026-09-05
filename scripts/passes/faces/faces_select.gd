extends ComputePass
class_name FacesSelectPass

const WORKGROUP_SIZE = 256
const SIZE_PARAMS = 40
const VERTEX_STRIDE = 12 # vec3
const INDEX_STRIDE = 12 # uvec3 for simplicity

var faces_scratch_set: RID
var index_scratch_buffer: RID
var vertex_scratch_buffer: RID

var faces_dedupe_dispatch_set: RID
var faces_dedupe_dispatch_buffer: RID


func _pre() -> void:
	push_constant.resize(SIZE_PARAMS)
	init_faces_scratch_buffers()
	init_faces_dedupe_dispatch_buffer()


func init_faces_scratch_buffers() -> void:
	var max_verts := mini(params.in_vertex_count, params.in_face_count * 3)
	var vertex_size := align_buffer(4 + maxi(max_verts, 1) * VERTEX_STRIDE)
	var index_size := align_buffer(4 + maxi(params.in_face_count, 1) * INDEX_STRIDE)

	vertex_scratch_buffer = rd.storage_buffer_create(vertex_size)
	index_scratch_buffer = rd.storage_buffer_create(index_size)

	faces_scratch_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([vertex_scratch_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
		ComputeUtil.create_uniform([index_scratch_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 1),
	], SurfaceShaders.faces_select.shader, 1)

	sets.faces_scratch = faces_scratch_set
	sets.index_scratch_buffer = index_scratch_buffer
	sets.vertex_scratch_buffer = vertex_scratch_buffer


func init_faces_dedupe_dispatch_buffer() -> void:
	faces_dedupe_dispatch_buffer = dispatch_buffer_create()
	faces_dedupe_dispatch_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([faces_dedupe_dispatch_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
	], SurfaceShaders.faces_select.shader, 2)

	sets.faces_dedupe_dispatch_buffer = faces_dedupe_dispatch_buffer


func pack_params() -> PackedByteArray:
	push_constant.encode_float(0, params.local_up.x)
	push_constant.encode_float(4, params.local_up.y)
	push_constant.encode_float(8, params.local_up.z)
	push_constant.encode_float(12, params.upright_dot)
	push_constant.encode_u32(16, params.in_vertex_count)
	push_constant.encode_u32(20, params.in_face_count)
	push_constant.encode_u32(24, params.in_normal_offset)
	push_constant.encode_u32(28, params.in_normal_stride)
	push_constant.encode_u32(32, params.in_color_offset)
	push_constant.encode_u32(36, params.in_attribute_stride)

	return push_constant


func compute() -> void:
	# Clear the counts - buffers not always zeroed
	rd.buffer_clear(index_scratch_buffer, 0, 4)
	rd.buffer_clear(vertex_scratch_buffer, 0, 4)

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.faces_select.pipeline)
	rd.compute_list_set_push_constant(compute_list, pack_params(), SIZE_PARAMS)
	rd.compute_list_bind_uniform_set(compute_list, sets.in_mesh, 0)
	rd.compute_list_bind_uniform_set(compute_list, faces_scratch_set, 1)
	rd.compute_list_bind_uniform_set(compute_list, faces_dedupe_dispatch_set, 2)
	rd.compute_list_dispatch(compute_list, ceili(params.in_face_count / float(WORKGROUP_SIZE)), 1, 1)
	rd.compute_list_end()


func _notification(what) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	for rid in [
		faces_scratch_set, index_scratch_buffer, vertex_scratch_buffer,
		faces_dedupe_dispatch_set, faces_dedupe_dispatch_buffer
	]:
		if rid.is_valid():
			rd.free_rid(rid)
