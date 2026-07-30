extends Node
class_name MeshCover

@export var material: StandardMaterial3D = preload("res://assets/snow.tres")

@onready var debug: Label3D = $Label3D

var workers: Array[ComputeWorker]


func _ready() -> void:
	var mesh_instance: MeshInstance3D = get_parent()
	convert_to_storage_buffer_mesh(mesh_instance)
	validate(mesh_instance)

	for i in mesh_instance.mesh.get_surface_count():
		var worker := ComputeWorker.new(mesh_instance.mesh, i, mesh_instance.global_transform)
		worker.output.connect(_on_output)
		worker.bake()
		mesh_instance.set_surface_override_material(worker.owned_surface, material)
		workers.append(worker)


func validate(mesh_instance: MeshInstance3D) -> void:
	# Must be an ArrayMesh - primitives like BoxMesh cannot have the STORAGE_BUFFER flag
	var array_mesh: ArrayMesh = mesh_instance.mesh
	var format := array_mesh.surface_get_format(0)
	var uses_storage_buffer := (format & Mesh.ARRAY_FLAG_USE_STORAGE_BUFFER) != 0
	assert(uses_storage_buffer, "Mesh must have the STORAGE_BUFFER flag")


func _on_output(message: String) -> void:
	debug.text = message


func change_depth(delta: int) -> void:
	for worker in workers:
		if delta == 0:
			worker.params.depth = worker.params.DEFAULT_DEPTH
		else:
			worker.params.depth += delta


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


func convert_to_storage_buffer_mesh(mesh_instance: MeshInstance3D) -> void:
	var source_mesh := mesh_instance.mesh as ArrayMesh
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
