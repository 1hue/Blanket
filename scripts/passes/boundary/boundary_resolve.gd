extends ComputePass
class_name BoundaryResolvePass

const WORKGROUP_SIZE = 64
const SIZE_PARAMS = 8
## Must match boundary_resolve.glsl and friends - sizes the resolved column per end
const MAX_RINGS = 3
const TOP_VERTS = MAX_RINGS + 1
const BOUNDARY_EDGE_STRIDE = 16 + TOP_VERTS * 8

func _pre() -> void:
	push_constant.resize(SIZE_PARAMS)
	assert(params.bevel_rings <= MAX_RINGS, "bevel_rings exceeds the resolved column size")


func pack_params() -> PackedByteArray:
	push_constant.encode_u32(0, params.bevel_steps)
	push_constant.encode_u32(4, params.bevel_rings)

	return push_constant


func compute() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.boundary_resolve.pipeline)
	rd.compute_list_set_push_constant(compute_list, pack_params(), SIZE_PARAMS)
	rd.compute_list_bind_uniform_set(compute_list, sets.boundary, 0)
	rd.compute_list_bind_uniform_set(compute_list, sets.face_edge_mask, 1)
	rd.compute_list_bind_uniform_set(compute_list, sets.shared_edge, 2)
	rd.compute_list_bind_uniform_set(compute_list, sets.selected_faces, 3)
	rd.compute_list_dispatch_indirect(compute_list, sets.dispatch_buffer, ComputeSets.Dispatch.BOUNDARY)
	rd.compute_list_end()
