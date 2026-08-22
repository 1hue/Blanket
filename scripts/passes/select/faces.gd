extends ComputePass
class_name SelectFacesPass

const SIZE_PARAMS = 44
const BUFFER_HEADER = 4 # faces_count

## Source vert indices of upright faces as uvec3, e.g. [(0, 1, 2), (0, 3, 1)]
var buffer: RID
var uniform_set: RID
var dispatch_buffer: RID
var dispatch_uniform_set: RID


func _pre() -> void:
	push_constant.resize(SIZE_PARAMS)
	_init_uniforms()
	_init_indirect_dispatch()


func _init_uniforms() -> void:
	var buffer_size := BUFFER_HEADER + params.in_index_count * 4

	buffer = rd.storage_buffer_create(
		buffer_size, PackedByteArray(), RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT
	)

	uniform_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0)
	], SurfaceShaders.select_faces.shader, 1)

	uniforms.faces_set = uniform_set


## Separate dispatch buffers. WARNING: must not be passed into target shader - engine constraint.
func _init_indirect_dispatch() -> void:
	dispatch_buffer = rd.storage_buffer_create(
		12, PackedByteArray(), RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT
	)

	uniforms.faces_dispatch_buffer = dispatch_buffer

	dispatch_uniform_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([dispatch_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
	], SurfaceShaders.select_faces.shader, 2)


func pack_params() -> PackedByteArray:
	push_constant.encode_float(0, params.local_up.x)
	push_constant.encode_float(4, params.local_up.y)
	push_constant.encode_float(8, params.local_up.z)
	push_constant.encode_float(12, params.upright_dot)
	push_constant.encode_u32(16, params.in_index_count)
	push_constant.encode_u32(20, params.in_vertex_count)
	push_constant.encode_u32(24, params.in_index_stride)
	push_constant.encode_u32(28, params.in_normal_offset)
	push_constant.encode_u32(32, params.in_normal_stride)
	push_constant.encode_u32(36, params.in_color_offset)
	push_constant.encode_u32(40, params.in_attribute_stride)

	return push_constant


## Select upright faces
func compute() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.select_faces.pipeline)
	rd.compute_list_set_push_constant(compute_list, pack_params(), SIZE_PARAMS)
	rd.compute_list_bind_uniform_set(compute_list, uniforms.source_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 1)
	rd.compute_list_bind_uniform_set(compute_list, dispatch_uniform_set, 2)
	rd.compute_list_bind_uniform_set(compute_list, uniforms.dedupe_set, 3)
	rd.compute_list_dispatch(compute_list, ceili(params.in_index_count / 3.0 / 256.0), 1, 1)
	rd.compute_list_end()


func _notification(what) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	for rid in [uniform_set, buffer, dispatch_uniform_set, dispatch_buffer]:
		if rid.is_valid():
			rd.free_rid(rid)
