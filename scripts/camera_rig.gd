class_name CameraRig
extends Node3D

@export var rotate_speed: float = 0.01
@export var min_pitch: float = deg_to_rad(-89.0)
@export var max_pitch: float = deg_to_rad(89.0)

@export var zoom_speed: float = 0.5
@export var min_distance: float = 2.0
@export var max_distance: float = 30.0

@onready var camera: Camera3D = $Camera3D

var yaw: float = 0.0
var pitch: float = 0.0
var dragging: bool = false
var distance: float = 0.0


func _ready() -> void:
	distance = camera.position.length()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		dragging = event.pressed
		get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and dragging:
		yaw -= event.relative.x * rotate_speed
		pitch -= event.relative.y * rotate_speed
		pitch = clamp(pitch, min_pitch, max_pitch)
		update_rotation()
		get_viewport().set_input_as_handled()

	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom(-zoom_speed)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom(zoom_speed)
			get_viewport().set_input_as_handled()


func update_rotation() -> void:
	rotation = Vector3(pitch, yaw, 0.0)


func zoom(delta: float) -> void:
	distance = clamp(distance + delta, min_distance, max_distance)
	var direction := camera.position.normalized()
	camera.position = direction * distance
