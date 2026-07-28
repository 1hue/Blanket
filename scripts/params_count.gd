extends RefCounted
class_name ParamsCount

signal changed

const OFFSET_LOCAL_UP := 0
const OFFSET_UP_THRESHOLD_DEGREES := 12
const TOTAL_SIZE := 16

var bytes := PackedByteArray()

var local_up: Vector3:
	get:
		return Vector3(
			bytes.decode_float(OFFSET_LOCAL_UP),
			bytes.decode_float(OFFSET_LOCAL_UP + 4),
			bytes.decode_float(OFFSET_LOCAL_UP + 8)
		)
	set(value):
		bytes.encode_float(OFFSET_LOCAL_UP, value.x)
		bytes.encode_float(OFFSET_LOCAL_UP + 4, value.y)
		bytes.encode_float(OFFSET_LOCAL_UP + 8, value.z)
		changed.emit()

var up_threshold_degrees: float:
	get: return bytes.decode_float(OFFSET_UP_THRESHOLD_DEGREES)
	set(value):
		bytes.encode_float(OFFSET_UP_THRESHOLD_DEGREES, value)
		changed.emit()


func _init() -> void:
	bytes.resize(TOTAL_SIZE)
	up_threshold_degrees = 45
	local_up = Vector3.UP
