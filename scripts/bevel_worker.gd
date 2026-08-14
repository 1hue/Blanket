extends RefCounted
class_name BevelWorker

var rd: RenderingDevice
var params: BevelParams

var mesh: ArrayMesh
var mesh_rid: RID:
	get: return mesh.get_rid()

var source_idx: int
var idx := -1

var in_uniform_set: RID
var out_uniform_set: RID

var shared_edge_buffer: RID
var shared_edge_uniform_set: RID
var dispatch_buffer: RID
var dispatch_uniform_set: RID
var debug_buffer: RID
var debug_uniform_set: RID


func _init(p_mesh: ArrayMesh, p_source_idx: int) -> void:
	rd = RenderingServer.get_rendering_device()
	mesh = p_mesh
	source_idx = p_source_idx
	params = BevelParams.new()


func bake() -> void:
	_size()
	_allocate()
	_init_uniforms()
	_compute_shrink()
	_compute_wedge()
	_compute_fill()
	debug()


func _size() -> void:
	params.in_vertex_count = mesh.surface_get_array_len(source_idx)
	params.in_index_count = mesh.surface_get_array_index_len(source_idx)
	params.out_vertex_count = params.in_vertex_count + get_bevel_vertex_count()


func get_bevel_vertex_count() -> int:
	var face_count := params.in_index_count / 3
	var segment_verts := params.segments * 4 * 3 # 4 faces per long segment: 2 wedges + 1 quad
	return face_count * segment_verts * 3 # Each face can have 3 shared edges


func _allocate() -> void:
	if idx >= 0:
		mesh.surface_remove(idx)
		idx = -1

	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	vertices.resize(params.out_vertex_count)
	colors.resize(params.out_vertex_count)
	normals.resize(params.out_vertex_count)
	indices.resize(params.out_vertex_count)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices

	idx = mesh.get_surface_count()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_STORAGE_BUFFER)
	mesh.custom_aabb = _source_aabb()


func _init_uniforms() -> void:
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
	var shared_edge_size := 4 + (params.in_index_count * 16)
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


func _compute_shrink() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.bevel_shrink.pipeline)
	rd.compute_list_set_push_constant(compute_list, params.pack_shrink(), BevelParams.SIZE_SHRINK)
	rd.compute_list_bind_uniform_set(compute_list, in_uniform_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, out_uniform_set, 1)
	rd.compute_list_bind_uniform_set(compute_list, shared_edge_uniform_set, 2)
	rd.compute_list_bind_uniform_set(compute_list, dispatch_uniform_set, 3)
	rd.compute_list_dispatch(compute_list, ceili(params.in_index_count / (128.0 * 3.0)), 1, 1)
	rd.compute_list_end()


func _compute_wedge() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.bevel_wedge.pipeline)
	rd.compute_list_set_push_constant(compute_list, params.pack_wedge(), BevelParams.SIZE_WEDGE)
	rd.compute_list_bind_uniform_set(compute_list, in_uniform_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, out_uniform_set, 1)
	rd.compute_list_bind_uniform_set(compute_list, shared_edge_uniform_set, 2)
	rd.compute_list_dispatch_indirect(compute_list, dispatch_buffer, 0)
	rd.compute_list_end()


func _compute_fill() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.bevel_fill.pipeline)
	rd.compute_list_set_push_constant(compute_list, params.pack_fill(), BevelParams.SIZE_FILL)
	rd.compute_list_bind_uniform_set(compute_list, in_uniform_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, out_uniform_set, 1)
	rd.compute_list_bind_uniform_set(compute_list, shared_edge_uniform_set, 2)
	rd.compute_list_bind_uniform_set(compute_list, debug_uniform_set, 4)
	rd.compute_list_dispatch_indirect(compute_list, dispatch_buffer, 0)
	rd.compute_list_end()


func debug() -> void:
	var dispatch := rd.buffer_get_data(dispatch_buffer)
	var shared_edges := rd.buffer_get_data(shared_edge_buffer)

	print_rich("[color=pale_green]",
		"\ndebug: ", rd.buffer_get_data(debug_buffer).to_float32_array(),
		"\ndispatch: x=%d y=%d z=%d" % [dispatch.decode_u32(0), dispatch.decode_u32(4), dispatch.decode_u32(8)],
		"[/color]",
		"\nshared_count: ", shared_edges.decode_u32(0),
		"\n\n[color=dark_khaki]shared edges: ", ComputeUtil.to_vector4i_array(shared_edges.slice(4)), "[/color]",
	)

	var out_vertex_buffer := RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(mesh_rid, idx)
	var out_attr_buffer := RenderingServer.mesh_surface_get_attribute_buffer_rd_rid(mesh_rid, idx)
	var out_index_buffer := RenderingServer.mesh_surface_get_index_buffer_rd_rid(mesh_rid, idx)
	print_rich("[color=pale_green]",
		#"\nverts: ", rd.buffer_get_data(out_vertex_buffer).to_vector3_array(),
		"\nattrs: ", rd.buffer_get_data(out_attr_buffer),
		"\nindices: ", ComputeUtil.to_int16_array(rd.buffer_get_data(out_index_buffer)),
		"[/color]"
	)


func _source_aabb() -> AABB:
	var vertices: PackedVector3Array = mesh.surface_get_arrays(source_idx)[Mesh.ARRAY_VERTEX]
	var aabb := AABB(vertices[0], Vector3.ZERO)
	for v in vertices:
		aabb = aabb.expand(v)
	return aabb


func _notification(what) -> void:
	if what != NOTIFICATION_PREDELETE:
		return

	for rid in [
		in_uniform_set, out_uniform_set,
		dispatch_uniform_set, dispatch_buffer,
		shared_edge_uniform_set, shared_edge_buffer,
		debug_uniform_set, debug_buffer,
	]:
		if rid.is_valid():
			rd.free_rid(rid)
