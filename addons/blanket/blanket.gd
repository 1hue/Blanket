## Covers every mesh in a scene
##
## Drop this in once and it finds the meshes around it, adding a [BlanketInstance] to each one.
## To skip a mesh, add it to [member exclude_group] - or a parent node, to skip everything under it.
@icon("res://addons/blanket/assets/blanket.svg")
extends Node
class_name Blanket

## Off stops new insertions and broadcasts. Existing instances stay put
@export var enabled := true:
	set(value):
		enabled = value

		if enabled:
			cover_siblings()

@export_range(0, 3, 0.05, "or_greater") var depth := BlanketParams.DEFAULT_DEPTH:
	set(value):
		depth = value
		push_settings()

## How far a face may tilt from up and still get covered. 90 includes vertical walls
@export_range(0.0, 90.0, 1.0, "degrees") var max_slope_degrees := BlanketParams.DEFAULT_MAX_SLOPE_DEGREES:
	set(value):
		max_slope_degrees = value
		push_settings()

## Meshes in this group are skipped, as are those under a parent in it
@export var exclude_group: StringName = &"blanket_exclude"
@export var material: ShaderMaterial = BlanketInstance.DEFAULT_MATERIAL

@export_group("Debug", "debug")
@export var debug_enabled := true
@export_subgroup("Normals", "debug_normals")
@export var debug_normals_enabled := false
@export_range(0, 2, 0.01, "or_greater", "prefer_slider") var debug_normals_length := 0.2
@export var debug_normals_color := Color.ORANGE_RED


func _ready() -> void:
	cover_siblings()


## Idempotent - is_eligible skips anything already covered
func cover_siblings() -> void:
	if not enabled or not is_inside_tree():
		return

	var parent := get_parent()

	if parent == null:
		return

	for sibling in parent.get_children():
		if sibling != self:
			cover(sibling)

	push_settings()


func cover(node: Node) -> void:
	if node.is_in_group(exclude_group):
		return

	if node is MeshInstance3D and is_eligible(node):
		add_instance(node)

	for child in node.get_children():
		cover(child)


## A hand-placed instance keeps its own settings. Leave it be
func is_eligible(mesh_instance: MeshInstance3D) -> bool:
	if not BlanketInstance.is_supported(mesh_instance.mesh):
		return false

	for child in mesh_instance.get_children():
		if child is BlanketInstance:
			return false

	return true


## Settings land before add_child - in place by the time _ready bakes
func add_instance(mesh_instance: MeshInstance3D) -> void:
	var instance := BlanketInstance.new()

	instance.name = "BlanketInstance"
	instance.material = material
	instance.depth = depth
	instance.max_slope_degrees = max_slope_degrees
	instance.debug_enabled = debug_enabled
	instance.debug_normals_enabled = debug_normals_enabled
	instance.debug_normals_length = debug_normals_length
	instance.debug_normals_color = debug_normals_color

	mesh_instance.add_child(instance)


## The group spans the whole scene. Filter to what our parent owns - hand-placed instances included
func push_settings() -> void:
	if not enabled or not is_inside_tree():
		return

	var parent := get_parent()

	if parent == null:
		return

	for instance in get_tree().get_nodes_in_group(BlanketInstance.GROUP):
		if parent.is_ancestor_of(instance):
			instance.depth = depth
			instance.max_slope_degrees = max_slope_degrees


func change_depth(delta: int) -> void:
	depth = BlanketParams.DEFAULT_DEPTH if delta == 0 else depth + delta


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
