extends RefCounted
class_name ComputeSurface

const MARKER_SHIFTED := 1.0
const MARKER_STATIC := 0.0
const SURFACE_FLAGS := (
	Mesh.ARRAY_FLAG_USE_STORAGE_BUFFER | (Mesh.ARRAY_CUSTOM_R_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
)

var vertices := PackedVector3Array()
var normals := PackedVector3Array()
var markers := PackedFloat32Array()
var indices := PackedInt32Array()
## Per new vertex, the source vertex it came from - shift_amount offsets from that position
var indices_sources := PackedInt32Array()

var mesh: ArrayMesh
var idx := -1 # Index of this new surface on the original mesh
var format: int:
	get: return mesh.surface_get_format(idx)
var vertex_count: int:
	get: return mesh.surface_get_array_len(idx)
var vertex_stride: int:
	get: return RenderingServer.mesh_surface_get_format_vertex_stride(format, vertex_count)


func _init(p_mesh: ArrayMesh) -> void:
	mesh = p_mesh


func rebuild(
	source_faces: PackedInt32Array,
	source_edges: PackedInt32Array,
	local_up: Vector3
) -> void:
	remove()
	clear()

	var source_arrays := mesh.surface_get_arrays(0)
	var source_vertices: PackedVector3Array = source_arrays[Mesh.ARRAY_VERTEX]
	var source_normals: PackedVector3Array = source_arrays[Mesh.ARRAY_NORMAL]

	add_cap(source_vertices, source_normals, source_faces)
	add_walls(source_vertices, source_edges, local_up)

	idx = mesh.get_surface_count()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, to_arrays(), [], {}, SURFACE_FLAGS)


func remove() -> void:
	if idx < 0:
		return
	mesh.surface_remove(idx)
	idx = -1


func clear() -> void:
	vertices.clear()
	normals.clear()
	markers.clear()
	indices.clear()
	indices_sources.clear()


func add_vertex(position: Vector3, normal: Vector3, marker: float, source_index: int) -> int:
	vertices.append(position)
	normals.append(normal)
	markers.append(marker)
	indices_sources.append(source_index)
	return vertices.size() - 1


func add_triangle(a: int, b: int, c: int) -> void:
	indices.append(a)
	indices.append(b)
	indices.append(c)


func add_cap(
	source_vertices: PackedVector3Array,
	source_normals: PackedVector3Array,
	source_faces: PackedInt32Array
) -> void:
	for source_index in source_faces:
		add_vertex(
			source_vertices[source_index],
			source_normals[source_index],
			MARKER_SHIFTED,
			source_index
		)

	for i in source_faces.size() / 3:
		add_triangle(i * 3, i * 3 + 1, i * 3 + 2)


func add_walls(
	source_vertices: PackedVector3Array,
	source_edges: PackedInt32Array,
	local_up: Vector3
) -> void:
	for e in source_edges.size() / 2:
		var source_a := source_edges[e * 2]
		var source_b := source_edges[e * 2 + 1]
		var position_a := source_vertices[source_a]
		var position_b := source_vertices[source_b]
		var normal := (position_b - position_a).cross(local_up).normalized()

		var bottom_a := add_vertex(position_a, normal, MARKER_STATIC, source_a)
		var bottom_b := add_vertex(position_b, normal, MARKER_STATIC, source_b)
		var top_a := add_vertex(position_a, normal, MARKER_SHIFTED, source_a)
		var top_b := add_vertex(position_b, normal, MARKER_SHIFTED, source_b)

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
