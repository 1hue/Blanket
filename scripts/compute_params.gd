extends RefCounted
class_name ComputeParams

signal changed

const DEFAULT_DEPTH = 0.5
const DEFAULT_MAX_SLOPE_DEGREES = 65.0
const DEFAULT_MIN_CREASE_DEGREES = 15.0

## Sizes BoundaryEdge.top - a spec constant can't, the block stride won't follow
const MAX_BEVEL = 3
## Passed to every pipeline as specialization constants, so a change needs a re-bake
const BEVEL_SEGMENTS = 1
const BEVEL_ARCS = 1
const BEVEL_WIDTH = 0.2
const SMOOTH_STRENGTH = 0.5
const SMOOTH_WALL_STRENGTH = 0.3

#region Bevel
## Segments across an arc - both sides of the crease
const ARC_SEGMENTS = BEVEL_SEGMENTS * 2
## Verts across an arc, ends included
const ARC_VERTS = ARC_SEGMENTS + 1
const FAN_VERTS = (BEVEL_ARCS - 1) * ARC_VERTS + ARC_VERTS - 2
const FAN_FACES = ARC_SEGMENTS + (BEVEL_ARCS - 1) * ARC_SEGMENTS * 2
## Both apex fans plus the strip bridging their outer arcs
const EDGE_VERTS = FAN_VERTS * 2
const EDGE_FACES = FAN_FACES * 2 + ARC_SEGMENTS * 2
#endregion

#region Boundary
## Live length of BoundaryEdge.top - the array itself is MAX_BEVEL + 1 long
const TOP_VERTS = BEVEL_ARCS + 1
const BOUNDARY_EDGE_STRIDE = 16 + (MAX_BEVEL + 1) * 8
#endregion

#region Boundary wall - a quad grid filling each boundary edge's skirt
## Both ends' resolved columns, plus the two rim corners
const WALL_COLS = 2 * BEVEL_ARCS + 2
## The rim, the fold, then up to the surface
const WALL_ROWS = BEVEL_SEGMENTS + 2
## Per boundary edge
const WALL_FACES_PER_EDGE = (WALL_COLS - 1) * (WALL_ROWS - 1) * 2
## Side columns are shared between adjacent walls - one set per selection vert
const WALL_SIDE_VERTS_PER_VERT = WALL_ROWS - 1
## Interior columns only; the sides and the top row live elsewhere
const WALL_VERTS_PER_EDGE = (WALL_COLS - 2) * (WALL_ROWS - 1)

var wall_rim_base: int
var wall_grid_base: int
var wall_face_base: int
#endregion

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
## Every corner may append once, to either edge list - the only bound that can't overflow
var max_edges: int:
	get: return in_face_count * 3
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
	@warning_ignore("assert_always_true")
	assert(BEVEL_ARCS <= MAX_BEVEL and BEVEL_SEGMENTS <= MAX_BEVEL, "Bevel exceeds the fixed array size")

	in_vertex_count = mesh.surface_get_array_len(surface.source_idx)
	in_vertex_stride = RenderingServer.mesh_surface_get_format_vertex_stride(format, in_vertex_count)
	in_index_count = mesh.surface_get_array_index_len(surface.source_idx)
	in_index_stride = RenderingServer.mesh_surface_get_format_index_stride(format, in_vertex_count)
	in_normal_offset = RenderingServer.mesh_surface_get_format_offset(format, in_vertex_count, Mesh.ARRAY_NORMAL)
	in_normal_stride = RenderingServer.mesh_surface_get_format_normal_tangent_stride(format, in_vertex_count)
	in_color_offset = RenderingServer.mesh_surface_get_format_offset(format, in_vertex_count, Mesh.ARRAY_COLOR)
	in_attribute_stride = RenderingServer.mesh_surface_get_format_attribute_stride(format, in_vertex_count)
	local_up = global_transform.basis.inverse() * Vector3.UP
