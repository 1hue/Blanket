extends RefCounted
class_name ComputeParams

signal changed

const SIZE_COUNT = 16
const SIZE_POSITION = 28
const DEFAULT_DEPTH = 0.1

## World up translated to model local space
var local_up := Vector3.UP:
	set(value):
		local_up = value
		changed.emit()

## Distance to extrude
var depth := DEFAULT_DEPTH:
	set(value):
		depth = value
		changed.emit()

## Only horizontal surfaces (mesh faces) are eligible. 90deg to include verticals.
var max_slope_degrees := 45.0:
	set(value):
		max_slope_degrees = value
		changed.emit()

var source_index_count: int
var source_index_stride: int
var source_vertex_count: int
var source_vertex_stride: int
var source_normal_offset: int
var source_normal_stride: int
var source_colors_offset: int
var source_attribute_stride: int
var target_vertex_count: int
var target_vertex_stride: int


## 1st pass
func pack_faces() -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(SIZE_COUNT)
	bytes.encode_float(0, local_up.x)
	bytes.encode_float(4, local_up.y)
	bytes.encode_float(8, local_up.z)
	bytes.encode_float(12, max_slope_degrees)
	bytes.encode_u32(16, source_vertex_count)
	bytes.encode_u32(20, source_index_count)
	bytes.encode_u32(24, source_index_stride)
	bytes.encode_u32(28, source_normal_offset)
	bytes.encode_u32(32, source_normal_stride)
	bytes.encode_u32(36, source_colors_offset)
	bytes.encode_u32(40, source_attribute_stride)
	return bytes


## 4th pass
func pack_positions() -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(SIZE_POSITION)
	bytes.encode_float(0, local_up.x)
	bytes.encode_float(4, local_up.y)
	bytes.encode_float(8, local_up.z)
	bytes.encode_float(12, depth)
	bytes.encode_u32(16, source_vertex_count)
	bytes.encode_u32(20, source_vertex_stride)
	bytes.encode_u32(24, target_vertex_stride)
	return bytes
