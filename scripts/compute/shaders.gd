extends Node

class BlanketShader:
	var versions: Array[StringName]
	## Empty string in case of non-versioned shaders
	var shaders: Dictionary[StringName, RID]
	## Empty string in case of non-versioned shaders
	var pipelines: Dictionary[StringName, RID]
	var rd: RenderingDevice


	func _init(path: String, specialization_constants := []) -> void:
		rd = RenderingServer.get_rendering_device()

		var shader_file: RDShaderFile = load(path)
		var spec_constants := BlanketUtil.create_spec_constants(specialization_constants)

		versions = shader_file.get_version_list()

		for version in versions:
			var rid := compile_shader(shader_file, version)

			shaders[version] = rid
			pipelines[version] = rd.compute_pipeline_create(rid, spec_constants)

	func compile_shader(shader_file: RDShaderFile, version: StringName) -> RID:
		var shader_spirv: RDShaderSPIRV = shader_file.get_spirv(version)
		var err = shader_spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
		if err: push_error(err)

		return rd.shader_create_from_spirv(shader_spirv)

	func _notification(what) -> void:
		if what == NOTIFICATION_PREDELETE:
			for rid in shaders.values():
				if rid.is_valid():
					rd.free_rid(rid)


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
	select = BlanketShader.new(
		"res://scripts/passes/faces/select.glsl",
		[SelectPass.WORKGROUP_SIZE, DedupePass.WORKGROUP_SIZE]
	)
	dedupe = BlanketShader.new(
		"res://scripts/passes/faces/dedupe.glsl",
		[DedupePass.WORKGROUP_SIZE, FacesPass.WORKGROUP_SIZE]
	)
	faces = BlanketShader.new(
		"res://scripts/passes/faces/faces.glsl",
		[FacesPass.WORKGROUP_SIZE]
	)
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
