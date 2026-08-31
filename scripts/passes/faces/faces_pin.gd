extends ComputePass
class_name FacesPinPass

const SIZE_PARAMS = 12


func _pre() -> void:
	push_constant.resize(SIZE_PARAMS)


func pack_params() -> PackedByteArray:
	push_constant.encode_u32(0, params.out_marker_offset)
	push_constant.encode_u32(4, params.out_color_offset)
	push_constant.encode_u32(8, params.out_attribute_stride)

	return push_constant


func compute() -> void:
	# Zero means unpinned, so clearing sets the default and only pins get written
	var attribute_buffer := RenderingServer.mesh_surface_get_attribute_buffer_rd_rid(mesh_rid, surface.idx)
	rd.buffer_clear(attribute_buffer, 0, params.out_vertex_count * params.out_attribute_stride)

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.faces_pin.pipeline)
	rd.compute_list_set_push_constant(compute_list, pack_params(), SIZE_PARAMS)
	rd.compute_list_bind_uniform_set(compute_list, uniforms.out_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, uniforms.faces_set, 1)
	rd.compute_list_dispatch_indirect(compute_list, uniforms.faces_write_dispatch_buffer, 0)
	rd.compute_list_end()
