extends ComputePass
class_name BoundaryPass

const WORKGROUP_SIZE = 64
const SIZE_PARAMS = 32
## Per boundary edge: inner pair, retracted rim pair, centre
const ARC_VERTS = 5
## Per boundary edge: 2 fans, 2 notches, 4 centre, 2 fold, 2 wall
const FACES = 12


func _pre() -> void:
	push_constant.resize(SIZE_PARAMS)


func pack_params() -> PackedByteArray:
	push_constant.encode_u32(0, params.selected_vertex_count)
	push_constant.encode_u32(4, params.wall_rim_base)
	push_constant.encode_u32(8, params.wall_arc_base)
	push_constant.encode_u32(12, params.wall_face_base)
	push_constant.encode_float(16, params.bevel_width)
	push_constant.encode_u32(20, params.out_color_offset)
	push_constant.encode_u32(24, params.out_custom_offset)
	push_constant.encode_u32(28, params.out_attribute_stride)

	return push_constant


func compute() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.boundary.pipeline)
	rd.compute_list_set_push_constant(compute_list, pack_params(), SIZE_PARAMS)
	rd.compute_list_bind_uniform_set(compute_list, sets.out_mesh, 0)
	rd.compute_list_bind_uniform_set(compute_list, sets.boundary, 1)
	rd.compute_list_bind_uniform_set(compute_list, sets.face_edge_mask, 2)
	rd.compute_list_dispatch_indirect(compute_list, sets.dispatch_buffer, 72)
	rd.compute_list_end()
