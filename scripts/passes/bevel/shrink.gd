extends ComputePass
class_name BevelShrink

const SIZE_PARAMS = 12

var out_uniform_set: RID
var shared_edge_buffer: RID
var shared_edge_uniform_set: RID
var dispatch_buffer: RID
var dispatch_uniform_set: RID


func _pre() -> void:
	push_constant.resize(SIZE_PARAMS)
	size()
	surface.allocate(params.bevel_vertex_count, params.bevel_index_count, Mesh.ARRAY_NORMAL | Mesh.ARRAY_COLOR)
	init_uniforms()
	init_indirect_dispatch()


func size() -> void:
	var arc_steps := params.bevel_segments * 2
	var arc_count := arc_steps + 1
	var fan_verts := 1 + params.BEVEL_WEDGE_SEGMENTS * arc_count
	var fan_tris := arc_steps + (params.BEVEL_WEDGE_SEGMENTS - 1) * arc_steps * 2

	params.bevel_vertex_count = params.in_index_count + params.max_shared_edges * fan_verts * 2
	params.bevel_index_count = (params.in_index_count + params.max_shared_edges * (fan_tris * 2 + arc_steps * 2)) * 3


func init_uniforms() -> void:
	var vertex_buffer := RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(mesh_rid, surface.idx)
	var index_buffer := RenderingServer.mesh_surface_get_index_buffer_rd_rid(mesh_rid, surface.idx)
	var attribute_buffer := RenderingServer.mesh_surface_get_attribute_buffer_rd_rid(mesh_rid, surface.idx)

	out_uniform_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([vertex_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
		ComputeUtil.create_uniform([index_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 1),
		ComputeUtil.create_uniform([attribute_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 2),
	], SurfaceShaders.bevel_shrink.shader, 1)

	uniforms.bevel_out_set = out_uniform_set

	var format := mesh.surface_get_format(surface.idx)
	params.bevel_color_offset = RenderingServer.mesh_surface_get_format_offset(format, params.bevel_vertex_count, Mesh.ARRAY_COLOR)
	params.bevel_attribute_stride = RenderingServer.mesh_surface_get_format_attribute_stride(format, params.bevel_vertex_count)

	# 3 edges per face
	var shared_edge_size := 4 + params.max_shared_edges * 16
	shared_edge_buffer = rd.storage_buffer_create(shared_edge_size)
	rd.buffer_clear(shared_edge_buffer, 0, shared_edge_size)
	shared_edge_uniform_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([shared_edge_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
	], SurfaceShaders.bevel_shrink.shader, 2)

	uniforms.shared_edge_set = shared_edge_uniform_set

	#debug_buffer = rd.storage_buffer_create(24*4)
	#rd.buffer_clear(debug_buffer, 0, 24*4)
	#debug_uniform_set = rd.uniform_set_create([
		#ComputeUtil.create_uniform([debug_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
	#], SurfaceShaders.bevel_fill.shader, 4)


## Separate dispatch buffers. WARNING: must not be passed into target shader - engine constraint.
func init_indirect_dispatch() -> void:
	dispatch_buffer = rd.storage_buffer_create(
		12, PackedByteArray(), RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT
	)

	uniforms.shrink_dispatch_buffer = dispatch_buffer

	dispatch_uniform_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([dispatch_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
	], SurfaceShaders.bevel_shrink.shader, 3)


func pack_params() -> PackedByteArray:
	push_constant.encode_float(0, params.bevel_shrink)
	push_constant.encode_u32(4, params.bevel_color_offset)
	push_constant.encode_u32(8, params.bevel_attribute_stride)

	return push_constant


func compute() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.bevel_shrink.pipeline)
	rd.compute_list_set_push_constant(compute_list, pack_params(), SIZE_PARAMS)
	# TODO: Replace with output from the Select multipass
	rd.compute_list_bind_uniform_set(compute_list, uniforms.source_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, out_uniform_set, 1)
	rd.compute_list_bind_uniform_set(compute_list, shared_edge_uniform_set, 2)
	rd.compute_list_bind_uniform_set(compute_list, dispatch_uniform_set, 3)
	rd.compute_list_dispatch(compute_list, ceili(params.in_index_count / (128.0 * 3.0)), 1, 1)
	rd.compute_list_end()


func _notification(what) -> void:
	if what != NOTIFICATION_PREDELETE:
		return

	for rid in [
		out_uniform_set, shared_edge_uniform_set, shared_edge_buffer,
		dispatch_uniform_set, dispatch_buffer
	]:
		if rid.is_valid():
			rd.free_rid(rid)
