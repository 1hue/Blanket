extends RefCounted
class_name ComputeSurface

const SURFACE_FLAGS := (
	Mesh.ARRAY_FLAG_USE_STORAGE_BUFFER | (Mesh.ARRAY_CUSTOM_R_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
)

var mesh: ArrayMesh
## Original surface derived from
var source_idx: int
## Index of the new surface on the mesh
var idx := -1
var format: int:
	get: return mesh.surface_get_format(idx)
var vertex_count: int:
	get: return mesh.surface_get_array_len(idx)
var vertex_stride: int:
	get: return RenderingServer.mesh_surface_get_format_vertex_stride(format, vertex_count)


func _init(p_mesh: ArrayMesh, p_source_idx: int) -> void:
	mesh = p_mesh
	source_idx = p_source_idx


## Sizes empty arrays and installs the surface - verts.glsl fills the actual data GPU-side.
## custom_aabb is required since positions are all zero at this point.
func allocate(new_vertex_count: int, new_index_count: int) -> void:
	remove()

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var markers := PackedByteArray()
	var indices := PackedInt32Array()
	vertices.resize(new_vertex_count)
	normals.resize(new_vertex_count)
	markers.resize(new_vertex_count * 4)
	indices.resize(new_index_count)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_CUSTOM0] = markers
	arrays[Mesh.ARRAY_INDEX] = indices

	idx = mesh.get_surface_count()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, SURFACE_FLAGS)
	mesh.custom_aabb = source_aabb()


func remove() -> void:
	if idx < 0:
		return
	mesh.surface_remove(idx)
	idx = -1


func source_aabb() -> AABB:
	var source_vertices: PackedVector3Array = mesh.surface_get_arrays(source_idx)[Mesh.ARRAY_VERTEX]
	var aabb := AABB(source_vertices[0], Vector3.ZERO)
	for v in source_vertices:
		aabb = aabb.expand(v)
	return aabb
