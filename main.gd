extends Node3D

var worker: ComputeWorker

@onready var debug: Label3D = $Label3D


func _ready() -> void:
	worker = ComputeWorker.new()
	worker.output.connect(_on_output)
	worker.compute(10)


func _on_output() -> void:
	debug.text = "%s" % worker.storage_out


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var digit := -1

		if event.keycode >= KEY_0 and event.keycode <= KEY_9:
			digit = event.keycode - KEY_0
		elif event.keycode >= KEY_KP_0 and event.keycode <= KEY_KP_9:
			digit = event.keycode - KEY_KP_0

		if digit != -1:
			worker.compute(digit)
			get_viewport().set_input_as_handled()
