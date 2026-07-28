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
var params: ComputePushConstant

var mesh: RID
var mesh_uniform_set: RID
var index_count: int
var index_stride: int

var count_buffer: RID
var count_buffer_size: int
var count_uniform_set: RID


func _init(p_mesh: ArrayMesh) -> void:
	rd = RenderingServer.get_rendering_device()

	var format := p_mesh.surface_get_format(0)
	var primitive := p_mesh.surface_get_primitive_type(0)
	assert(format & Mesh.ARRAY_FORMAT_NORMAL, "Mesh must have normals: %s" % p_mesh)
	assert(primitive == Mesh.PRIMITIVE_TRIANGLES, "Mesh must be of triangle primitives: %s is %s" % [p_mesh, primitive])

	index_count = p_mesh.surface_get_array_index_len(0)
	var vertex_count := p_mesh.surface_get_array_len(0)
	index_stride = RenderingServer.mesh_surface_get_format_index_stride(format, vertex_count)
	var normal_offset := RenderingServer.mesh_surface_get_format_offset(format, vertex_count, Mesh.ARRAY_NORMAL)
	var normal_stride := RenderingServer.mesh_surface_get_format_normal_tangent_stride(format, vertex_count)

	shaders = [
		ComputeUtil.compile_shader(rd, SHADER_PATHS[0]),
		ComputeUtil.compile_shader(rd, SHADER_PATHS[1]),
	]
	pipelines = [
		rd.compute_pipeline_create(shaders[0], ComputeUtil.create_spec_constants([
			index_count, vertex_count, index_stride, normal_offset, normal_stride
		])),
		rd.compute_pipeline_create(shaders[1]),
	]

	params = ComputePushConstant.new()
	params.changed.connect(compute)

	_init_mesh(p_mesh)


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


func _init_mesh(p_mesh: ArrayMesh) -> void:
	mesh = p_mesh.get_rid()

	#var format := p_mesh.surface_get_format(0)
	#var surface := RenderingServer.mesh_get_surface(mesh, 0)
	# DEBUG
	#prints("surface", surface)
	#prints("vertex_count", vertex_count, "index_count", index_count,
		#"normals_offset", normals_offset, "indices_offset", indices_offset, "index_stride", index_stride)

	var buffer := RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(mesh, 0)
	var vertex_uniform := ComputeUtil.create_uniform([buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 1)

	#var normal_tangent_stride := RenderingServer.mesh_surface_get_format_normal_tangent_stride(format, vertex_count)
	#var length := vertex_count * normal_tangent_stride
	#var normals_data := rd.buffer_get_data(buffer, 0, 16)
	#prints("\n", normals_data, "\n")
	#prints("vert buffer 16 bytes:", normals_data)
	#prints(" - try decode normal at [0]:", ComputeUtil.read_normal(normals_data, 0))
	#normals_data = rd.buffer_get_data(buffer, 72, 16)
	#prints("288 offset 16 bytes:", normals_data)
	#prints(" - try decode normal at [0]:", ComputeUtil.read_normal(normals_data, 0))

	buffer = RenderingServer.mesh_surface_get_index_buffer_rd_rid(mesh, 0)
	var index_uniform := ComputeUtil.create_uniform([buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0)
	#var index_data := rd.buffer_get_data(buffer)
	#var indices := ComputeUtil.to_vector3i_array(ComputeUtil.to_int16_array(index_data))
	#prints("index buffer: ", index_data)

	mesh_uniform_set = rd.uniform_set_create([index_uniform, vertex_uniform], shaders[0], 0)

	_init_count_buffer()


func _init_count_buffer() -> void:
	if count_buffer.is_valid():
		rd.free_rid(count_buffer)

	count_buffer_size = COUNT_BUFFER_OFFSET + index_count * index_stride # Indices is 16-bit uint each = 2 bytes

	var data_init := PackedByteArray()
	data_init.resize(count_buffer_size)
	count_buffer = rd.storage_buffer_create(data_init.size(), data_init)

	var count_uniform := ComputeUtil.create_uniform([count_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER)
	count_uniform_set = rd.uniform_set_create([count_uniform], shaders[0], 1)


func clear() -> void:
	rd.buffer_clear(count_buffer, 0, count_buffer_size) # reset counter


func compute() -> void:
	clear()
	compute_count()
	#compute_compact()


func compute_count() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipelines[0])
	rd.compute_list_set_push_constant(compute_list, params.bytes, params.bytes.size())
	rd.compute_list_bind_uniform_set(compute_list, mesh_uniform_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, count_uniform_set, 1)
	rd.compute_list_dispatch(compute_list, 1, 1, 1)
	rd.compute_list_end()
	out()


func out() -> void:
	var bytes_out := rd.buffer_get_data(count_buffer)
	var arr := ComputeUtil.to_vector3i_array(ComputeUtil.to_int16_array(bytes_out.slice(COUNT_BUFFER_OFFSET)))

	print_rich('Output: x%d | [color=pale_green][b]%s[/b][/color]' % [
		bytes_out.decode_u32(0), bytes_out.slice(4).to_vector3_array()
	])

	output.emit("%s" % [arr])
