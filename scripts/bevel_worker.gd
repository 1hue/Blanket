extends RefCounted
class_name BevelWorker

var rd: RenderingDevice
var shaders: Array[RID]:
	get: return SurfaceService.shaders
var pipelines: Array[RID]:
	get: return SurfaceService.pipelines

var mesh: ArrayMesh
var mesh_rid: RID:
	get: return mesh.get_rid()

var source_idx: int
var idx := -1

var in_uniform_set: RID
var out_uniform_set: RID

var in_face_count: int
var in_corner_count: int
var quad_face_base: int
var fan_face_base: int
var out_vertex_count: int
var out_face_count: int

const MAX_VALENCE = 32
const SHRINK = 0.3


func _init(p_mesh: ArrayMesh, p_source_idx: int) -> void:
	rd = RenderingServer.get_rendering_device()
	mesh = p_mesh
	source_idx = p_source_idx


func bake() -> void:
	_size()
	_allocate()
	_init_uniforms()
	_compute_shrink()
	debug()


func _size() -> void:
	in_corner_count = mesh.surface_get_array_index_len(source_idx)
	in_face_count = in_corner_count / 3

	out_vertex_count = in_corner_count

	quad_face_base = in_face_count
	fan_face_base = quad_face_base + in_corner_count * 2
	out_face_count = fan_face_base + in_corner_count * (MAX_VALENCE - 2)


func _allocate() -> void:
	if idx >= 0:
		mesh.surface_remove(idx)
		idx = -1

	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	vertices.resize(out_vertex_count)
	colors.resize(out_vertex_count)
	normals.resize(out_vertex_count)
	indices.resize(out_face_count * 3)

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
	], shaders[5], 0)

	var out_vertex_buffer := RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(mesh_rid, idx)
	var out_index_buffer := RenderingServer.mesh_surface_get_index_buffer_rd_rid(mesh_rid, idx)
	var out_attribute_buffer := RenderingServer.mesh_surface_get_attribute_buffer_rd_rid(mesh_rid, idx)

	out_uniform_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([out_vertex_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
		ComputeUtil.create_uniform([out_index_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 1),
		ComputeUtil.create_uniform([out_attribute_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 2),
	], shaders[5], 1)


func _compute_shrink() -> void:
	var format := mesh.surface_get_format(idx)
	var out_color_offset := RenderingServer.mesh_surface_get_format_offset(format, out_vertex_count, Mesh.ARRAY_COLOR)
	var out_attribute_stride := RenderingServer.mesh_surface_get_format_attribute_stride(format, out_vertex_count)

	var push := PackedByteArray()
	push.resize(20)
	push.encode_float(0, SHRINK)
	push.encode_u32(4, in_face_count)
	push.encode_u32(8, in_corner_count)
	push.encode_u32(12, out_color_offset)
	push.encode_u32(16, out_attribute_stride)

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipelines[5])
	rd.compute_list_set_push_constant(compute_list, push, push.size())
	rd.compute_list_bind_uniform_set(compute_list, in_uniform_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, out_uniform_set, 1)
	rd.compute_list_dispatch(compute_list, ceili(in_face_count / 256.0), 1, 1)
	rd.compute_list_end()


func debug() -> void:
	var out_vertex_buffer := RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(mesh_rid, idx)
	var out_index_buffer := RenderingServer.mesh_surface_get_index_buffer_rd_rid(mesh_rid, idx)

	var out_verts := rd.buffer_get_data(out_vertex_buffer)
	var out_indices := rd.buffer_get_data(out_index_buffer)

	print_rich("[color=pale_green] out_positions:", out_verts.to_vector3_array(), "[/color]")
	print_rich("[color=pale_green] out_indices:", ComputeUtil.to_vector3i_array(ComputeUtil.to_int16_array(out_indices)), "[/color]")


func _source_aabb() -> AABB:
	var vertices: PackedVector3Array = mesh.surface_get_arrays(source_idx)[Mesh.ARRAY_VERTEX]
	var aabb := AABB(vertices[0], Vector3.ZERO)
	for v in vertices:
		aabb = aabb.expand(v)
	return aabb


func _notification(what) -> void:
	if what != NOTIFICATION_PREDELETE:
		return

	for rid in [in_uniform_set, out_uniform_set]:
		if rid.is_valid():
			rd.free_rid(rid)
