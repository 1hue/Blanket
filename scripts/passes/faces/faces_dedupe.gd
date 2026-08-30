extends ComputePass
class_name FacesDedupePass

const SIZE_PARAMS = 4
const EMPTY_BYTE = UINT32_MAX

var table_buffer: RID
var table_buffer_size: int
var table_uniform_set: RID
var table_clear: PackedByteArray

var slot_buffer: RID
var slot_uniform_set: RID

var dispatch_buffer: RID
var dispatch_uniform_set: RID


func _pre() -> void:
	push_constant.resize(SIZE_PARAMS)
	init_uniforms()


func init_uniforms() -> void:
	# Power of two above 2x the vertex count, so probes stay short
	params.faces_table_size = nearest_po2(params.in_vertex_count * 2)

	table_buffer_size = align_buffer(params.faces_table_size * 4)
	table_buffer = rd.storage_buffer_create(table_buffer_size)

	# Cached, since buffer_clear only zeroes and empty slots must read as all bits set
	table_clear.resize(table_buffer_size)
	table_clear.fill(EMPTY_BYTE)

	table_uniform_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([table_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
	], SurfaceShaders.faces_dedupe.shader, 2)

	# Only survivors are ever read back, so this needs no clearing
	slot_buffer = rd.storage_buffer_create(params.in_vertex_count * 2)

	slot_uniform_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([slot_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
	], SurfaceShaders.faces_dedupe.shader, 3)

	dispatch_buffer = rd.storage_buffer_create(
		12, PackedByteArray(), RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT
	)

	dispatch_uniform_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([dispatch_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
	], SurfaceShaders.faces_dedupe.shader, 4)

	uniforms.faces_table_set = table_uniform_set
	uniforms.faces_table_buffer = table_buffer
	uniforms.faces_slot_set = slot_uniform_set
	uniforms.faces_slot_buffer = slot_buffer
	uniforms.faces_write_dispatch_buffer = dispatch_buffer


func pack_params() -> PackedByteArray:
	push_constant.encode_u32(0, params.faces_table_size)

	return push_constant


func compute() -> void:
	rd.buffer_update(table_buffer, 0, table_buffer_size, table_clear)
	rd.buffer_clear(dispatch_buffer, 0, 12)

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.faces_dedupe.pipeline)
	rd.compute_list_set_push_constant(compute_list, pack_params(), SIZE_PARAMS)
	rd.compute_list_bind_uniform_set(compute_list, uniforms.source_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, uniforms.faces_set, 1)
	rd.compute_list_bind_uniform_set(compute_list, table_uniform_set, 2)
	rd.compute_list_bind_uniform_set(compute_list, slot_uniform_set, 3)
	rd.compute_list_bind_uniform_set(compute_list, dispatch_uniform_set, 4)
	rd.compute_list_dispatch_indirect(compute_list, uniforms.faces_dedupe_dispatch_buffer, 0)
	rd.compute_list_end()


func _notification(what) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	for rid in [
		table_uniform_set, table_buffer,
		slot_uniform_set, slot_buffer,
		dispatch_uniform_set, dispatch_buffer,
	]:
		if rid.is_valid():
			rd.free_rid(rid)
