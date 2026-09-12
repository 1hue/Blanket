extends Node
class_name SurfaceCover

@export var material: Material = preload("res://assets/snow.tres")
@export var debug: Label3D

@export_group("Debug", "debug")
@export_subgroup("Normals", "debug_normals")
@export var debug_normals := false:
	set(value):
		debug_normals = value
		draw_normals()
@export_range(0, 2, 0.01, "or_greater", "prefer_slider") var debug_normals_length := 0.2:
	set(value):
		debug_normals_length = value
		draw_normals()
@export var debug_normals_color := Color.RED:
	set(value):
		debug_normals_color = value
		draw_normals()

@onready var mesh_instance: MeshInstance3D = $".."

var mesh: ArrayMesh:
	get: return mesh_instance.mesh
var debug_normals_mesh: MeshInstance3D: set = _set_debug_normals_mesh
var computes: Array[Compute]


func _ready() -> void:
	convert_to_storage_buffer_mesh()
	validate()

	mesh.changed.connect(_on_mesh_changed)

	for i in mesh.get_surface_count():
		var compute := Compute.new(mesh, i, mesh_instance.global_transform)

		compute.output.connect(_on_output)
		computes.append(compute)

	for compute in computes:
		compute.bake()

	draw_normals()


func _on_mesh_changed() -> void:
	if material:
		for compute in computes:
			if compute.surface.idx > -1:
				mesh_instance.set_surface_override_material(compute.surface.idx, material)

	draw_normals()


func _exit_tree() -> void:
	computes.clear()


func _set_debug_normals_mesh(value: MeshInstance3D) -> void:
	if debug_normals_mesh: # Clear previous mesh
		remove_child(debug_normals_mesh)
		debug_normals_mesh.queue_free()

	debug_normals_mesh = value

	if debug_normals_mesh:
		add_child(debug_normals_mesh)


func draw_normals(surface_idx: int = 1) -> void:
	# Bootleg compute sync
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	debug_normals_mesh = null

	if not debug_normals or not mesh_instance or not is_node_ready():
		return

	var arrays := mesh.surface_get_arrays(surface_idx)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]

	debug_normals_mesh = draw_normal_debug(vertices, normals, mesh_instance.global_transform, debug_normals_length)


func draw_normal_debug(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	transform: Transform3D,
	length: float = 0.2
) -> MeshInstance3D:
	var im := ImmediateMesh.new()
	var normals_material := ORMMaterial3D.new()
	normals_material.vertex_color_use_as_albedo = true
	normals_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	normals_material.no_depth_test = true
	normals_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	im.surface_begin(Mesh.PRIMITIVE_LINES, normals_material)
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


func _on_output(message: String) -> void:
	if debug:
		debug.text = message


func change_depth(delta: int) -> void:
	for compute in computes:
		if delta == 0:
			compute.params.depth = ComputeParams.DEFAULT_DEPTH
		else:
			compute.params.depth += delta

		compute.update()

	draw_normals()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_EQUAL or event.keycode == KEY_KP_ADD:
			change_depth(1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_MINUS or event.keycode == KEY_KP_SUBTRACT:
			change_depth(-1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_BACKSPACE:
			change_depth(0)
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.shift_pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			change_depth(1)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			change_depth(-1)
			get_viewport().set_input_as_handled()


func convert_to_storage_buffer_mesh() -> void:
	var source_mesh := mesh
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
