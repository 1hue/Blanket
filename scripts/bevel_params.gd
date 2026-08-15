extends RefCounted
class_name BevelParams

const SIZE_SHRINK = 12
const SIZE_FILL = 16
const DEFAULT_SHRINK = 0.3
const DEFAULT_SEGMENTS = 2
const WEDGE_SEGMENTS = 2

var shrink := DEFAULT_SHRINK
var in_vertex_count: int
var in_index_count: int
var out_vertex_count: int
var out_index_count: int
var out_color_offset: int
var out_attribute_stride: int
var segments := DEFAULT_SEGMENTS
var bevel := 0.0

var max_shared_edges: int:
	get: return in_index_count / 2


func pack_shrink() -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(SIZE_SHRINK)
	bytes.encode_float(0, shrink)
	bytes.encode_u32(4, out_color_offset)
	bytes.encode_u32(8, out_attribute_stride)
	return bytes


func pack_fill() -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(SIZE_FILL)
	bytes.encode_float(0, shrink)
	bytes.encode_u32(4, segments)
	bytes.encode_u32(8, out_color_offset)
	bytes.encode_u32(12, out_attribute_stride)
	return bytes
