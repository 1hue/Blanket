extends RefCounted
class_name ComputeParams

signal changed

const DEFAULT_DEPTH = 0.1
const DEFAULT_MAX_SLOPE_DEGREES = 65.0
const MAX_VALENCE = 32
const DEFAULT_BEVEL_SHRINK = 0.3
const DEFAULT_BEVEL_SEGMENTS = 2
const BEVEL_WEDGE_SEGMENTS = 2

#region Source surface
var in_vertex_count: int
var in_vertex_stride: int
var in_index_count: int
var in_index_stride: int
var in_normal_offset: int
var in_normal_stride: int
var in_color_offset: int
var in_attribute_stride: int
#endregion

#region Select
var select_vertex_count: int
var select_vertex_stride: int
var select_normal_offset: int
var select_normal_stride: int
var select_marker_offset: int
var select_attribute_stride: int
var select_index_stride: int
#endregion

#region Bevel
var bevel := 0.0
var bevel_shrink := DEFAULT_BEVEL_SHRINK
var bevel_segments := DEFAULT_BEVEL_SEGMENTS
var bevel_vertex_count: int
var bevel_index_count: int
var bevel_normal_offset: int
var bevel_normal_stride: int
var bevel_color_offset: int
var bevel_attribute_stride: int
var max_shared_edges: int:
	get: return in_index_count / 2
#endregion

## How steeply a face may tilt from local_up and still qualify - derived from max_slope_degrees
var upright_dot := cos(deg_to_rad(DEFAULT_MAX_SLOPE_DEGREES))

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


func _init(surface: ComputeSurface, global_transform: Transform3D) -> void:
	var mesh := surface.mesh
	var format := mesh.surface_get_format(surface.source_idx)
	var primitive := mesh.surface_get_primitive_type(surface.source_idx)
	var vertex_count := mesh.surface_get_array_len(surface.source_idx)

	assert(primitive == Mesh.PRIMITIVE_TRIANGLES, "Mesh must be triangles: %s is primitibe type %s" % [mesh, primitive])
	assert(format & Mesh.ARRAY_FORMAT_NORMAL != 0, "Mesh must have normals: %s" % mesh)
	assert(format & Mesh.ARRAY_FORMAT_COLOR != 0, "Mesh must have vertex colors: %s" % mesh)

	in_vertex_count = vertex_count
	in_vertex_stride = RenderingServer.mesh_surface_get_format_vertex_stride(format, vertex_count)
	in_index_count = mesh.surface_get_array_index_len(surface.source_idx)
	in_index_stride = RenderingServer.mesh_surface_get_format_index_stride(format, vertex_count)
	in_normal_offset = RenderingServer.mesh_surface_get_format_offset(format, vertex_count, Mesh.ARRAY_NORMAL)
	in_normal_stride = RenderingServer.mesh_surface_get_format_normal_tangent_stride(format, vertex_count)
	in_color_offset = RenderingServer.mesh_surface_get_format_offset(format, vertex_count, Mesh.ARRAY_COLOR)
	in_attribute_stride = RenderingServer.mesh_surface_get_format_attribute_stride(format, vertex_count)
	local_up = global_transform.basis.inverse() * Vector3.UP
