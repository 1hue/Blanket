extends Node3D

const HIGHLIGHT_MATERIAL: StandardMaterial3D = preload("res://assets/highlight.tres")

var worker: ComputeWorker

@onready var debug: Label3D = $Label3D
# Make sure this uses an ArrayMesh - primitives like BoxMesh cannot have the STORAGE_BUFFER flag
#@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var mesh_instance: MeshInstance3D = $cube/Cube


func _ready() -> void:
	convert_to_storage_buffer_mesh(mesh_instance)

	var array_mesh: ArrayMesh = mesh_instance.mesh
	var format := array_mesh.surface_get_format(0)
	var uses_storage_buffer := (format & Mesh.ARRAY_FLAG_USE_STORAGE_BUFFER) != 0
	assert(uses_storage_buffer, "Mesh must have the STORAGE_BUFFER flag")

	worker = ComputeWorker.new(mesh_instance.mesh, mesh_instance.global_transform)
	worker.output.connect(_on_output)
	worker.compute()
	mesh_instance.set_surface_override_material(worker.owned_surface, HIGHLIGHT_MATERIAL)


func _on_output(message: String) -> void:
	debug.text = message


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_EQUAL or event.keycode == KEY_KP_ADD:
			worker.params.shift_amount += 1
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_MINUS or event.keycode == KEY_KP_SUBTRACT:
			worker.params.shift_amount -= 1
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_BACKSPACE:
			worker.params.shift_amount = 0
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.shift_pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			worker.params.shift_amount += 1
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			worker.params.shift_amount -= 1
			get_viewport().set_input_as_handled()


func convert_to_storage_buffer_mesh(p_mesh_instance: MeshInstance3D) -> void:
	var source_mesh := p_mesh_instance.mesh as ArrayMesh
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
		var material := source_mesh.surface_get_material(i)
		if material != null:
			new_mesh.surface_set_material(i, material)

	mesh_instance.mesh = new_mesh
