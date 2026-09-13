## Scene-wide dispatcher
##
## Walks the tree once at [code]_ready[/code] and inserts a [BlanketInstance] under every eligible [MeshInstance3D].
extends Node
class_name Blanket

## Meshes in this group are skipped, as are those under a parent in it
@export var exclude_group: StringName = &"blanket_exclude"
@export var material: Material = preload("res://assets/snow.tres")
@export var depth := BlanketParams.DEFAULT_DEPTH:
	set(value):
		depth = value
		push_depth()

@export_group("Debug", "debug")
@export var debug_enabled := true
@export_subgroup("Normals", "debug_normals")
@export var debug_normals_enabled := false
@export_range(0, 2, 0.01, "or_greater", "prefer_slider") var debug_normals_length := 0.2
@export var debug_normals_color := Color.ORANGE_RED


func _ready() -> void:
	var parent := get_parent()

	if parent == null:
		return

	for sibling in parent.get_children():
		if sibling != self:
			cover(sibling)

	push_depth()


## Excluded tree branches are skipped whole - any parent can exclude everything it owns
func cover(node: Node) -> void:
	if node.is_in_group(exclude_group):
		return

	if node is MeshInstance3D and is_eligible(node):
		add_instance(node)

	for child in node.get_children():
		cover(child)


## A manually placed instance is left alone, config and all
func is_eligible(mesh_instance: MeshInstance3D) -> bool:
	if mesh_instance.mesh == null:
		return false

	for child in mesh_instance.get_children():
		if child is BlanketInstance:
			return false

	return true


## Exports are applied before add_child, so they land before _ready bakes
func add_instance(mesh_instance: MeshInstance3D) -> void:
	var instance := BlanketInstance.new()

	instance.name = "BlanketInstance"
	instance.material = material
	instance.depth = depth
	instance.debug_enabled = debug_enabled
	instance.debug_normals_enabled = debug_normals_enabled
	instance.debug_normals_length = debug_normals_length
	instance.debug_normals_color = debug_normals_color

	mesh_instance.add_child(instance)


## The group spans the whole scene, so filter to what our parent owns - this
## also picks up manually placed instances, which never went through add_instance
func push_depth() -> void:
	if not is_inside_tree():
		return

	var parent := get_parent()

	if parent == null:
		return

	for instance in get_tree().get_nodes_in_group(BlanketInstance.GROUP):
		if parent.is_ancestor_of(instance):
			instance.depth = depth


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
