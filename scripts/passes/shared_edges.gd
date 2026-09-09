extends ComputePass
class_name SharedEdgesPass

const WORKGROUP_SIZE = 64
const SIZE_PARAMS = 16
const STRUCT_STRIDE = 32

var shared_edge_set: RID
var shared_edge_buffer: RID
var shared_edge_buffer_size: int

var shared_mask_set: RID
var shared_mask_buffer: RID
var shared_mask_buffer_size: int


func _pre() -> void:
	push_constant.resize(SIZE_PARAMS)
	init_shared_edge_buffer()
	init_shared_mask_buffer()


func init_shared_edge_buffer() -> void:
	# shared_count, then one entry per manifold edge pair across the whole source mesh
	shared_edge_buffer_size = align_buffer(4 + params.max_shared_edges * STRUCT_STRIDE)
	shared_edge_buffer = rd.storage_buffer_create(shared_edge_buffer_size)

	shared_edge_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([shared_edge_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER),
	], SurfaceShaders.shared_edges.shader, 1)

	sets.shared_edge_buffer = shared_edge_buffer
	sets.shared_edge = shared_edge_set


func init_shared_mask_buffer() -> void:
	# One 3-bit mask per face, marking which of its edges are shared
	shared_mask_buffer_size = align_buffer(maxi(params.in_face_count, 1) * 4)
	shared_mask_buffer = rd.storage_buffer_create(shared_mask_buffer_size)

	shared_mask_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([shared_mask_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER),
	], SurfaceShaders.shared_edges.shader, 2)

	sets.shared_mask_buffer = shared_mask_buffer
	sets.shared_mask = shared_mask_set


func allocate_out_mesh() -> void:
	var faces := rd.buffer_get_data(sets.selected_index_buffer, 0, 4).decode_u32(0)
	var verts := rd.buffer_get_data(sets.selected_vertex_buffer, 0, 4).decode_u32(0)
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
	push_constant.encode_u32(0, params.out_custom_offset)
	push_constant.encode_u32(4, params.out_attribute_stride)
	push_constant.encode_u32(8, params.max_shared_edges)
	push_constant.encode_float(12, params.crease_dot)

	return push_constant


func compute() -> void:
	rd.buffer_clear(shared_edge_buffer, 0, 16)
	rd.buffer_clear(shared_mask_buffer, 0, shared_mask_buffer_size)

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.shared_edges.pipeline)
	rd.compute_list_set_push_constant(compute_list, pack_params(), SIZE_PARAMS)
	rd.compute_list_bind_uniform_set(compute_list, sets.selected_faces, 0)
	rd.compute_list_bind_uniform_set(compute_list, shared_edge_set, 1)
	rd.compute_list_bind_uniform_set(compute_list, shared_mask_set, 2)
	rd.compute_list_bind_uniform_set(compute_list, sets.dispatch, 3)
	rd.compute_list_dispatch_indirect(compute_list, sets.dispatch_buffer, 24)
	rd.compute_list_end()

	allocate_out_mesh()


func _notification(what) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	for rid in [
		shared_edge_set, shared_edge_buffer,
		shared_mask_set, shared_mask_buffer,
	]:
		if rid.is_valid():
			rd.free_rid(rid)
