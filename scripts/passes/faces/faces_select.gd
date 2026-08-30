extends ComputePass
class_name FacesSelectPass

const SIZE_PARAMS = 40

var faces_buffer: RID
var faces_buffer_size: int
var faces_uniform_set: RID

var dispatch_buffer: RID
var dispatch_uniform_set: RID


func _pre() -> void:
	push_constant.resize(SIZE_PARAMS)
	init_uniforms()


func init_uniforms() -> void:
	# face_count, vertex_count, then at most every source face
	faces_buffer_size = align_buffer(8 + params.in_face_count * 6)
	faces_buffer = rd.storage_buffer_create(faces_buffer_size)

	faces_uniform_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([faces_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
	], SurfaceShaders.faces_select.shader, 1)

	dispatch_buffer = rd.storage_buffer_create(
		12, PackedByteArray(), RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT
	)

	dispatch_uniform_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([dispatch_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
	], SurfaceShaders.faces_select.shader, 2)

	uniforms.faces_set = faces_uniform_set
	uniforms.faces_buffer = faces_buffer
	uniforms.faces_dedupe_dispatch_buffer = dispatch_buffer


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
	rd.buffer_clear(faces_buffer, 0, faces_buffer_size)
	rd.buffer_clear(dispatch_buffer, 0, 12)

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.faces_select.pipeline)
	rd.compute_list_set_push_constant(compute_list, pack_params(), SIZE_PARAMS)
	rd.compute_list_bind_uniform_set(compute_list, uniforms.source_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, faces_uniform_set, 1)
	rd.compute_list_bind_uniform_set(compute_list, dispatch_uniform_set, 2)
	rd.compute_list_dispatch(compute_list, ceili(params.in_face_count / 256.0), 1, 1)
	rd.compute_list_end()


func _notification(what) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	for rid in [faces_uniform_set, faces_buffer, dispatch_uniform_set, dispatch_buffer]:
		if rid.is_valid():
			rd.free_rid(rid)
