extends RefCounted
class_name ComputeWorker

signal output(message: String)

const FACES_HEADER = 16 # dispatch (12) + count (4)
const EDGES_HEADER = 16 # dispatch (12) + count (4)

var rd: RenderingDevice
var shaders: Array[RID]:
	get: return SurfaceService.shaders
var pipelines: Array[RID]:
	get: return SurfaceService.pipelines
var params: ComputeParams

var mesh: ArrayMesh
var mesh_rid: RID:
	get: return mesh.get_rid()
var in_uniform_sets: Array[RID] = [RID(), RID()] # 0 = Vertex, 1 = Index & Attribute

var faces_buffer: RID
var faces_buffer_size: int
var faces_uniform: RDUniform
var faces_uniform_set: RID

var edges_buffer: RID
var edges_buffer_size: int
var edges_uniform: RDUniform
var edges_uniform_set: RID

var out_uniform_set: RID
var out_in_map_buffer: RID

var surface: ComputeSurface


func _init(p_mesh: ArrayMesh, surface_idx: int, global_transform: Transform3D) -> void:
	rd = RenderingServer.get_rendering_device()
	mesh = p_mesh
	surface = ComputeSurface.new(p_mesh, surface_idx)

	_init_params(global_transform)
	_init_in_uniforms()
	_init_faces_uniforms()
	_init_edges_uniforms()


func _init_params(global_transform: Transform3D) -> void:
	var format := mesh.surface_get_format(surface.idx)
	var primitive := mesh.surface_get_primitive_type(surface.idx)
	var vertex_count := mesh.surface_get_array_len(surface.idx)

	assert(format & Mesh.ARRAY_FORMAT_NORMAL != 0, "Mesh must have normals: %s" % mesh)
	assert(primitive == Mesh.PRIMITIVE_TRIANGLES, "Mesh must be triangles: %s is %s" % [mesh, primitive])

	params = ComputeParams.new()
	params.in_vertex_count = vertex_count
	params.in_vertex_stride = RenderingServer.mesh_surface_get_format_vertex_stride(format, vertex_count)
	params.in_index_count = mesh.surface_get_array_index_len(surface.idx)
	params.in_index_stride = RenderingServer.mesh_surface_get_format_index_stride(format, vertex_count)
	params.in_normal_offset = RenderingServer.mesh_surface_get_format_offset(format, vertex_count, Mesh.ARRAY_NORMAL)
	params.in_normal_stride = RenderingServer.mesh_surface_get_format_normal_tangent_stride(format, vertex_count)
	params.in_color_offset = RenderingServer.mesh_surface_get_format_offset(format, vertex_count, Mesh.ARRAY_COLOR)
	params.in_attribute_stride = RenderingServer.mesh_surface_get_format_attribute_stride(format, vertex_count)
	params.local_up = global_transform.basis.inverse() * Vector3.UP
	params.changed.connect(update)


