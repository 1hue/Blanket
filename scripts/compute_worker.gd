extends RefCounted
class_name ComputeWorker

signal output(message: String)

const FACES_BUFFER_OFFSET = 16
const EDGES_BUFFER_OFFSET = 4

var rd: RenderingDevice
var shaders: Array[RID]:
	get: return SurfaceService.shaders
var pipelines: Array[RID]:
	get: return SurfaceService.pipelines
var params: ComputeParams

var mesh: ArrayMesh
var mesh_uniform_set: RID
var vertex_uniform: RDUniform

var faces_buffer: RID
var faces_buffer_size: int
var faces_uniform_set: RID

var edges_buffer: RID
var edges_buffer_size: int
var edges_uniform_set: RID

var owned_surface: int
var owned_surface_uniform_set: RID

var surface: ComputeSurface


func _init(p_mesh: ArrayMesh, surface_idx: int, global_transform: Transform3D) -> void:
	rd = RenderingServer.get_rendering_device()
	mesh = p_mesh
	surface = ComputeSurface.new(p_mesh, surface_idx)

	_init_params(global_transform)
	_init_mesh_buffer()
	_init_faces_buffer()
	_init_edges_buffer()


func _init_params(global_transform: Transform3D) -> void:
	var format := mesh.surface_get_format(surface.idx)
	var primitive := mesh.surface_get_primitive_type(surface.idx)
	var vertex_count := mesh.surface_get_array_len(surface.idx)

	assert(format & Mesh.ARRAY_FORMAT_NORMAL != 0, "Mesh must have normals: %s" % mesh)
	assert(primitive == Mesh.PRIMITIVE_TRIANGLES, "Mesh must be of triangle primitives: %s is %s" % [mesh, primitive])

	params = ComputeParams.new()
	params.source_vertex_count = mesh.surface_get_array_len(surface.idx)
	params.source_vertex_stride = RenderingServer.mesh_surface_get_format_vertex_stride(format, vertex_count)
	params.source_index_count = mesh.surface_get_array_index_len(surface.idx)
	params.source_index_stride = RenderingServer.mesh_surface_get_format_index_stride(format, vertex_count)
	params.source_normal_offset = RenderingServer.mesh_surface_get_format_offset(format, vertex_count, Mesh.ARRAY_NORMAL)
	params.source_normal_stride = RenderingServer.mesh_surface_get_format_normal_tangent_stride(format, vertex_count)
	params.source_colors_offset = RenderingServer.mesh_surface_get_format_offset(format, vertex_count, Mesh.ARRAY_COLOR)
	params.source_attribute_stride = RenderingServer.mesh_surface_get_format_attribute_stride(format, vertex_count)
	params.local_up = global_transform.basis.inverse() * Vector3.UP
	params.changed.connect(update)


