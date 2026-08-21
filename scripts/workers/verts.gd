extends ComputeWorker
class_name Verts

var out_uniform_set: RID
var out_in_map_buffer: RID


func _pre() -> void:
	pass


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

	surface.allocate(vertex_count, index_count)

	var format := mesh.surface_get_format(surface.idx)
	params.out_vertex_count = vertex_count
	params.out_vertex_stride = RenderingServer.mesh_surface_get_format_vertex_stride(format, vertex_count)
	params.out_normal_offset = RenderingServer.mesh_surface_get_format_offset(format, vertex_count, Mesh.ARRAY_NORMAL)
	params.out_normal_stride = RenderingServer.mesh_surface_get_format_normal_tangent_stride(format, vertex_count)
	params.out_marker_offset = RenderingServer.mesh_surface_get_format_offset(format, vertex_count, Mesh.ARRAY_CUSTOM0)
	params.out_attribute_stride = RenderingServer.mesh_surface_get_format_attribute_stride(format, vertex_count)
	params.out_index_stride = RenderingServer.mesh_surface_get_format_index_stride(format, vertex_count)

	_init_uniforms(vertex_count)


## Prepare buffers for verts.glsl
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


## Dispatch verts.glsl to fill the empty mesh surface GPU-side
func compute() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.verts.pipeline)
	rd.compute_list_set_push_constant(compute_list, params.pack_verts(), ComputeParams.SIZE_VERTS)
	rd.compute_list_bind_uniform_set(compute_list, in_uniform_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, selection_uniform_set, 1)
	rd.compute_list_bind_uniform_set(compute_list, out_uniform_set, 2)
	rd.compute_list_bind_uniform_set(compute_list, dedupe_uniform_set, 3)
	rd.compute_list_dispatch_indirect(compute_list, edges_dispatch_buffer, 0)
	rd.compute_list_end()