func _init_in_uniforms() -> void:
	var vertex_buffer := RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(mesh_rid, surface.idx)
	var in_vertex_uniform := ComputeUtil.create_uniform([vertex_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0)

	var index_buffer := RenderingServer.mesh_surface_get_index_buffer_rd_rid(mesh_rid, surface.idx)
	var index_uniform := ComputeUtil.create_uniform([index_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0)

	var attribute_buffer := RenderingServer.mesh_surface_get_attribute_buffer_rd_rid(mesh_rid, surface.idx)
	var attribute_uniform := ComputeUtil.create_uniform([attribute_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 1)

	in_uniform_sets[0] = rd.uniform_set_create([in_vertex_uniform], shaders[0], 0)
	in_uniform_sets[1] = rd.uniform_set_create([index_uniform, attribute_uniform], shaders[0], 1)


func _init_faces_uniforms() -> void:
	faces_buffer_size = FACES_HEADER + params.in_index_count * 4 # worst case: every vert is a face corner
	faces_buffer = rd.storage_buffer_create(faces_buffer_size)

	faces_uniform = ComputeUtil.create_uniform([faces_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER)
	faces_uniform_set = rd.uniform_set_create([faces_uniform], shaders[0], 2)


func _init_edges_uniforms() -> void:
	# uvec3 dispatch + uint count + uvec2 edges[], worst case every face contributes 3 unique edges
	edges_buffer_size = EDGES_HEADER + params.in_index_count * 8
	edges_buffer = rd.storage_buffer_create(edges_buffer_size)

	edges_uniform = ComputeUtil.create_uniform([edges_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER)
	edges_uniform_set = rd.uniform_set_create([edges_uniform], shaders[1], 1)


func clear() -> void:
	rd.buffer_clear(faces_buffer, 0, faces_buffer_size)
	rd.buffer_clear(edges_buffer, 0, edges_buffer_size)


## Free buffers after bake, keep the owned surface's buffers
func _cleanup_bake() -> void:
	rd.free_rid(faces_uniform_set)
	rd.free_rid(faces_buffer)
	rd.free_rid(edges_uniform_set)
	rd.free_rid(edges_buffer)


func bake() -> void:
	clear()
	_bake_selection()
	_init_geometry_out()
	_bake_geometry_out()
	_cleanup_bake()
	update()


## Select upright faces and outer edges
func _bake_selection() -> void:
	var compute_list := rd.compute_list_begin()

	# Faces
	rd.compute_list_bind_compute_pipeline(compute_list, pipelines[0])
	rd.compute_list_set_push_constant(compute_list, params.pack_faces(), ComputeParams.SIZE_FACES)
	rd.compute_list_bind_uniform_set(compute_list, in_uniform_sets[0], 0)
	rd.compute_list_bind_uniform_set(compute_list, in_uniform_sets[1], 1)
	rd.compute_list_bind_uniform_set(compute_list, faces_uniform_set, 2)
	rd.compute_list_dispatch(compute_list, 1, 1, 1)

	# Edges
	rd.compute_list_bind_compute_pipeline(compute_list, pipelines[1])
	rd.compute_list_bind_uniform_set(compute_list, faces_uniform_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, edges_uniform_set, 1)
	rd.compute_list_dispatch_indirect(compute_list, faces_buffer, 0)

	rd.compute_list_end()


## Spawn an empty mesh surface
func _init_geometry_out() -> void:
	# Only read the counts - avoid a whole GPU-CPU-GPU data roundtrip
	var face_count := rd.buffer_get_data(faces_buffer, 12, 4).decode_u32(0)
	var edge_count := rd.buffer_get_data(edges_buffer, 12, 4).decode_u32(0)

	var vertex_count := face_count * 3 + edge_count * 4
	var index_count := face_count * 3 + edge_count * 6

	surface.allocate(vertex_count, index_count)

	var format := mesh.surface_get_format(surface.idx)
	params.out_vertex_count = vertex_count
	params.out_vertex_stride = RenderingServer.mesh_surface_get_format_vertex_stride(format, vertex_count)
	params.out_normal_offset = RenderingServer.mesh_surface_get_format_offset(format, vertex_count, Mesh.ARRAY_NORMAL)
	params.out_normal_stride = RenderingServer.mesh_surface_get_format_normal_tangent_stride(format, vertex_count)
	params.out_marker_offset = RenderingServer.mesh_surface_get_format_offset(format, vertex_count, Mesh.ARRAY_CUSTOM0)
	params.out_attribute_stride = RenderingServer.mesh_surface_get_format_attribute_stride(format, vertex_count)

	_init_geometry_out_uniforms(vertex_count)


## Prepare for verts.glsl
func _init_geometry_out_uniforms(vertex_count: int) -> void:
	if out_uniform_set.is_valid():
		rd.free_rid(out_uniform_set)
	if out_in_map_buffer.is_valid():
		rd.free_rid(out_in_map_buffer)

	var out_vertex_buffer := RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(mesh_rid, surface.idx)
	var out_index_buffer := RenderingServer.mesh_surface_get_index_buffer_rd_rid(mesh_rid, surface.idx)
	var out_attribute_buffer := RenderingServer.mesh_surface_get_attribute_buffer_rd_rid(mesh_rid, surface.idx)

	out_in_map_buffer = rd.storage_buffer_create(vertex_count * 4)

	var out_vertex_uniform := ComputeUtil.create_uniform([out_vertex_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0)
	var out_index_uniform := ComputeUtil.create_uniform([out_index_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 1)
	var out_attribute_uniform := ComputeUtil.create_uniform([out_attribute_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 2)
	var out_source_uniform := ComputeUtil.create_uniform([out_in_map_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 3)
	out_uniform_set = rd.uniform_set_create(
		[out_vertex_uniform, out_index_uniform, out_attribute_uniform, out_source_uniform], shaders[2], 3
	)


## Dispatch verts.glsl to fill the empty mesh surface GPU-side
func _bake_geometry_out() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipelines[2])
	rd.compute_list_set_push_constant(compute_list, params.pack_verts(), ComputeParams.SIZE_VERTS)
	rd.compute_list_bind_uniform_set(compute_list, in_uniform_sets[0], 0)
	rd.compute_list_bind_uniform_set(compute_list, faces_uniform_set, 1)
	rd.compute_list_bind_uniform_set(compute_list, edges_uniform_set, 2)
	rd.compute_list_bind_uniform_set(compute_list, out_uniform_set, 3)
	rd.compute_list_dispatch_indirect(compute_list, edges_buffer, 0)
	rd.compute_list_end()


## Dispatch shape.glsl to reposition the spawned mesh surface
func _compute_shape() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipelines[3])
	rd.compute_list_set_push_constant(compute_list, params.pack_shape(), ComputeParams.SIZE_SHAPE)
	rd.compute_list_bind_uniform_set(compute_list, in_uniform_sets[0], 0)
	rd.compute_list_bind_uniform_set(compute_list, out_uniform_set, 1)
	rd.compute_list_dispatch(compute_list, ceili(params.out_vertex_count / 256.0), 1, 1)
	rd.compute_list_end()


func update() -> void:
	_compute_shape()


func _notification(what) -> void:
	if what != NOTIFICATION_PREDELETE:
		return

	for rid in in_uniform_sets:
		if rid.is_valid():
			rd.free_rid(rid)

	for rid in [faces_uniform_set, faces_buffer, edges_uniform_set, edges_buffer, out_uniform_set, out_in_map_buffer]:
		if rid.is_valid():
			rd.free_rid(rid)
