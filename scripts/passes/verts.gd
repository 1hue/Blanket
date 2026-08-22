extends ComputePass
class_name VertsPass

const SIZE_PARAMS = 52

var out_uniform_set: RID
var out_in_map_buffer: RID


func _pre() -> void:
	push_constant.resize(SIZE_PARAMS)


## Add an empty mesh surface
func _allocate_verts_out() -> void:
	# Only read the counts - avoid a whole GPU-CPU-GPU data roundtrip
	var unique_count := rd.buffer_get_data(uniforms.slot_buffer, 0, 4).decode_u32(0)
	var edge_count := rd.buffer_get_data(uniforms.edges_buffer, 0, 4).decode_u32(0)
	var face_count := rd.buffer_get_data(uniforms.faces_buffer, 0, 4).decode_u32(0)
	assert(face_count > 0, "Face count: %d" % face_count)
	#assert(edge_count > 0, "Edge count: %d" % edge_count)

	var vertex_count := unique_count + edge_count * 4
	var index_count := face_count * 3 + edge_count * 6

	surface.allocate(vertex_count, index_count, Mesh.ARRAY_NORMAL | Mesh.ARRAY_CUSTOM0 | Mesh.ARRAY_COLOR)

	var format := mesh.surface_get_format(surface.idx)
	params.out_vertex_count = vertex_count
	params.out_vertex_stride = RenderingServer.mesh_surface_get_format_vertex_stride(format, vertex_count)
	params.out_normal_offset = RenderingServer.mesh_surface_get_format_offset(format, vertex_count, Mesh.ARRAY_NORMAL)
	params.out_normal_stride = RenderingServer.mesh_surface_get_format_normal_tangent_stride(format, vertex_count)
	params.out_marker_offset = RenderingServer.mesh_surface_get_format_offset(format, vertex_count, Mesh.ARRAY_CUSTOM0)
	params.out_attribute_stride = RenderingServer.mesh_surface_get_format_attribute_stride(format, vertex_count)
	params.out_index_stride = RenderingServer.mesh_surface_get_format_index_stride(format, vertex_count)

	_init_uniforms(vertex_count)


func _init_uniforms(vertex_count: int) -> void:
	var out_vertex_buffer := RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(mesh_rid, surface.idx)
	var out_index_buffer := RenderingServer.mesh_surface_get_index_buffer_rd_rid(mesh_rid, surface.idx)
	var out_attribute_buffer := RenderingServer.mesh_surface_get_attribute_buffer_rd_rid(mesh_rid, surface.idx)
	out_in_map_buffer = rd.storage_buffer_create(vertex_count * 4)

	out_uniform_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([out_vertex_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
		ComputeUtil.create_uniform([out_index_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 1),
		ComputeUtil.create_uniform([out_attribute_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 2),
		ComputeUtil.create_uniform([out_in_map_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 3)
	], SurfaceShaders.verts.shader, 2)


func pack_params() -> PackedByteArray:
	push_constant.encode_float(0, params.local_up.x)
	push_constant.encode_float(4, params.local_up.y)
	push_constant.encode_float(8, params.local_up.z)
	push_constant.encode_u32(12, params.in_vertex_count)
	push_constant.encode_u32(16, params.in_vertex_stride)
	push_constant.encode_u32(20, params.in_normal_offset)
	push_constant.encode_u32(24, params.in_normal_stride)
	push_constant.encode_u32(28, params.select_vertex_stride)
	push_constant.encode_u32(32, params.select_normal_offset)
	push_constant.encode_u32(36, params.select_normal_stride)
	push_constant.encode_u32(40, params.select_marker_offset)
	push_constant.encode_u32(44, params.select_attribute_stride)
	push_constant.encode_u32(48, params.select_index_stride)

	return push_constant


## Dispatch verts.glsl to fill the empty mesh surface GPU-side
func compute() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.verts.pipeline)
	rd.compute_list_set_push_constant(compute_list, pack_params(), SIZE_PARAMS)
	rd.compute_list_bind_uniform_set(compute_list, uniforms.source_set, 0)
	#rd.compute_list_bind_uniform_set(compute_list, selection_uniform_set, 1)
	rd.compute_list_bind_uniform_set(compute_list, out_uniform_set, 2)
	#rd.compute_list_bind_uniform_set(compute_list, dedupe_uniform_set, 3)
	rd.compute_list_dispatch_indirect(compute_list, uniforms.edges_dispatch_buffer, 0)
	rd.compute_list_end()