func _init_mesh_buffer() -> void:
	var mesh_rid := mesh.get_rid()
	var buffer := RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(mesh_rid, 0)
	vertex_uniform = ComputeUtil.create_uniform([buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0)

	buffer = RenderingServer.mesh_surface_get_index_buffer_rd_rid(mesh_rid, 0)
	var index_uniform := ComputeUtil.create_uniform([buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 1)

	buffer = RenderingServer.mesh_surface_get_attribute_buffer_rd_rid(mesh_rid, 0)
	var attribute_uniform := ComputeUtil.create_uniform([buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 2)

	mesh_uniform_set = rd.uniform_set_create([vertex_uniform, index_uniform, attribute_uniform], shaders[0], 0)


func _init_faces_buffer() -> void:
	faces_buffer_size = FACES_BUFFER_OFFSET + params.index_count * 4 # Max faces buffer size is all verts stuffed into it
	faces_buffer = rd.storage_buffer_create(faces_buffer_size)

	var count_uniform := ComputeUtil.create_uniform([faces_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER)
	faces_uniform_set = rd.uniform_set_create([count_uniform], shaders[0], 1)


func _init_edges_buffer() -> void:
	edges_buffer_size = EDGES_BUFFER_OFFSET + params.index_count * params.index_stride # Indices is 16-bit uint each = 2 bytes
	edges_buffer = rd.storage_buffer_create(edges_buffer_size)

	var edges_uniform := ComputeUtil.create_uniform([edges_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER)
	edges_uniform_set = rd.uniform_set_create([edges_uniform], shaders[1], 1)


func clear() -> void:
	rd.buffer_clear(faces_buffer, 0, faces_buffer_size)


## Free up GPU memory after bake
func _cleanup_bake() -> void:
	rd.free_rid(faces_uniform_set)
	rd.free_rid(faces_buffer)
	rd.free_rid(edges_uniform_set)
	rd.free_rid(edges_buffer)


func _init_new_surface_buffer() -> void:
	if owned_surface_uniform_set.is_valid():
		rd.free_rid(owned_surface_uniform_set)

	var mesh_rid := mesh.get_rid()
	var buffer := RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(mesh_rid, owned_surface)
	var target_vertex_uniform := ComputeUtil.create_uniform([buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 1)

	owned_surface_uniform_set = rd.uniform_set_create([vertex_uniform, target_vertex_uniform], shaders[1], 0)


func bake() -> void:
	_bake()
	_add_surface()
	_cleanup_bake()
	update()


func _bake() -> void:
	var compute_list := rd.compute_list_begin()

	# 1st pass: Identify eligible surfaces
	rd.compute_list_bind_compute_pipeline(compute_list, pipelines[0])
	rd.compute_list_set_push_constant(compute_list, params.pack_faces(), params.SIZE_COUNT)
	rd.compute_list_bind_uniform_set(compute_list, mesh_uniform_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, faces_uniform_set, 1)
	rd.compute_list_dispatch(compute_list, 1, 1, 1)

	# 2nd pass: Identify outer edges
	rd.compute_list_bind_compute_pipeline(compute_list, pipelines[0])
	rd.compute_list_bind_uniform_set(compute_list, faces_uniform_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, edges_uniform_set, 1)
	rd.compute_list_dispatch_indirect(compute_list, faces_buffer, 0)

	rd.compute_list_end()


func _add_surface() -> void:
	var face_count := rd.buffer_get_data(faces_buffer, 12, 4).decode_u32(0)
	var face_indices := rd.buffer_get_data(faces_buffer, FACES_BUFFER_OFFSET, face_count * 12).to_int32_array()

	var edges_count := rd.buffer_get_data(edges_buffer, 0, 4).decode_u32(0)
	var edge_indices := rd.buffer_get_data(edges_buffer, 4, edges_count * 8).to_int32_array()

	surface.rebuild(face_indices, edge_indices, params.local_up)

	params.target_vertex_count = surface.vertex_count
	params.target_vertex_stride = surface.vertex_stride
	source_map_buffer = rd.storage_buffer_create(surface.source_map.size() * 4, surface.source_map.to_byte_array())


## Reposition verts of the added mesh surface
func update() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipelines[1])
	rd.compute_list_set_push_constant(compute_list, params.pack_position(), params.SIZE_POSITION)
	rd.compute_list_bind_uniform_set(compute_list, owned_surface_uniform_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, faces_uniform_set, 1)
	rd.compute_list_dispatch(compute_list, 1, 1, 1)
	rd.compute_list_end()
	#var count := rd.compute_list_dispatch_indirect()
	out()


func out() -> void:
	var bytes_out := rd.buffer_get_data(faces_buffer)
	var counter := bytes_out.decode_u32(0)
	#var arr := ComputeUtil.to_vector3i_array(ComputeUtil.to_int16_array(bytes_out.slice(FACES_BUFFER_OFFSET)))

	print_rich('Output: x%d | [color=pale_green][b]%s[/b][/color] %sB' % [
		counter, ComputeUtil.to_vector3i_array(bytes_out.slice(4).to_int32_array()), count_buffer_size
	])

	output.emit("%s" % [counter])


func _notification(what) -> void:
	if what == NOTIFICATION_PREDELETE:
		print_rich('[color=dim_gray]Worker goodbye![/color]')

		if mesh_uniform_set.is_valid():
			rd.free_rid(mesh_uniform_set)
		if faces_uniform_set.is_valid():
			rd.free_rid(faces_uniform_set)
		if faces_buffer.is_valid():
			rd.free_rid(faces_buffer)
		if edges_uniform_set.is_valid():
			rd.free_rid(edges_uniform_set)
		if edges_buffer.is_valid():
			rd.free_rid(edges_buffer)


#region Debug

#prints("Normals:", format & Mesh.ARRAY_FORMAT_NORMAL != 0, "| Colours:", format & Mesh.ARRAY_FORMAT_COLOR != 0)
#var format := p_mesh.surface_get_format(0)
#var surface := RenderingServer.mesh_get_surface(mesh, 0)
#prints("surface", surface)
#prints("vertex_count", vertex_count, "index_count", index_count,
	#"normals_offset", normals_offset, "indices_offset", indices_offset, "index_stride", index_stride)

#var normal_tangent_stride := RenderingServer.mesh_surface_get_format_normal_tangent_stride(format, vertex_count)
#var length := vertex_count * normal_tangent_stride
#var normals_data := rd.buffer_get_data(buffer, 0, 16)
#prints("\n", normals_data, "\n")
#prints("vert buffer 16 bytes:", normals_data)
#prints(" - try decode normal at [0]:", ComputeUtil.read_normal(normals_data, 0))
#normals_data = rd.buffer_get_data(buffer, 72, 16)
#prints("288 offset 16 bytes:", normals_data)
#prints(" - try decode normal at [0]:", ComputeUtil.read_normal(normals_data, 0))
#var index_data := rd.buffer_get_data(buffer)
#var indices := ComputeUtil.to_vector3i_array(ComputeUtil.to_int16_array(index_data))
#prints("index buffer: ", index_data)

#endregion
