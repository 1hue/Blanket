extends RefCounted

const SHADER_PATHS: Array[String] = [
	"res://shaders/count.glsl",
	"res://shaders/edges.glsl",
	"res://shaders/positions.glsl"
]

var rd: RenderingDevice
var shaders: Array[RID]
var pipelines: Array[RID]


func _init() -> void:
	rd = RenderingServer.get_rendering_device()
	shaders = [
		compile_shader(rd, SHADER_PATHS[0]),
		compile_shader(rd, SHADER_PATHS[1]),
		compile_shader(rd, SHADER_PATHS[2]),
	]
	pipelines = [
		rd.compute_pipeline_create(shaders[0]),
		rd.compute_pipeline_create(shaders[1]),
		rd.compute_pipeline_create(shaders[2]),
	]


func _notification(what) -> void:
	if what == NOTIFICATION_PREDELETE:
		for shader in shaders:
			if shader.is_valid():
				rd.free_rid(shader)


func compile_shader(p_rd: RenderingDevice, p_shader_path: String) -> RID:
	var shader_file: RDShaderFile = load(p_shader_path)
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()

	var err = shader_spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if err: push_warning(err)

	return p_rd.shader_create_from_spirv(shader_spirv)
