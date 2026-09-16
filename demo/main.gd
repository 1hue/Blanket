extends Node3D

@onready var blanket: Blanket = $Blanket


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_EQUAL or event.keycode == KEY_KP_ADD:
			blanket.change_depth(1)
		elif event.keycode == KEY_MINUS or event.keycode == KEY_KP_SUBTRACT:
			blanket.change_depth(-1)
		elif event.keycode == KEY_BACKSPACE:
			blanket.change_depth(0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.shift_pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			blanket.change_depth(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			blanket.change_depth(-1)
