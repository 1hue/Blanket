extends Node3D

@onready var blanket: Blanket = get_node_or_null("Blanket")
@onready var camera_rig: CameraRig = get_node_or_null("CameraRig")

var mesh_instances: Array[MeshInstance3D]
var focus_index := -1


func _unhandled_key_input(event: InputEvent) -> void:
	if event is not InputEventKey or not event.pressed or event.echo:
		return

	if event.keycode == KEY_N:
		focus_next_mesh()
		return

	if not blanket:
		return

	if event.keycode == KEY_EQUAL or event.keycode == KEY_KP_ADD:
		blanket.change_depth(1)
	elif event.keycode == KEY_MINUS or event.keycode == KEY_KP_SUBTRACT:
		blanket.change_depth(-1)
	elif event.keycode == KEY_BACKSPACE:
		blanket.change_depth(0)


func _unhandled_input(event: InputEvent) -> void:
	if not blanket:
		return

	if event is InputEventMouseButton and event.pressed and event.shift_pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			blanket.change_depth(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			blanket.change_depth(-1)


## Gathered on first use - the scene doesn't change under us
func focus_next_mesh() -> void:
	if camera_rig == null:
		return

	if mesh_instances.is_empty():
		collect_meshes(self)

	if mesh_instances.is_empty():
		return

	focus_index = (focus_index + 1) % mesh_instances.size()
	camera_rig.global_position = mesh_instances[focus_index].global_position


func collect_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		mesh_instances.append(node)

	for child in node.get_children():
		collect_meshes(child)
