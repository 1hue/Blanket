extends RefCounted
class_name ComputeWorker

signal output(message: String)

const SHADER_PATHS: Array[String] = [
	"res://shaders/count.glsl",
	"res://shaders/compact.glsl"
]
const COUNT_BUFFER_OFFSET := 16

var rd: RenderingDevice
var shaders: Array[RID] = [RID(), RID()]
var pipelines: Array[RID] = [RID(), RID()]

var params_count: ParamsCount
var params_compact: ParamsCompact

var mesh_uniform_set: RID
var vertex_uniform: RDUniform
var index_count: int
var index_stride: int

var count_buffer: RID
var count_buffer_size: int
var count_uniform_set: RID

var mesh: ArrayMesh
var owned_surface: int
var owned_surface_uniform_set: RID


func _init(p_mesh: ArrayMesh, global_transform: Transform3D) -> void:
	rd = RenderingServer.get_rendering_device()
	mesh = p_mesh

	var format := mesh.surface_get_format(0)
	var primitive := mesh.surface_get_primitive_type(0)

	assert(format & Mesh.ARRAY_FORMAT_NORMAL != 0, "Mesh must have normals: %s" % mesh)
	assert(primitive == Mesh.PRIMITIVE_TRIANGLES, "Mesh must be of triangle primitives: %s is %s" % [mesh, primitive])

	index_count = mesh.surface_get_array_index_len(0)
	var vertex_count := mesh.surface_get_array_len(0)
	index_stride = RenderingServer.mesh_surface_get_format_index_stride(format, vertex_count)
	var normal_offset := RenderingServer.mesh_surface_get_format_offset(format, vertex_count, Mesh.ARRAY_NORMAL)
	var normal_stride := RenderingServer.mesh_surface_get_format_normal_tangent_stride(format, vertex_count)
	var colors_offset := RenderingServer.mesh_surface_get_format_offset(format, vertex_count, Mesh.ARRAY_COLOR)
	var attribute_stride := RenderingServer.mesh_surface_get_format_attribute_stride(format, vertex_count)

	shaders = [
		ComputeUtil.compile_shader(rd, SHADER_PATHS[0]),
		ComputeUtil.compile_shader(rd, SHADER_PATHS[1]),
	]
	pipelines = [
		rd.compute_pipeline_create(shaders[0], ComputeUtil.create_spec_constants([
			index_count, vertex_count, index_stride, normal_offset, normal_stride, colors_offset, attribute_stride
		])),
		rd.compute_pipeline_create(shaders[1]),
	]

	params_count = ParamsCount.new()
	params_count.local_up = global_transform.basis.inverse() * Vector3.UP
	params_count.changed.connect(compute)

	params_compact = ParamsCompact.new()
	params_compact.local_up = global_transform.basis.inverse() * Vector3.UP

	_init_mesh()


func _notification(what) -> void:
	if what == NOTIFICATION_PREDELETE:
		print_rich('[color=dim_gray]Worker goodbye![/color]')

		if count_buffer.is_valid():
			rd.free_rid(count_buffer)
		for pipeline in pipelines:
			if pipeline.is_valid():
				rd.free_rid(pipeline)
		for shader in shaders:
			if shader.is_valid():
				rd.free_rid(shader)


