extends ComputePass
class_name BevelShrinkPass

const WORKGROUP_SIZE = 64
const SIZE_PARAMS = 16


func _pre() -> void:
	push_constant.resize(SIZE_PARAMS)


func allocate_out_mesh() -> void:
	var faces := rd.buffer_get_data(sets.index_scratch_buffer, 0, 4).decode_u32(0)
	var verts := rd.buffer_get_data(sets.vertex_scratch_buffer, 0, 4).decode_u32(0)
	var shared := rd.buffer_get_data(sets.shared_edge_buffer, 0, 4).decode_u32(0)

	params.out_vertex_count = verts + faces * 3 + shared * params.edge_vertex_count
	params.out_index_count = (faces + shared * params.edge_face_count) * 3

	surface.allocate(
		params.out_vertex_count,
		params.out_index_count,
		Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_COLOR | Mesh.ARRAY_FORMAT_CUSTOM0
	)

	init_out_mesh_set()
	set_out_params()


func init_out_mesh_set() -> void:
	var vertex_buffer := RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(surface.mesh_rid, surface.idx)
	var index_buffer := RenderingServer.mesh_surface_get_index_buffer_rd_rid(surface.mesh_rid, surface.idx)
	var attribute_buffer := RenderingServer.mesh_surface_get_attribute_buffer_rd_rid(surface.mesh_rid, surface.idx)

	sets.out_mesh = rd.uniform_set_create([
		ComputeUtil.create_uniform([vertex_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
		ComputeUtil.create_uniform([index_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 1),
		ComputeUtil.create_uniform([attribute_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 2),
	], SurfaceShaders.bevel_shrink.shader, 0)


func set_out_params() -> void:
	var format := surface.format
	var verts := params.out_vertex_count

	params.out_vertex_stride = RenderingServer.mesh_surface_get_format_vertex_stride(format, verts)
	params.out_index_stride = RenderingServer.mesh_surface_get_format_index_stride(format, verts)
	params.out_normal_offset = RenderingServer.mesh_surface_get_format_offset(format, verts, Mesh.ARRAY_NORMAL)
	params.out_normal_stride = RenderingServer.mesh_surface_get_format_normal_tangent_stride(format, verts)
	params.out_color_offset = RenderingServer.mesh_surface_get_format_offset(format, verts, Mesh.ARRAY_COLOR)
	params.out_custom_offset = RenderingServer.mesh_surface_get_format_offset(format, verts, Mesh.ARRAY_CUSTOM0)
	params.out_attribute_stride = RenderingServer.mesh_surface_get_format_attribute_stride(format, verts)


func pack_params() -> PackedByteArray:
	push_constant.encode_float(0, params.bevel_width)
	push_constant.encode_u32(4, params.out_color_offset)
	push_constant.encode_u32(8, params.out_custom_offset)
	push_constant.encode_u32(12, params.out_attribute_stride)

	return push_constant


func compute() -> void:
	allocate_out_mesh()

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.bevel_shrink.pipeline)
	rd.compute_list_set_push_constant(compute_list, pack_params(), SIZE_PARAMS)
	rd.compute_list_bind_uniform_set(compute_list, sets.out_mesh, 0)
	rd.compute_list_bind_uniform_set(compute_list, sets.faces_scratch, 1)
	rd.compute_list_bind_uniform_set(compute_list, sets.shared_mask, 2)
	rd.compute_list_dispatch_indirect(compute_list, sets.dispatch_buffer, 36)
	rd.compute_list_end()
