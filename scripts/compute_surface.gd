extends RefCounted
class_name ComputeSurface

const SURFACE_NAME = "ComputedSurface"
const SURFACE_FLAGS := (
	Mesh.ARRAY_FLAG_USE_STORAGE_BUFFER | (Mesh.ARRAY_CUSTOM_R_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
)

var mesh: ArrayMesh
var mesh_rid: RID:
	get: return mesh.get_rid()
## Original surface derived from.
var source_idx: int
## The newly created surface on the mesh.
var idx := -1
var format: int:
	get: return mesh.surface_get_format(idx) if idx >= 0 else 0
var vertex_count: int:
	get: return mesh.surface_get_array_len(idx) if idx >= 0 else 0
var vertex_stride: int:
	get: return RenderingServer.mesh_surface_get_format_vertex_stride(format, vertex_count) if idx >= 0 else 0


func _init(p_mesh: ArrayMesh, p_source_idx: int) -> void:
	mesh = p_mesh
	source_idx = p_source_idx


## Size empty mesh arrays and install the surface for manipulation GPU-side.
## Set custom_aabb since positions are all zero at this point.
func allocate(new_vertex_count: int, new_index_count: int, array_types: int = Mesh.ARRAY_NORMAL) -> void:
	remove()

	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	vertices.resize(new_vertex_count)
	indices.resize(new_index_count)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices

	if array_types & Mesh.ARRAY_NORMAL:
		var normals := PackedVector3Array()
		normals.resize(new_vertex_count)
		arrays[Mesh.ARRAY_NORMAL] = normals

	if array_types & Mesh.ARRAY_TANGENT:
		var tangents := PackedFloat32Array()
		tangents.resize(new_vertex_count * 4)
		arrays[Mesh.ARRAY_TANGENT] = tangents

	if array_types & Mesh.ARRAY_CUSTOM0:
		var custom_0 := PackedFloat32Array()
		custom_0.resize(new_vertex_count)
		arrays[Mesh.ARRAY_CUSTOM0] = custom_0

	if array_types & Mesh.ARRAY_COLOR:
		var colors := PackedColorArray()
		colors.resize(new_vertex_count)
		arrays[Mesh.ARRAY_COLOR] = colors

	idx = mesh.get_surface_count()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, SURFACE_FLAGS)
	mesh.surface_set_name(idx, SURFACE_NAME)
	mesh.custom_aabb = source_aabb()
	mesh.emit_changed()


func remove() -> void:
	if idx >= 0:
		mesh.surface_remove(idx)
		mesh.emit_changed()
	idx = -1


func source_aabb() -> AABB:
	var source_vertices: PackedVector3Array = mesh.surface_get_arrays(source_idx)[Mesh.ARRAY_VERTEX]
	var aabb := AABB(source_vertices[0], Vector3.ZERO)
	for v in source_vertices:
		aabb = aabb.expand(v)
	return aabb
