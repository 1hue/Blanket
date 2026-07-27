extends Node3D

var worker: ComputeWorker
var vertex_count: int

@onready var debug: Label3D = $Label3D
# Make sure this uses an ArrayMesh - primitives like BoxMesh cannot have the STORAGE_BUFFER flag
@onready var mesh_instance_3d: MeshInstance3D = $MeshInstance3D


func _ready() -> void:
	convert_to_storage_buffer_mesh(mesh_instance_3d)

	var array_mesh: ArrayMesh = mesh_instance_3d.mesh
	var format := array_mesh.surface_get_format(0)
	var uses_storage_buffer := (format & Mesh.ARRAY_FLAG_USE_STORAGE_BUFFER) != 0
	assert(uses_storage_buffer, "Mesh must have the STORAGE_BUFFER flag")

	vertex_count = array_mesh.surface_get_array_len(0)
	prints("vertex_count", vertex_count)

	worker = ComputeWorker.new()
	worker.output.connect(_on_output)
	worker.set_mesh(mesh_instance_3d.mesh.get_rid())
	worker.compute(vertex_count, 0)


func _on_output() -> void:
	debug.text = worker.storage_out


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var digit := -1

		if event.keycode >= KEY_0 and event.keycode <= KEY_9:
			digit = event.keycode - KEY_0
		elif event.keycode >= KEY_KP_0 and event.keycode <= KEY_KP_9:
			digit = event.keycode - KEY_KP_0

		if digit != -1:
			worker.compute(vertex_count, digit)
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
		var material := source_mesh.surface_get_material(i)
		if material != null:
			new_mesh.surface_set_material(i, material)

	mesh_instance.mesh = new_mesh
