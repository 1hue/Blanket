extends RefCounted
class_name ComputeWorker

signal output(message: String)

const SHADER_PATHS: Array[String] = [
	"res://shaders/count.glsl",
	"res://shaders/compact.glsl"
]

var rd: RenderingDevice
var shaders: Array[RID] = [RID(), RID()]
var pipelines: Array[RID] = [RID(), RID()]

var mesh: RID
var mesh_uniform_set: RID
var vertex_count: int
var index_count: int

var count_buffer: RID
var count_uniform_set: RID

var push_constant: PackedByteArray
var p_local_up: Vector3:
	get:
		return Vector3(
			push_constant.decode_float(0),
			push_constant.decode_float(4),
			push_constant.decode_float(8)
		)
	set(value):
		push_constant.encode_float(0, value.x)
		push_constant.encode_float(4, value.y)
		push_constant.encode_float(8, value.z)
		compute()
var p_up_threshold_degrees: float:
	get:
		return push_constant.decode_float(12)
	set(value):
		push_constant.encode_float(12, value)
		compute()
var p_shift_amount: float:
	get:
		return push_constant.decode_float(16)
	set(value):
		push_constant.encode_float(16, value)
		compute()


func _init(p_mesh: ArrayMesh) -> void:
	rd = RenderingServer.get_rendering_device()

	vertex_count = p_mesh.surface_get_array_len(0)
	index_count = p_mesh.surface_get_array_index_len(0)
	prints("vertex_count", vertex_count, "index_count", index_count)

	shaders = [
		ComputeUtil.compile_shader(rd, SHADER_PATHS[0]),
		ComputeUtil.compile_shader(rd, SHADER_PATHS[1]),
	]
	pipelines = [
		rd.compute_pipeline_create(shaders[0], ComputeUtil.create_spec_constants([index_count])),
		rd.compute_pipeline_create(shaders[1]),
	]

	push_constant.resize(20)
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

	var buffer := RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(mesh, 0)
	var vertex_uniform := ComputeUtil.create_uniform([buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 1)

	buffer = RenderingServer.mesh_surface_get_index_buffer_rd_rid(mesh, 0)
	var index_uniform := ComputeUtil.create_uniform([buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0)

	mesh_uniform_set = rd.uniform_set_create([index_uniform, vertex_uniform], shaders[0], 0)

	_init_count_buffer(buffer)


func _init_count_buffer(index_buffer: RID) -> void:
	if count_buffer.is_valid():
		rd.free_rid(count_buffer)

	var data_init := PackedByteArray()
	data_init.resize(16)
	count_buffer = rd.storage_buffer_create(data_init.size(), data_init)

	var count_uniform := ComputeUtil.create_uniform([count_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER)
	count_uniform_set = rd.uniform_set_create([count_uniform], shaders[0], 1)


func compute() -> void:
	compute_count()
	#compute_compact()


func compute_count() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipelines[0])
	rd.compute_list_set_push_constant(compute_list, push_constant, push_constant.size())
	rd.compute_list_bind_uniform_set(compute_list, mesh_uniform_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, count_uniform_set, 1)
	rd.compute_list_dispatch(compute_list, 1, 1, 1)
	rd.compute_list_end()
	out()


func out() -> void:
	var bytes_out := rd.buffer_get_data(count_buffer)
	var arr := bytes_out.slice(4).to_float32_array()

	print_rich('Output: x%d | [color=pale_green][b]%s[/b][/color] (%s)' % [
		bytes_out.decode_u32(0), arr, bytes_out.size()
	])

	output.emit("%s" % [arr])
