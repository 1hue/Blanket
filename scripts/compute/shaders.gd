extends Node

class BlanketShader:
	var shader: RID
	var pipeline: RID
	var rd: RenderingDevice

	func _init(path: String, specialization_constants := []) -> void:
		rd = RenderingServer.get_rendering_device()
		shader = compile_shader(path)
		pipeline = rd.compute_pipeline_create(shader, BlanketUtil.create_spec_constants(specialization_constants))

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

var select: BlanketShader
var dedupe: BlanketShader
var faces: BlanketShader
var edges: BlanketShader
var out_mesh: BlanketShader
var shrink: BlanketShader
var fill: BlanketShader
var boundary_resolve: BlanketShader
var boundary_write: BlanketShader
var offset: BlanketShader
var normals_sum: BlanketShader
var normals_write: BlanketShader
var smooth_sum: BlanketShader
var smooth_write: BlanketShader


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F5:
		_notification(NOTIFICATION_PREDELETE)
		_init()


func _init() -> void:
	select = BlanketShader.new("res://scripts/passes/faces/select.glsl")
	dedupe = BlanketShader.new("res://scripts/passes/faces/dedupe.glsl")
	faces = BlanketShader.new("res://scripts/passes/faces/faces.glsl")
	edges = BlanketShader.new("res://scripts/passes/edges.glsl")
	out_mesh = BlanketShader.new("res://scripts/passes/out_mesh.glsl")
	shrink = BlanketShader.new(
		"res://scripts/passes/bevel/shrink.glsl",
		[BlanketParams.BEVEL_WIDTH]
	)
	fill = BlanketShader.new(
		"res://scripts/passes/bevel/fill.glsl",
		[BlanketParams.BEVEL_SEGMENTS, BlanketParams.BEVEL_ARCS]
	)
	boundary_resolve = BlanketShader.new(
		"res://scripts/passes/boundary/boundary_resolve.glsl",
		[BlanketParams.BEVEL_SEGMENTS, BlanketParams.BEVEL_ARCS]
	)
	boundary_write = BlanketShader.new(
		"res://scripts/passes/boundary/boundary_write.glsl",
		[BlanketParams.WALL_SEGMENTS, BlanketParams.BEVEL_ARCS]
	)
	offset = BlanketShader.new("res://scripts/passes/offset.glsl")
	normals_sum = BlanketShader.new("res://scripts/passes/normals/normals_sum.glsl")
	normals_write = BlanketShader.new("res://scripts/passes/normals/normals_write.glsl")
	smooth_sum = BlanketShader.new("res://scripts/passes/smooth/smooth_sum.glsl")
	smooth_write = BlanketShader.new("res://scripts/passes/smooth/smooth_write.glsl")
