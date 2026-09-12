extends RefCounted
class_name ComputeParams

signal changed

const DEFAULT_DEPTH = 0.5
const DEFAULT_MAX_SLOPE_DEGREES = 65.0
const DEFAULT_BEVEL_WIDTH = 0.2
const DEFAULT_SMOOTH_STRENGTH = 0.5
const DEFAULT_MIN_CREASE_DEGREES = 15.0
## Sizes BoundaryEdge.top - a spec constant can't, the block stride won't follow
const MAX_BEVEL = 3
const BEVEL_SEGMENTS = 1
const BEVEL_RINGS = 1

#region Source surface
var in_vertex_count: int
var in_vertex_stride: int
var in_index_count: int
var in_index_stride: int
var in_normal_offset: int
var in_normal_stride: int
var in_color_offset: int
var in_attribute_stride: int
var in_face_count: int:
	get: return in_index_count / 3
var in_face_stride: int:
	get: return in_index_stride * 3
#endregion

#region Generated surface
var out_vertex_count: int
var out_vertex_stride: int
var out_index_count: int
var out_index_stride: int
var out_normal_offset: int
var out_normal_stride: int
var out_color_offset: int
var out_custom_offset: int
var out_attribute_stride: int
var out_face_count: int:
	get: return out_index_count / 3
var out_face_stride: int:
	get: return out_index_stride * 3
#endregion

#region Bevel
var bevel_width := DEFAULT_BEVEL_WIDTH
var smooth_strength := DEFAULT_SMOOTH_STRENGTH
var max_shared_edges: int:
	get: return in_face_count * 3
var max_boundary_edges: int:
	get: return in_face_count * 3
## Segments across a ring - both sides of the crease
var ring_steps: int:
	get: return BEVEL_SEGMENTS * 2
## Verts across a ring, ends included
var ring_count: int:
	get: return ring_steps + 1
var fan_vertex_count: int:
	get: return (BEVEL_RINGS - 1) * ring_count + ring_count - 2
var fan_face_count: int:
	get: return ring_steps + (BEVEL_RINGS - 1) * ring_steps * 2
## Both apex fans plus the strip bridging their outer rings
var edge_vertex_count: int:
	get: return fan_vertex_count * 2
var edge_face_count: int:
	get: return fan_face_count * 2 + ring_steps * 2
#endregion

#region Boundary
## Per end: the surface vert, then one per ring out to the retracted vert
var top_verts: int:
	get: return BEVEL_RINGS + 1
var boundary_edge_stride: int:
	get: return 16 + (MAX_BEVEL + 1) * 8
#endregion

#region Boundary wall
var wall_rim_base: int
var wall_grid_base: int
var wall_face_base: int
## Both ends' resolved columns, plus the two rim corners
var wall_cols: int:
	get: return 2 * BEVEL_RINGS + 2
## The rim, the fold, then up to the surface
var wall_rows: int:
	get: return BEVEL_SEGMENTS + 2
## Per boundary edge
var wall_faces_per_edge: int:
	get: return (wall_cols - 1) * (wall_rows - 1) * 2
## Side columns are shared between adjacent walls - one set per selection vert
var wall_side_verts_per_vert: int:
	get: return wall_rows - 1
## Interior columns only; the sides and the top row live elsewhere
var wall_verts_per_edge: int:
	get: return (wall_cols - 2) * (wall_rows - 1)
#endregion

## How steeply a face may tilt from local_up and still qualify - derived from max_slope_degrees
var upright_dot := cos(deg_to_rad(DEFAULT_MAX_SLOPE_DEGREES))

## Below this angle between adjacent faces, the edge is treated as flat and left unbeveled
var crease_dot := cos(deg_to_rad(DEFAULT_MIN_CREASE_DEGREES))

var min_crease_degrees := DEFAULT_MIN_CREASE_DEGREES:
	set(value):
		min_crease_degrees = value
		crease_dot = cos(deg_to_rad(value))
		changed.emit()

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

	assert(primitive == Mesh.PRIMITIVE_TRIANGLES, "Mesh must be triangles: %s is primitive type %s" % [mesh, primitive])
	assert(format & Mesh.ARRAY_FORMAT_NORMAL != 0, "Mesh must have normals: %s" % mesh)
	assert(format & Mesh.ARRAY_FORMAT_COLOR != 0, "Mesh must have vertex colors: %s" % mesh)

	in_vertex_count = mesh.surface_get_array_len(surface.source_idx)
	in_vertex_stride = RenderingServer.mesh_surface_get_format_vertex_stride(format, in_vertex_count)
	in_index_count = mesh.surface_get_array_index_len(surface.source_idx)
	in_index_stride = RenderingServer.mesh_surface_get_format_index_stride(format, in_vertex_count)
	in_normal_offset = RenderingServer.mesh_surface_get_format_offset(format, in_vertex_count, Mesh.ARRAY_NORMAL)
	in_normal_stride = RenderingServer.mesh_surface_get_format_normal_tangent_stride(format, in_vertex_count)
	in_color_offset = RenderingServer.mesh_surface_get_format_offset(format, in_vertex_count, Mesh.ARRAY_COLOR)
	in_attribute_stride = RenderingServer.mesh_surface_get_format_attribute_stride(format, in_vertex_count)
	local_up = global_transform.basis.inverse() * Vector3.UP
