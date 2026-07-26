extends RefCounted
class_name ComputeWorker

signal output

const SHADER_PATH = "res://shaders/compute.glsl"
const INPUT_COUNT = 1
## Number of floats for our input/output.
## 1 counter + 2 floats for Vector2 `constants` + 1 empty float for "padding" + 8 actual inputs
const SSBO_SIZE = 1 + 2 + 1 + INPUT_COUNT

const SPEC_CONSTANT_0 = 12.0
const SPEC_CONSTANT_1 = 34.0

var rd: RenderingDevice
var shader: RID
var pipeline: RID
var uniform_set: RID
var storage_buffer: RID

# Outputs
var counter: int
var constants: Vector2
var storage_out: PackedFloat32Array
var benchmark: float


func _init() -> void:
	rd = RenderingServer.create_local_rendering_device()
	if not rd:
		push_error("Couldn't create local RenderingDevice on GPU: %s" % RenderingServer.get_video_adapter_name())

	_compile()


func _notification(what) -> void:
	if what == NOTIFICATION_PREDELETE:
		print_rich('[color=dim_gray]Worker goodbye![/color]')

		if not rd:
			return

		if storage_buffer.is_valid():
			rd.free_rid(storage_buffer)

		if shader.is_valid():
			rd.free_rid(shader)

		# Free if local RD only
		rd.free()


func _compile() -> void:
	if pipeline.is_valid():
		rd.free_rid(pipeline)
	if shader.is_valid():
		rd.free_rid(shader)

	shader = compile_shader(rd, SHADER_PATH)
	pipeline = rd.compute_pipeline_create(shader, create_specialization_constants())

	# Reset storage buffer upon recompilation
	_init_storage_buffer()


func _init_storage_buffer() -> void:
	if storage_buffer.is_valid():
		rd.free_rid(storage_buffer)

	var storage_init := PackedByteArray()
	# Each 32-bit float is 4 bytes
	storage_init.resize(SSBO_SIZE * 4)
	storage_buffer = rd.storage_buffer_create(storage_init.size(), storage_init)

	var uniform: RDUniform = create_uniform([storage_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER)
	uniform_set = rd.uniform_set_create([uniform], shader, 0)


## Import, compile and load shader
func compile_shader(p_rd: RenderingDevice, p_shader_path: String) -> RID:
	var shader_file: RDShaderFile = load(p_shader_path)
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()

	var err = shader_spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if err: push_warning(err)

	return p_rd.shader_create_from_spirv(shader_spirv)


func create_specialization_constants() -> Array[RDPipelineSpecializationConstant]:
	var constants_in: Array[RDPipelineSpecializationConstant] = []

	var constant := RDPipelineSpecializationConstant.new()
	constant.constant_id = 0
	constant.value = SPEC_CONSTANT_0
	constants_in.append(constant)

	constant = RDPipelineSpecializationConstant.new()
	constant.constant_id = 1
	constant.value = SPEC_CONSTANT_1
	constants_in.append(constant)

	return constants_in


func create_uniform(rids: Array[RID], type: RenderingDevice.UniformType, binding: int = 0) -> RDUniform:
	var uniform: RDUniform = RDUniform.new()
	uniform.uniform_type = type
	uniform.binding = binding
	for rid in rids:
		uniform.add_id(rid)
	return uniform


func compute(digit: int) -> void:
	var push_constant := PackedFloat32Array([digit, 0,0,0])
	#assert(push_constant.size() == INPUT_COUNT,
		#"Push constant passed in must strictly be of predetermined length %d" % INPUT_COUNT)

	rd.capture_timestamp("bench_start")
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), push_constant.size() * 4)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_dispatch(compute_list, 1, 1, 1)
	rd.compute_list_end()
	rd.capture_timestamp("bench_end")
	rd.submit()
	out()


func _get_benchmark() -> float:
	var start := rd.get_captured_timestamp_gpu_time(0)
	var end := rd.get_captured_timestamp_gpu_time(1)
	var gpu_ms := (end - start) * 1e-6
	return gpu_ms


func out() -> void:
	rd.sync()
	## Important this is after sync but before buffer_get_data
	benchmark = _get_benchmark()

	var bytes_out: PackedByteArray = rd.buffer_get_data(storage_buffer)

	# Bytes 0-4
	counter = bytes_out.decode_u32(0)

	# Bytes 4 through 8 become empty/padding

	# Bytes 8-16
	constants = Vector2(bytes_out.decode_float(8), bytes_out.decode_float(12))
	# Bytes 16 onwards
	storage_out = bytes_out.slice(16).to_float32_array()

	print_rich('Output: x%d | Vector2%s | [color=pale_green][b]%s[/b][/color]' % [
		counter, constants, storage_out
	])

	output.emit()
