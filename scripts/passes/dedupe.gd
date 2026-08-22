extends ComputePass
class_name DedupePass

const SIZE_PARAMS = 16

var slot_buffer: RID
var used_buffer: RID
var uniform_set: RID


func _pre() -> void:
	push_constant.resize(SIZE_PARAMS)
	_init_uniforms()


func _init_uniforms() -> void:
	_init_slot_buffer()

	used_buffer = rd.storage_buffer_create(params.in_vertex_count * 4)

	uniform_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([slot_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
		ComputeUtil.create_uniform([used_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 1),
	], SurfaceShaders.dedupe.shader, 3)


func _init_slot_buffer() -> void:
	# unique_count (4) + one slot per source vertex
	var buffer_size := 4 + params.in_vertex_count * 4
	slot_buffer = rd.storage_buffer_create(buffer_size)

	# unique_count zeroed, slots[] filled with the unused sentinel
	var slot_init := PackedByteArray()
	slot_init.resize(buffer_size)
	slot_init.encode_u32(0, 0)
	for i in params.in_vertex_count:
		slot_init.encode_u32(4 + i * 4, UINT32_MAX) # TODO: fill()?
	rd.buffer_update(slot_buffer, 0, buffer_size, slot_init)


func pack_params() -> PackedByteArray:
	push_constant.encode_u32(0, params.in_vertex_count)
	push_constant.encode_u32(4, params.in_vertex_stride)
	push_constant.encode_u32(8, params.in_normal_offset)
	push_constant.encode_u32(12, params.in_normal_stride)

	return push_constant


func compute() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.dedupe.pipeline)
	rd.compute_list_set_push_constant(compute_list, pack_params(), SIZE_PARAMS)
	rd.compute_list_bind_uniform_set(compute_list, uniforms.source_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 3)
	rd.compute_list_dispatch(compute_list, ceili(params.in_vertex_count / 256.0), 1, 1)
	rd.compute_list_end()


func _notification(what) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	for rid in [uniform_set, slot_buffer, used_buffer]:
		if rid.is_valid():
			rd.free_rid(rid)
