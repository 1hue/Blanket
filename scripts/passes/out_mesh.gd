extends ComputePass
class_name OutMeshPass

const SIZE_PARAMS = 12


func _pre() -> void:
	push_constant.resize(SIZE_PARAMS)


func allocate() -> void:
	var verts := read_counter(sets.selected_vertex_buffer)
	var faces := read_counter(sets.selected_index_buffer)
	var shared := mini(read_counter(sets.shared_edge_buffer), params.max_edges)
	var boundary := mini(read_counter(sets.boundary_buffer), params.max_edges)

	params.wall_rim_base = verts + faces * 3 + shared * ComputeParams.EDGE_VERTS
	params.wall_grid_base = params.wall_rim_base + verts * ComputeParams.WALL_SIDE_VERTS_PER_VERT
	params.wall_face_base = faces + shared * ComputeParams.EDGE_FACES
	params.out_vertex_count = params.wall_grid_base + boundary * ComputeParams.WALL_VERTS_PER_EDGE
	params.out_index_count = (params.wall_face_base + boundary * ComputeParams.WALL_FACES_PER_EDGE) * 3

	surface.allocate(
		params.out_vertex_count,
		params.out_index_count,
		Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_COLOR | Mesh.ARRAY_FORMAT_CUSTOM0
	)

	init_out_mesh_set()
	set_out_params()


func read_counter(buffer: RID) -> int:
	return rd.buffer_get_data(buffer, 0, 4).decode_u32(0)


func init_out_mesh_set() -> void:
	var vertex_buffer := RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(surface.mesh_rid, surface.idx)
	var index_buffer := RenderingServer.mesh_surface_get_index_buffer_rd_rid(surface.mesh_rid, surface.idx)
	var attribute_buffer := RenderingServer.mesh_surface_get_attribute_buffer_rd_rid(surface.mesh_rid, surface.idx)

	sets.out_mesh = rd.uniform_set_create([
		ComputeUtil.create_uniform([vertex_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
		ComputeUtil.create_uniform([index_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 1),
		ComputeUtil.create_uniform([attribute_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 2),
	], SurfaceShaders.out_mesh.shader, 0)


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

	assert(params.out_index_stride == 2, "Index writes are hardcoded u16vec3")
	assert(params.out_attribute_stride - params.out_custom_offset == 16, "Custom0 must be RGBA_FLOAT")


func pack_params() -> PackedByteArray:
	push_constant.encode_u32(0, params.out_color_offset)
	push_constant.encode_u32(4, params.out_custom_offset)
	push_constant.encode_u32(8, params.out_attribute_stride)

	return push_constant


func compute() -> void:
	allocate()

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.out_mesh.pipeline)
	rd.compute_list_set_push_constant(compute_list, pack_params(), SIZE_PARAMS)
	rd.compute_list_bind_uniform_set(compute_list, sets.out_mesh, 0)
	rd.compute_list_bind_uniform_set(compute_list, sets.selected_faces, 1)
	rd.compute_list_bind_uniform_set(compute_list, sets.vertex_flag, 2)
	rd.compute_list_dispatch_indirect(compute_list, sets.dispatch_buffer, ComputeSets.Dispatch.OUT_MESH)
	rd.compute_list_end()
