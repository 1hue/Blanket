extends RefCounted
class_name SurfaceGeometry

const MARKER_SHIFTED := 1.0
const MARKER_STATIC := 0.0

var vertices := PackedVector3Array()
var normals := PackedVector3Array()
var markers := PackedFloat32Array()
var source_map := PackedInt32Array()
var indices := PackedInt32Array()


func add_vertex(position: Vector3, normal: Vector3, marker: float, source_index: int) -> int:
	vertices.append(position)
	normals.append(normal)
	markers.append(marker)
	source_map.append(source_index)
	return vertices.size() - 1


func add_triangle(a: int, b: int, c: int) -> void:
	indices.append(a)
	indices.append(b)
	indices.append(c)


func add_cap(
	source_vertices: PackedVector3Array,
	source_normals: PackedVector3Array,
	eligible_indices: PackedInt32Array
) -> void:
	for source_index in eligible_indices:
		add_vertex(
			source_vertices[source_index],
			source_normals[source_index],
			MARKER_SHIFTED,
			source_index
		)

	for i in eligible_indices.size() / 3:
		add_triangle(i * 3, i * 3 + 1, i * 3 + 2)


func add_walls(
	source_vertices: PackedVector3Array,
	outer_edges: PackedInt32Array,
	local_up: Vector3
) -> void:
	for e in outer_edges.size() / 2:
		var index_a := outer_edges[e * 2]
		var index_b := outer_edges[e * 2 + 1]
		var position_a := source_vertices[index_a]
		var position_b := source_vertices[index_b]
		var normal := (position_b - position_a).cross(local_up).normalized()

		var bottom_a := add_vertex(position_a, normal, MARKER_STATIC, index_a)
		var bottom_b := add_vertex(position_b, normal, MARKER_STATIC, index_b)
		var top_a := add_vertex(position_a, normal, MARKER_SHIFTED, index_a)
		var top_b := add_vertex(position_b, normal, MARKER_SHIFTED, index_b)

		add_triangle(bottom_a, bottom_b, top_b)
		add_triangle(bottom_a, top_b, top_a)


func to_arrays() -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_CUSTOM0] = markers.to_byte_array()
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays
