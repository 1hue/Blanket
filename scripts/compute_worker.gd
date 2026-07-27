extends RefCounted
class_name ComputeWorker

signal output

const SHADER_PATH = "res://shaders/compute.glsl"

var rd: RenderingDevice
var shader: RID
var pipeline: RID
var storage_uniform_set: RID
var storage_buffer: RID

# Outputs
var counter: int
var push_constant: PackedByteArray
var storage_out: String

var mesh_uniform: RDUniform
var mesh_buffer: RID
var mesh_uniform_set: RID


func _init() -> void:
	rd = RenderingServer.get_rendering_device()
	if not rd:
		push_error("Couldn't create local RenderingDevice on GPU: %s" % RenderingServer.get_video_adapter_name())

	if pipeline.is_valid():
		rd.free_rid(pipeline)
	if shader.is_valid():
		rd.free_rid(shader)

	shader = _compile_shader(rd, SHADER_PATH)
	pipeline = rd.compute_pipeline_create(shader)

	push_constant.resize(8)
	_init_storage_buffer() # Reset storage buffer upon recompilation


func _init_storage_buffer() -> void:
	if storage_buffer.is_valid():
		rd.free_rid(storage_buffer)

	var storage_init := PackedByteArray()
	storage_init.resize(8)
	storage_buffer = rd.storage_buffer_create(storage_init.size(), storage_init)

	var storage_uniform := create_uniform([storage_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER)
	storage_uniform_set = rd.uniform_set_create([storage_uniform], shader, 0)


func _compile_shader(p_rd: RenderingDevice, p_shader_path: String) -> RID:
	var shader_file: RDShaderFile = load(p_shader_path)
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()

	var err = shader_spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if err: push_warning(err)

	return p_rd.shader_create_from_spirv(shader_spirv)


func create_uniform(rids: Array[RID], type: RenderingDevice.UniformType, binding: int = 0) -> RDUniform:
	var uniform: RDUniform = RDUniform.new()
	uniform.uniform_type = type
	uniform.binding = binding
	for rid in rids:
		uniform.add_id(rid)
	return uniform


func set_mesh(mesh: RID) -> void:
	if mesh_uniform_set:
		rd.free_rid(mesh_uniform_set)

	mesh_buffer = RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(mesh, 0)

	mesh_uniform = create_uniform([mesh_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER)
	mesh_uniform_set = rd.uniform_set_create([mesh_uniform], shader, 1)


func compute(vertex_count: int, debug_in: int) -> void:
	push_constant.encode_u32(0, vertex_count)
	push_constant.encode_u32(4, debug_in)

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_set_push_constant(compute_list, push_constant, push_constant.size())
	rd.compute_list_bind_uniform_set(compute_list, storage_uniform_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, mesh_uniform_set, 1)
	rd.compute_list_dispatch(compute_list, 1, 1, 1)
	rd.compute_list_end()
	out(vertex_count)


func out(vertex_count: int, ) -> void:
	var bytes_out := rd.buffer_get_data(storage_buffer)

	counter = bytes_out.decode_u32(0)
	storage_out = "%s" % bytes_out.decode_u32(4)

	bytes_out = rd.buffer_get_data(mesh_buffer, 0, vertex_count * 12)
	var verts := bytes_out.to_vector3_array()
	bytes_out = rd.buffer_get_data(mesh_buffer, vertex_count * 12)
	var rest := bytes_out.to_float32_array()

	print_rich('Output: x%d | [color=pale_green][b]%s[/b][/color] %s %s' % [
		counter, verts, verts.size(), rest
	])

	output.emit()


func _notification(what) -> void:
	if what == NOTIFICATION_PREDELETE:
		print_rich('[color=dim_gray]Worker goodbye![/color]')

		if not rd:
			return
		if storage_buffer.is_valid():
			rd.free_rid(storage_buffer)
		if shader.is_valid():
			rd.free_rid(shader)
