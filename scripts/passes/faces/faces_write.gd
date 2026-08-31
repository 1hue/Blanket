extends ComputePass
class_name FacesWritePass

const SIZE_PARAMS = 12

var faces_out_uniform_set: RID


func _pre() -> void:
	push_constant.resize(SIZE_PARAMS)


## Godot needs the surface sized CPU-side, so the counts have to come back here
func allocate() -> void:
	var counts := rd.buffer_get_data(uniforms.faces_buffer, 0, 8)
	var face_count := counts.decode_u32(0)

	params.faces_out_vertex_count = counts.decode_u32(4)
	params.faces_out_index_count = face_count * 3

	surface.allocate(
		params.faces_out_vertex_count,
		params.faces_out_index_count,
		Mesh.ARRAY_NORMAL | Mesh.ARRAY_COLOR | Mesh.ARRAY_CUSTOM0
	)

	var vertex_buffer := RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(mesh_rid, surface.idx)
	var index_buffer := RenderingServer.mesh_surface_get_index_buffer_rd_rid(mesh_rid, surface.idx)
	var attribute_buffer := RenderingServer.mesh_surface_get_attribute_buffer_rd_rid(mesh_rid, surface.idx)

	faces_out_uniform_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([vertex_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
		ComputeUtil.create_uniform([index_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 1),
		ComputeUtil.create_uniform([attribute_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 2),
	], SurfaceShaders.faces_write.shader, 4)

	uniforms.faces_out_set = faces_out_uniform_set

	var format := mesh.surface_get_format(surface.idx)
	var count := params.faces_out_vertex_count
	params.faces_out_vertex_stride = RenderingServer.mesh_surface_get_format_vertex_stride(format, count)
	params.faces_out_index_stride = RenderingServer.mesh_surface_get_format_index_stride(format, count)
	params.faces_out_color_offset = RenderingServer.mesh_surface_get_format_offset(format, count, Mesh.ARRAY_COLOR)
	params.faces_out_marker_offset = RenderingServer.mesh_surface_get_format_offset(format, count, Mesh.ARRAY_CUSTOM0)
	params.faces_out_attribute_stride = RenderingServer.mesh_surface_get_format_attribute_stride(format, count)


func pack_params() -> PackedByteArray:
	push_constant.encode_u32(0, params.faces_table_size)
	push_constant.encode_u32(4, params.faces_out_color_offset)
	push_constant.encode_u32(8, params.faces_out_attribute_stride)

	return push_constant


func compute() -> void:
	allocate()

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.faces_write.pipeline)
	rd.compute_list_set_push_constant(compute_list, pack_params(), SIZE_PARAMS)
	rd.compute_list_bind_uniform_set(compute_list, uniforms.source_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, uniforms.faces_set, 1)
	rd.compute_list_bind_uniform_set(compute_list, uniforms.faces_table_set, 2)
	rd.compute_list_bind_uniform_set(compute_list, uniforms.faces_slot_set, 3)
	rd.compute_list_bind_uniform_set(compute_list, faces_out_uniform_set, 4)
	rd.compute_list_dispatch_indirect(compute_list, uniforms.faces_write_dispatch_buffer, 0)
	rd.compute_list_end()

	#dump()
	test()


func dump() -> void:
	var faces := rd.buffer_get_data(uniforms.faces_buffer)
	print_rich("[color=aqua]faces buffer raw: ", faces, "[/color]")
	var table := rd.buffer_get_data(uniforms.faces_table_buffer)
	print_rich("[color=aqua]table[", table.size() / 4, "] uint32: ", ComputeUtil.to_uint32_array(table), "[/color]")
	var slots := rd.buffer_get_data(uniforms.faces_slot_buffer)
	print_rich("[color=aqua]slots[", slots.size() / 2, "] uint16: ", ComputeUtil.to_int16_array(slots), "[/color]")
	var data := RenderingServer.mesh_get_surface(mesh_rid, surface.idx)
	var verts: PackedByteArray = data.vertex_data
	var indices: PackedByteArray = data.index_data

	prints(
		"\nindex_data[%s]:" % data.index_count, ComputeUtil.to_int16_array(indices),
	)


## Verifies dedupe produced a valid, fully merged surface. Debug builds only.
func test() -> void:
	var vertex_buffer := RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(mesh_rid, surface.idx)
	var index_buffer := RenderingServer.mesh_surface_get_index_buffer_rd_rid(mesh_rid, surface.idx)

	var positions := rd.buffer_get_data(
		vertex_buffer, 0, params.faces_out_vertex_count * params.faces_out_vertex_stride
	).to_float32_array()
	var indices := ComputeUtil.to_int16_array(rd.buffer_get_data(index_buffer))

	assert(params.faces_out_vertex_count > 0, "No verts survived dedupe")
	assert(indices.size() == params.faces_out_index_count, "Index count %d does not match surface %d" % [
		indices.size(), params.faces_out_index_count
	])

	# Every position must be distinct, or dedupe missed a merge
	var seen := {}
	for i in params.faces_out_vertex_count:
		var position := Vector3(positions[i * 3], positions[i * 3 + 1], positions[i * 3 + 2])
		assert(not seen.has(position), "Vert %d duplicates vert %s at %s" % [i, seen.get(position), position])
		seen[position] = i

	# Every slot must be reachable, or the surface has gaps
	var referenced := {}
	for index in indices:
		assert(index < params.faces_out_vertex_count, "Index %d exceeds vert count %d" % [index, params.faces_out_vertex_count])
		referenced[index] = true

	assert(referenced.size() == params.faces_out_vertex_count, "Only %d of %d verts are referenced" % [
		referenced.size(), params.faces_out_vertex_count
	])

	# A triangle naming one vert twice is degenerate
	for face in indices.size() / 3:
		var a := indices[face * 3]
		var b := indices[face * 3 + 1]
		var c := indices[face * 3 + 2]

		assert(a != b and b != c and c != a, "Face %d is degenerate: (%d, %d, %d)" % [face, a, b, c])


func _notification(what) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	if faces_out_uniform_set.is_valid():
		rd.free_rid(faces_out_uniform_set)
