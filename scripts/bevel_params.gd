extends RefCounted
class_name BevelParams

const SIZE_SHRINK = 20
const SIZE_JOIN = 4
const DEFAULT_SHRINK = 0.3

var shrink := DEFAULT_SHRINK
var in_vertex_count: int
var in_index_count: int
var out_vertex_count: int
var out_color_offset: int
var out_attribute_stride: int


func pack_shrink() -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(SIZE_SHRINK)
	bytes.encode_float(0, shrink)
	bytes.encode_u32(4, in_vertex_count)
	bytes.encode_u32(8, in_index_count)
	bytes.encode_u32(12, out_color_offset)
	bytes.encode_u32(16, out_attribute_stride)
	return bytes


func pack_wedge() -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(SIZE_JOIN)
	bytes.encode_float(0, shrink)
	return bytes
