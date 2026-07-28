extends RefCounted
class_name ParamsCompact

signal changed

const OFFSET_LOCAL_UP := 0
const OFFSET_SHIFT_AMOUNT := 12
const OFFSET_VERTEX_COUNT := 16
const OFFSET_SOURCE_VERTEX_STRIDE := 20
const OFFSET_TARGET_VERTEX_STRIDE := 24
const TOTAL_SIZE := 28

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

var shift_amount: float:
	get: return bytes.decode_float(OFFSET_SHIFT_AMOUNT)
	set(value):
		bytes.encode_float(OFFSET_SHIFT_AMOUNT, value)
		changed.emit()

var vertex_count: int:
	get: return bytes.decode_u32(OFFSET_VERTEX_COUNT)
	set(value):
		bytes.encode_u32(OFFSET_VERTEX_COUNT, value)
		changed.emit()

var source_vertex_stride: int:
	get: return bytes.decode_u32(OFFSET_SOURCE_VERTEX_STRIDE)
	set(value):
		bytes.encode_u32(OFFSET_SOURCE_VERTEX_STRIDE, value)
		changed.emit()

var target_vertex_stride: int:
	get: return bytes.decode_u32(OFFSET_TARGET_VERTEX_STRIDE)
	set(value):
		bytes.encode_u32(OFFSET_TARGET_VERTEX_STRIDE, value)
		changed.emit()


func _init() -> void:
	bytes.resize(TOTAL_SIZE)
	local_up = Vector3.UP
	shift_amount = 1.0
