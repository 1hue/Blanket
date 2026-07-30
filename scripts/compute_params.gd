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

var vertex_stride: int
var index_count: int
var vertex_count: int
var index_stride: int
var normals_offset: int
var normal_tangent_stride: int
var colors_offset: int
var attribute_stride: int
var target_vertex_stride: int


## 1st pass
func pack_count() -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(SIZE_COUNT)
	bytes.encode_float(0, local_up.x)
	bytes.encode_float(4, local_up.y)
	bytes.encode_float(8, local_up.z)
	bytes.encode_float(12, max_slope_degrees)
	return bytes


## 4th pass
func pack_positions() -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(SIZE_POSITION)
	bytes.encode_float(0, local_up.x)
	bytes.encode_float(4, local_up.y)
	bytes.encode_float(8, local_up.z)
	bytes.encode_float(12, depth)
	bytes.encode_u32(16, vertex_count)
	bytes.encode_u32(20, vertex_stride)
	bytes.encode_u32(24, target_vertex_stride)
	return bytes