func _init_mesh() -> void:
	var mesh_rid := mesh.get_rid()
	var buffer := RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(mesh_rid, 0)
	vertex_uniform = ComputeUtil.create_uniform([buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0)

	buffer = RenderingServer.mesh_surface_get_index_buffer_rd_rid(mesh_rid, 0)
	var index_uniform := ComputeUtil.create_uniform([buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 1)

	buffer = RenderingServer.mesh_surface_get_attribute_buffer_rd_rid(mesh_rid, 0)
	var attribute_uniform := ComputeUtil.create_uniform([buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 2)

	mesh_uniform_set = rd.uniform_set_create([vertex_uniform, index_uniform, attribute_uniform], shaders[0], 0)

	_init_count_buffer()


func _init_count_buffer() -> void:
	if count_buffer.is_valid():
		rd.free_rid(count_buffer)

	count_buffer_size = COUNT_BUFFER_OFFSET + index_count * index_stride # Indices is 16-bit uint each = 2 bytes
	count_buffer = rd.storage_buffer_create(count_buffer_size)

	var count_uniform := ComputeUtil.create_uniform([count_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER)
	count_uniform_set = rd.uniform_set_create([count_uniform], shaders[0], 1)


func clear() -> void:
	rd.buffer_clear(count_buffer, 0, count_buffer_size) # reset counter


func compute() -> void:
	clear()
	compute_count()
	add_surface()
	compute_compact()


func add_surface() -> void:
	if params_compact.changed.is_connected(compute_compact):
		params_compact.changed.disconnect(compute_compact)

	if owned_surface:
		mesh.surface_remove(owned_surface)

	var counter := rd.buffer_get_data(count_buffer, 0 , 4).decode_u32(0)
	var eligible_indices := rd.buffer_get_data(count_buffer, 4, counter * 12).to_int32_array()

	_add_surface(mesh, eligible_indices)
	_init_new_surface_buffer()

	var target_format := mesh.surface_get_format(owned_surface)
	params_compact.vertex_count = eligible_indices.size()
	params_compact.target_vertex_stride = RenderingServer.mesh_surface_get_format_vertex_stride(
		target_format, params_compact.vertex_count
	)
	var source_format := mesh.surface_get_format(0)
	var source_vertex_count := mesh.surface_get_array_len(0)
	params_compact.source_vertex_stride = RenderingServer.mesh_surface_get_format_vertex_stride(
		source_format, source_vertex_count
	)

	params_compact.changed.connect(compute_compact)


func _init_new_surface_buffer() -> void:
	var mesh_rid := mesh.get_rid()
	var buffer := RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(mesh_rid, owned_surface)
	var target_vertex_uniform := ComputeUtil.create_uniform([buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 1)

	owned_surface_uniform_set = rd.uniform_set_create([vertex_uniform, target_vertex_uniform], shaders[1], 0)


func _add_surface(array_mesh: ArrayMesh, eligible_indices: PackedInt32Array) -> void:
	var source_arrays := array_mesh.surface_get_arrays(0)
	var source_verts: PackedVector3Array = source_arrays[Mesh.ARRAY_VERTEX]
	var source_normals: PackedVector3Array = source_arrays[Mesh.ARRAY_NORMAL]

	var count := eligible_indices.size()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	vertices.resize(count)
	normals.resize(count)
	indices.resize(count)

	for i in count:
		var source_index := eligible_indices[i]
		vertices[i] = source_verts[source_index]
		normals[i] = source_normals[source_index]
		indices[i] = i

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices

	owned_surface = array_mesh.get_surface_count()
	array_mesh.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES,
		arrays,
		[],
		{},
		Mesh.ARRAY_FLAG_USE_STORAGE_BUFFER
	)


func compute_count() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipelines[0])
	rd.compute_list_set_push_constant(compute_list, params_count.bytes, params_count.bytes.size())
	rd.compute_list_bind_uniform_set(compute_list, mesh_uniform_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, count_uniform_set, 1)
	rd.compute_list_dispatch(compute_list, 1, 1, 1)
	rd.compute_list_end()


func compute_compact() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipelines[1])
	rd.compute_list_set_push_constant(compute_list, params_compact.bytes, params_compact.bytes.size())
	rd.compute_list_bind_uniform_set(compute_list, owned_surface_uniform_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, count_uniform_set, 1)
	rd.compute_list_dispatch(compute_list, 1, 1, 1)
	rd.compute_list_end()
	#var count := rd.compute_list_dispatch_indirect()
	out()

func out() -> void:
	var bytes_out := rd.buffer_get_data(count_buffer)
	var counter := bytes_out.decode_u32(0)
	#var arr := ComputeUtil.to_vector3i_array(ComputeUtil.to_int16_array(bytes_out.slice(COUNT_BUFFER_OFFSET)))

	print_rich('Output: x%d | [color=pale_green][b]%s[/b][/color] %sB' % [
		counter, ComputeUtil.to_vector3i_array(bytes_out.slice(4).to_int32_array()), count_buffer_size
	])

	output.emit("%s" % [counter])


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
