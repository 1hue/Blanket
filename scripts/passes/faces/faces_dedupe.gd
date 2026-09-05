extends ComputePass
class_name FacesDedupePass

const SIZE_PARAMS = 4
const EMPTY_BYTE = UINT32_MAX

var table_set: RID
var table_buffer: RID
var table_buffer_size: int
var table_clear: PackedByteArray

var slot_set: RID
var slot_buffer: RID

var faces_write_dispatch_set: RID
var faces_write_dispatch_buffer: RID


func _pre() -> void:
	push_constant.resize(SIZE_PARAMS)
	init_table_buffer()
	init_slot_buffer()
	init_faces_write_dispatch()


func init_table_buffer() -> void:
	# Power of two above 2x the vertex count, so probes stay short
	var table_size := nearest_po2(params.in_vertex_count * 2)

	# uint table_size header, then array
	table_buffer_size = align_buffer(4 + table_size * 4)
	table_buffer = rd.storage_buffer_create(table_buffer_size)
	table_clear.resize(table_buffer_size)
	table_clear.fill(EMPTY_BYTE)
	table_clear.encode_u32(0, table_size)

	table_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([table_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
	], SurfaceShaders.faces_dedupe.shader, 2)

	sets.faces_table = table_set
	sets.faces_table_buffer = table_buffer


func init_slot_buffer() -> void:
	# Only survivors are ever read back, so this needs no clearing
	slot_buffer = rd.storage_buffer_create(params.in_vertex_count * 2)

	slot_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([slot_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
	], SurfaceShaders.faces_dedupe.shader, 3)

	sets.faces_slot = slot_set
	sets.faces_slot_buffer = slot_buffer


func init_faces_write_dispatch() -> void:
	faces_write_dispatch_buffer = dispatch_buffer_create()

	faces_write_dispatch_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([faces_write_dispatch_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
	], SurfaceShaders.faces_dedupe.shader, 4)

	sets.faces_write_dispatch_buffer = faces_write_dispatch_buffer


func compute() -> void:
	rd.buffer_update(table_buffer, 0, table_buffer_size, table_clear)
	rd.buffer_clear(faces_write_dispatch_buffer, 0, 12)

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.faces_dedupe.pipeline)
	rd.compute_list_bind_uniform_set(compute_list, sets.in_mesh, 0)
	rd.compute_list_bind_uniform_set(compute_list, sets.faces, 1)
	rd.compute_list_bind_uniform_set(compute_list, table_set, 2)
	rd.compute_list_bind_uniform_set(compute_list, slot_set, 3)
	rd.compute_list_bind_uniform_set(compute_list, faces_write_dispatch_set, 4)
	rd.compute_list_dispatch_indirect(compute_list, sets.faces_dedupe_dispatch_buffer, 0)
	rd.compute_list_end()


func _notification(what) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	for rid in [
		table_set, table_buffer, slot_set, slot_buffer, faces_write_dispatch_set, faces_write_dispatch_buffer,
	]:
		if rid.is_valid():
			rd.free_rid(rid)
