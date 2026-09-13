extends Node
class_name BlanketInstance

@export var material: Material = preload("res://assets/snow.tres")

@export_group("Debug", "debug")
@export var debug_enabled := false:
	set(value):
		debug_enabled = value
		draw_normals()
@export_subgroup("Normals", "debug_normals")
@export var debug_normals_enabled := false:
	set(value):
		debug_normals_enabled = value
		draw_normals()
@export_range(0, 2, 0.01, "or_greater", "prefer_slider") var debug_normals_length := 0.2:
	set(value):
		debug_normals_length = value
		draw_normals()
@export var debug_normals_color := Color.ORANGE_RED:
	set(value):
		debug_normals_color = value
		draw_normals()

@onready var mesh_instance: MeshInstance3D = $".."

var mesh: ArrayMesh:
	get: return mesh_instance.mesh if mesh_instance else null
var debug_normals_mesh: MeshInstance3D: set = set_debug_normals_mesh
var pipelines: Array[BlanketPipeline]


func _ready() -> void:
	setup()


## Re-entering the tree after _exit_tree tore everything down. On first entry
## _ready hasn't run yet, so mesh_instance is still null and _ready does it
func _enter_tree() -> void:
	if is_node_ready():
		setup()


## Dropping the pipelines frees their RIDs through the RefCounted destructors
func _exit_tree() -> void:
	if mesh and mesh.changed.is_connected(on_mesh_changed):
		mesh.changed.disconnect(on_mesh_changed)

	debug_normals_mesh = null
	pipelines.clear()


func setup() -> void:
	convert_to_storage_buffer_mesh()
	validate()

	mesh.changed.connect(on_mesh_changed)

	for i in mesh.get_surface_count():
		pipelines.append(BlanketPipeline.new(mesh, i, mesh_instance.global_transform))

	for pipeline in pipelines:
		pipeline.bake()

	draw_normals()


func on_mesh_changed() -> void:
	if material:
		for pipeline in pipelines:
			if pipeline.surface.idx > -1:
				mesh_instance.set_surface_override_material(pipeline.surface.idx, material)

	draw_normals()


func set_debug_normals_mesh(value: MeshInstance3D) -> void:
	if debug_normals_mesh:
		remove_child(debug_normals_mesh)
		debug_normals_mesh.queue_free()

	debug_normals_mesh = value

	if debug_normals_mesh:
		add_child(debug_normals_mesh)


func draw_normals() -> void:
	# Bootleg compute sync
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	# Awaited, so the node may have left the tree in the meantime
	if not is_inside_tree() or not is_node_ready():
		return

	debug_normals_mesh = null

	if not debug_enabled or not debug_normals_enabled:
		return

	debug_normals_mesh = build_normal_lines(mesh_instance.global_transform, debug_normals_length)


## Every computed surface goes into one mesh - surface.idx is where each landed
func build_normal_lines(transform: Transform3D, length := 0.2) -> MeshInstance3D:
	var im := ImmediateMesh.new()
	var normals_material := ORMMaterial3D.new()
	normals_material.vertex_color_use_as_albedo = true
	normals_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	normals_material.no_depth_test = true
	normals_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	im.surface_begin(Mesh.PRIMITIVE_LINES, normals_material)

	for pipeline in pipelines:
		var idx := pipeline.surface.idx

		if idx < 0 or idx >= mesh.get_surface_count():
			continue

		var arrays := mesh.surface_get_arrays(idx)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]

		for i in vertices.size():
			var world_pos := transform * vertices[i]
			var world_normal := (transform.basis * normals[i]).normalized()

			im.surface_set_color(debug_normals_color)
			im.surface_add_vertex(world_pos)
			im.surface_add_vertex(world_pos + world_normal * length)

	im.surface_end()

	var mi := MeshInstance3D.new()
	mi.mesh = im
	return mi


func validate() -> void:
	assert(mesh is ArrayMesh,
		"Must be an ArrayMesh - primitives like BoxMesh cannot have the STORAGE_BUFFER flag")
	var format := mesh.surface_get_format(0)
	var uses_storage_buffer := (format & Mesh.ARRAY_FLAG_USE_STORAGE_BUFFER) != 0
	assert(uses_storage_buffer, "Mesh must have the STORAGE_BUFFER flag")


func change_depth(delta: int) -> void:
	for pipeline in pipelines:
		if delta == 0:
			pipeline.params.depth = BlanketParams.DEFAULT_DEPTH
		else:
			pipeline.params.depth += delta

		pipeline.update()

	draw_normals()


func _unhandled_key_input(event: InputEvent) -> void:
	if not debug_enabled:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_EQUAL or event.keycode == KEY_KP_ADD:
			change_depth(1)
		elif event.keycode == KEY_MINUS or event.keycode == KEY_KP_SUBTRACT:
			change_depth(-1)
		elif event.keycode == KEY_BACKSPACE:
			change_depth(0)


func _unhandled_input(event: InputEvent) -> void:
	if not debug_enabled:
		return

	if event is InputEventMouseButton and event.pressed and event.shift_pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			change_depth(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			change_depth(-1)


## Already converted on re-entry, and rebuilding would drop the computed surfaces
func convert_to_storage_buffer_mesh() -> void:
	var source_mesh := mesh

	if source_mesh.get_surface_count() > 0  and source_mesh.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_STORAGE_BUFFER:
		return

	var new_mesh := ArrayMesh.new()

	for i in source_mesh.get_surface_count():
		var arrays := source_mesh.surface_get_arrays(i)

		new_mesh.add_surface_from_arrays(
			source_mesh.surface_get_primitive_type(i),
			arrays,
			[],
			{},
			Mesh.ARRAY_FLAG_USE_STORAGE_BUFFER
		)

		var source_material := source_mesh.surface_get_material(i)

		if source_material != null:
			new_mesh.surface_set_material(i, source_material)

	mesh_instance.mesh = new_mesh
