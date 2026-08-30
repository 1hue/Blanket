extends ComputePass
class_name FacesWritePass

const SIZE_PARAMS = 4

var out_uniform_set: RID


func _pre() -> void:
	push_constant.resize(SIZE_PARAMS)


## Godot needs the surface sized CPU-side, so the counts have to come back here
func allocate() -> void:
	var counts := rd.buffer_get_data(uniforms.faces_buffer, 0, 8)
	var face_count := counts.decode_u32(0)

	params.out_vertex_count = counts.decode_u32(4)
	params.out_index_count = face_count * 3

	surface.allocate(
		params.out_vertex_count,
		params.out_index_count,
		Mesh.ARRAY_NORMAL | Mesh.ARRAY_COLOR | Mesh.ARRAY_CUSTOM0
	)

	var vertex_buffer := RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(mesh_rid, surface.idx)
	var index_buffer := RenderingServer.mesh_surface_get_index_buffer_rd_rid(mesh_rid, surface.idx)
	var attribute_buffer := RenderingServer.mesh_surface_get_attribute_buffer_rd_rid(mesh_rid, surface.idx)

	out_uniform_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([vertex_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
		ComputeUtil.create_uniform([index_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 1),
		ComputeUtil.create_uniform([attribute_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 2),
	], SurfaceShaders.faces_write.shader, 4)

	uniforms.faces_out_set = out_uniform_set

	var format := mesh.surface_get_format(surface.idx)
	var count := params.out_vertex_count
	params.out_vertex_stride = RenderingServer.mesh_surface_get_format_vertex_stride(format, count)
	params.out_index_stride = RenderingServer.mesh_surface_get_format_index_stride(format, count)
	params.out_normal_offset = RenderingServer.mesh_surface_get_format_offset(format, count, Mesh.ARRAY_NORMAL)
	params.out_normal_stride = RenderingServer.mesh_surface_get_format_normal_tangent_stride(format, count)
	params.out_color_offset = RenderingServer.mesh_surface_get_format_offset(format, count, Mesh.ARRAY_COLOR)
	params.out_marker_offset = RenderingServer.mesh_surface_get_format_offset(format, count, Mesh.ARRAY_CUSTOM0)
	params.out_attribute_stride = RenderingServer.mesh_surface_get_format_attribute_stride(format, count)


func pack_params() -> PackedByteArray:
	push_constant.encode_u32(0, params.faces_table_size)

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
	rd.compute_list_bind_uniform_set(compute_list, out_uniform_set, 4)
	rd.compute_list_dispatch_indirect(compute_list, uniforms.faces_write_dispatch_buffer, 0)
	rd.compute_list_end()


func _notification(what) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	if out_uniform_set.is_valid():
		rd.free_rid(out_uniform_set)
