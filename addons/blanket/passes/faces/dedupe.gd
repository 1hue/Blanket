# SPDX-FileCopyrightText: © 2026 1hue
# SPDX-License-Identifier: MIT

extends BlanketPass
class_name DedupePass

const SIZE_PARAMS = 4
const EMPTY_BYTE = UINT32_MAX
const TABLE_ENTRY_STRIDE = 8 # uvec2: vert, out_vert
const TABLE_LOAD_FACTOR = 2 # Halve the occupancy so probes stay short

var table_set: RID
var table_buffer: RID
var table_buffer_size: int
var table_clear: PackedByteArray


func _pre() -> void:
	push_constant.resize(SIZE_PARAMS)

	init_table_buffer()


func init_table_buffer() -> void:
	# One entry per unique position among selected corners - capped by both source verts and corners
	var max_entries := mini(params.in_vertex_count, params.in_face_count * 3)
	var table_size := nearest_po2(maxi(max_entries, 1) * TABLE_LOAD_FACTOR)

	# uint table_size header, then array
	table_buffer_size = align_buffer(4 + table_size * TABLE_ENTRY_STRIDE)

	table_buffer = rd.storage_buffer_create(table_buffer_size)
	table_clear.resize(table_buffer_size)
	table_clear.fill(EMPTY_BYTE)
	table_clear.encode_u32(0, table_size)

	table_set = rd.uniform_set_create([
		BlanketUtil.create_uniform([table_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
	], BlanketShaders.dedupe.shaders[version], 2)

	sets.faces_table = table_set
	sets.faces_table_buffer = table_buffer


func compute() -> void:
	rd.buffer_update(table_buffer, 0, table_buffer_size, table_clear)

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, BlanketShaders.dedupe.pipelines[version])
	rd.compute_list_bind_uniform_set(compute_list, sets.in_mesh, 0)
	rd.compute_list_bind_uniform_set(compute_list, sets.selected_faces, 1)
	rd.compute_list_bind_uniform_set(compute_list, table_set, 2)
	rd.compute_list_bind_uniform_set(compute_list, sets.dispatch, 3)
	rd.compute_list_dispatch_indirect(compute_list, sets.dispatch_buffer, BlanketSets.Dispatch.DEDUPE)
	rd.compute_list_end()

	sync_dispatch()


func _notification(what) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	for rid in [table_set, table_buffer]:
		if rid:
			rd.free_rid(rid)
