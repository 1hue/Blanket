extends ComputeWorker
class_name BevelShrinkWorker

const SIZE_PARAMS = 12

var normal_sum_buffer: RID
var normal_sum_size: int
var normal_sum_uniform_set: RID


func pack_params() -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(SIZE_PARAMS)
	bytes.encode_float(0, params.shrink_amount)
	bytes.encode_u32(4, params.out_color_offset)
	bytes.encode_u32(8, params.out_attribute_stride)
	return bytes


func compute() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.bevel_shrink.pipeline)
	rd.compute_list_set_push_constant(compute_list, pack_params(), SIZE_PARAMS)
	rd.compute_list_bind_uniform_set(compute_list, in_uniform_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, out_uniform_set, 1)
	rd.compute_list_bind_uniform_set(compute_list, shared_edge_uniform_set, 2)
	rd.compute_list_bind_uniform_set(compute_list, dispatch_uniform_set, 3)
	rd.compute_list_dispatch(compute_list, ceili(params.in_index_count / (128.0 * 3.0)), 1, 1)
	rd.compute_list_end()



func _pre() -> void:
	var in_vertex_buffer := RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(mesh_rid, source_idx)
	var in_index_buffer := RenderingServer.mesh_surface_get_index_buffer_rd_rid(mesh_rid, source_idx)

	in_uniform_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([in_vertex_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
		ComputeUtil.create_uniform([in_index_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 1),
	], SurfaceShaders.bevel_shrink.shader, 0)

	var out_vertex_buffer := RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(mesh_rid, idx)
	var out_index_buffer := RenderingServer.mesh_surface_get_index_buffer_rd_rid(mesh_rid, idx)
	var out_attribute_buffer := RenderingServer.mesh_surface_get_attribute_buffer_rd_rid(mesh_rid, idx)

	out_uniform_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([out_vertex_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
		ComputeUtil.create_uniform([out_index_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 1),
		ComputeUtil.create_uniform([out_attribute_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 2),
	], SurfaceShaders.bevel_shrink.shader, 1)

	var format := mesh.surface_get_format(idx)
	params.out_color_offset = RenderingServer.mesh_surface_get_format_offset(format, params.out_vertex_count, Mesh.ARRAY_COLOR)
	params.out_attribute_stride = RenderingServer.mesh_surface_get_format_attribute_stride(format, params.out_vertex_count)

	# 3 edges per face
	var shared_edge_size := 4 + params.max_shared_edges * 16
	shared_edge_buffer = rd.storage_buffer_create(shared_edge_size)
	rd.buffer_clear(shared_edge_buffer, 0, shared_edge_size)
	shared_edge_uniform_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([shared_edge_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
	], SurfaceShaders.bevel_shrink.shader, 2)

	dispatch_buffer = rd.storage_buffer_create(
		12, PackedByteArray(), RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT
	)
	rd.buffer_clear(dispatch_buffer, 0, 12)
	dispatch_uniform_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([dispatch_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
	], SurfaceShaders.bevel_shrink.shader, 3)

	debug_buffer = rd.storage_buffer_create(24*4)
	rd.buffer_clear(debug_buffer, 0, 24*4)
	debug_uniform_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([debug_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
	], SurfaceShaders.bevel_fill.shader, 4)
