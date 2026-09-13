extends Node

class ShaderPipeline:
	var shader: RID
	var pipeline: RID
	var rd: RenderingDevice

	func _init(path: String, specialization_constants := []) -> void:
		rd = RenderingServer.get_rendering_device()
		shader = compile_shader(path)
		pipeline = rd.compute_pipeline_create(shader, ComputeUtil.create_spec_constants(specialization_constants))

	func compile_shader(p_shader_path: String) -> RID:
		var shader_file: RDShaderFile = load(p_shader_path)
		var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()

		var err = shader_spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
		if err: push_error(err)
		return rd.shader_create_from_spirv(shader_spirv)

	func _notification(what) -> void:
		if what == NOTIFICATION_PREDELETE:
			if shader.is_valid():
				rd.free_rid(shader)

var rd: RenderingDevice
var shaders: Array[RID]
var pipelines: Array[RID]

var faces_select: ShaderPipeline
var faces_dedupe: ShaderPipeline
var faces_write: ShaderPipeline
var shared_edges: ShaderPipeline
var out_mesh: ShaderPipeline
var bevel_shrink: ShaderPipeline
var bevel_fill: ShaderPipeline
var boundary_resolve: ShaderPipeline
var boundary_write: ShaderPipeline
var offset: ShaderPipeline
var normals_sum: ShaderPipeline
var normals_write: ShaderPipeline
var smooth_sum: ShaderPipeline
var smooth_write: ShaderPipeline


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F5:
		_notification(NOTIFICATION_PREDELETE)
		_init()


func _init() -> void:
	faces_select = ShaderPipeline.new("res://scripts/passes/faces/faces_select.glsl")
	faces_dedupe = ShaderPipeline.new("res://scripts/passes/faces/faces_dedupe.glsl")
	faces_write = ShaderPipeline.new("res://scripts/passes/faces/faces_write.glsl")
	shared_edges = ShaderPipeline.new("res://scripts/passes/shared_edges.glsl")
	out_mesh = ShaderPipeline.new("res://scripts/passes/out_mesh.glsl")
	bevel_shrink = ShaderPipeline.new(
		"res://scripts/passes/bevel/bevel_shrink.glsl",
		[ComputeParams.BEVEL_WIDTH]
	)
	bevel_fill = ShaderPipeline.new(
		"res://scripts/passes/bevel/bevel_fill.glsl",
		[ComputeParams.BEVEL_SEGMENTS, ComputeParams.BEVEL_ARCS]
	)
	boundary_resolve = ShaderPipeline.new(
		"res://scripts/passes/boundary/boundary_resolve.glsl",
		[ComputeParams.BEVEL_SEGMENTS, ComputeParams.BEVEL_ARCS]
	)
	boundary_write = ShaderPipeline.new(
		"res://scripts/passes/boundary/boundary_write.glsl",
		[ComputeParams.WALL_SEGMENTS, ComputeParams.BEVEL_ARCS]
	)
	offset = ShaderPipeline.new("res://scripts/passes/offset.glsl")
	normals_sum = ShaderPipeline.new("res://scripts/passes/normals/normals_sum.glsl")
	normals_write = ShaderPipeline.new("res://scripts/passes/normals/normals_write.glsl")
	smooth_sum = ShaderPipeline.new("res://scripts/passes/smooth/smooth_sum.glsl")
	smooth_write = ShaderPipeline.new("res://scripts/passes/smooth/smooth_write.glsl")
