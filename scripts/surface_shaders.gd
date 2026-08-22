extends Node

class ShaderPipeline:
	var shader: RID
	var pipeline: RID
	var rd: RenderingDevice

	func _init(path: String) -> void:
		rd = RenderingServer.get_rendering_device()
		shader = compile_shader(path)
		pipeline = rd.compute_pipeline_create(shader)

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

var select_faces: ShaderPipeline
var select_edges: ShaderPipeline
var dedupe: ShaderPipeline
var verts: ShaderPipeline
var shape: ShaderPipeline
var bevel_shrink: ShaderPipeline
var bevel_fill: ShaderPipeline
var normals_sum: ShaderPipeline
var normals: ShaderPipeline


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F5:
		_notification(NOTIFICATION_PREDELETE)
		_init()


func _init() -> void:
	select_faces = ShaderPipeline.new("res://scripts/passes/select/faces.glsl")
	select_edges = ShaderPipeline.new("res://scripts/passes/select/edges.glsl")
	dedupe = ShaderPipeline.new("res://scripts/passes/dedupe.glsl")
	verts = ShaderPipeline.new("res://scripts/passes/verts.glsl")
	shape = ShaderPipeline.new("res://scripts/passes/shape.glsl")
	bevel_shrink = ShaderPipeline.new("res://scripts/passes/bevel/shrink.glsl")
	bevel_fill = ShaderPipeline.new("res://scripts/passes/bevel/fill.glsl")
	normals_sum = ShaderPipeline.new("res://scripts/passes/normals/sum.glsl")
	normals = ShaderPipeline.new("res://scripts/passes/normals/normals.glsl")
