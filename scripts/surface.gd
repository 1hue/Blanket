extends RefCounted
class_name ComputeSurface

const SURFACE_FLAGS := Mesh.ARRAY_FLAG_USE_STORAGE_BUFFER \
	| (Mesh.ARRAY_CUSTOM_R_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)

var mesh: ArrayMesh
var idx := -1
var source_map := PackedInt32Array()


func _init(p_mesh: ArrayMesh, p_idx: int) -> void:
	mesh = p_mesh
	idx = p_idx


func rebuild(
	upright_indices: PackedInt32Array,
	outer_edges: PackedInt32Array,
	local_up: Vector3
) -> void:
	remove()

	var source_arrays := mesh.surface_get_arrays(0)
	var source_vertices: PackedVector3Array = source_arrays[Mesh.ARRAY_VERTEX]
	var source_normals: PackedVector3Array = source_arrays[Mesh.ARRAY_NORMAL]

	var geometry := SurfaceGeometry.new()
	geometry.add_cap(source_vertices, source_normals, upright_indices)
	geometry.add_walls(source_vertices, outer_edges, local_up)

	source_map = geometry.source_map
	idx = mesh.get_surface_count()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, geometry.to_arrays(), [], {}, SURFACE_FLAGS)


func remove() -> void:
	if idx < 0:
		return
	mesh.surface_remove(idx)
	idx = -1


func vertex_count() -> int:
	return mesh.surface_get_array_len(idx)


func vertex_stride() -> int:
	return RenderingServer.mesh_surface_get_format_vertex_stride(
		mesh.surface_get_format(idx), vertex_count()
	)
