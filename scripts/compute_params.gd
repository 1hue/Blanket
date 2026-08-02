extends RefCounted
class_name ComputeParams

signal changed

const SIZE_FACES = 44
const SIZE_VERTS = 44
const SIZE_SHAPE = 36
const DEFAULT_DEPTH = 0.1
const DEFAULT_MAX_SLOPE_DEGREES = 45.0

## World up translated to model local space, normalized
var local_up := Vector3.UP:
	set(value):
		local_up = value.normalized()
		changed.emit()

## Distance to extrude
var depth := DEFAULT_DEPTH:
	set(value):
		depth = value
		changed.emit()

## Only horizontal surfaces (mesh faces) are eligible. 90deg to include verticals.
var max_slope_degrees := DEFAULT_MAX_SLOPE_DEGREES:
	set(value):
		max_slope_degrees = value
		upright_dot = cos(deg_to_rad(value))
		changed.emit()

## How steeply a face may tilt from local_up and still qualify - derived from max_slope_degrees
var upright_dot := cos(deg_to_rad(DEFAULT_MAX_SLOPE_DEGREES))

var in_vertex_count: int
var in_vertex_stride: int
var in_index_count: int
var in_index_stride: int
var in_normal_offset: int
var in_normal_stride: int
var in_color_offset: int
var in_attribute_stride: int

var out_vertex_count: int
var out_vertex_stride: int
var out_normal_offset: int
var out_normal_stride: int
var out_marker_offset: int
var out_attribute_stride: int


## faces.glsl
func pack_faces() -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(SIZE_FACES)
	bytes.encode_float(0, local_up.x)
	bytes.encode_float(4, local_up.y)
	bytes.encode_float(8, local_up.z)
	bytes.encode_float(12, upright_dot)
	bytes.encode_u32(16, in_index_count)
	bytes.encode_u32(20, in_vertex_count)
	bytes.encode_u32(24, in_index_stride)
	bytes.encode_u32(28, in_normal_offset)
	bytes.encode_u32(32, in_normal_stride)
	bytes.encode_u32(36, in_color_offset)
	bytes.encode_u32(40, in_attribute_stride)
	return bytes


## verts.glsl
func pack_verts() -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(SIZE_VERTS)
	bytes.encode_float(0, local_up.x)
	bytes.encode_float(4, local_up.y)
	bytes.encode_float(8, local_up.z)
	bytes.encode_u32(12, in_vertex_stride)
	bytes.encode_u32(16, in_normal_offset)
	bytes.encode_u32(20, in_normal_stride)
	bytes.encode_u32(24, out_vertex_stride)
	bytes.encode_u32(28, out_normal_offset)
	bytes.encode_u32(32, out_normal_stride)
	bytes.encode_u32(36, out_marker_offset)
	bytes.encode_u32(40, out_attribute_stride)
	return bytes


## shape.glsl
func pack_shape() -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(SIZE_SHAPE)
	bytes.encode_float(0, local_up.x)
	bytes.encode_float(4, local_up.y)
	bytes.encode_float(8, local_up.z)
	bytes.encode_float(12, depth)
	bytes.encode_u32(16, out_vertex_count)
	bytes.encode_u32(20, in_vertex_stride)
	bytes.encode_u32(24, out_vertex_stride)
	bytes.encode_u32(28, out_marker_offset)
	bytes.encode_u32(32, out_attribute_stride)
	return bytes
