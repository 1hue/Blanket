extends Node
class_name SurfaceCover

## The computed surface is added after the source, so it's always index 1
const COMPUTED_SURFACE_IDX = 1

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
var debug_normals_mesh: MeshInstance3D: set = _set_debug_normals_mesh
var computes: Array[Compute]


func _ready() -> void:
	_setup()


## Re-entering the tree after _exit_tree tore everything down. On first entry
## _ready hasn't run yet, so mesh_instance is still null and _ready does it
func _enter_tree() -> void:
	if is_node_ready():
		_setup()


## Dropping the computes frees their RIDs through the RefCounted destructors
func _exit_tree() -> void:
	if mesh and mesh.changed.is_connected(_on_mesh_changed):
		mesh.changed.disconnect(_on_mesh_changed)

	debug_normals_mesh = null
	computes.clear()


func _setup() -> void:
	convert_to_storage_buffer_mesh()
	validate()

	mesh.changed.connect(_on_mesh_changed)

	for i in mesh.get_surface_count():
		var compute := Compute.new(mesh, i, mesh_instance.global_transform)

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


func _set_debug_normals_mesh(value: MeshInstance3D) -> void:
	if debug_normals_mesh:
		remove_child(debug_normals_mesh)
		debug_normals_mesh.queue_free()

	debug_normals_mesh = value

	if debug_normals_mesh:
		add_child(debug_normals_mesh)


func draw_normals(surface_idx := COMPUTED_SURFACE_IDX) -> void:
	# Bootleg compute sync
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	# Awaited, so the node may have left the tree in the meantime
	if not is_inside_tree() or not is_node_ready():
		return

	debug_normals_mesh = null

	if not debug_enabled or not debug_normals_enabled or surface_idx >= mesh.get_surface_count():
		return

	var arrays := mesh.surface_get_arrays(surface_idx)

	debug_normals_mesh = build_normal_lines(
		arrays[Mesh.ARRAY_VERTEX],
		arrays[Mesh.ARRAY_NORMAL],
		mesh_instance.global_transform,
		debug_normals_length
	)


func build_normal_lines(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	transform: Transform3D,
	length := 0.2
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


func change_depth(delta: int) -> void:
	for compute in computes:
		if delta == 0:
			compute.params.depth = ComputeParams.DEFAULT_DEPTH
		else:
			compute.params.depth += delta

		compute.update()

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
