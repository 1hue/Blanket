extends ComputePass
class_name BoundaryPass

const WORKGROUP_SIZE = 64
const SIZE_PARAMS = 20


func _pre() -> void:
	push_constant.resize(SIZE_PARAMS)


func pack_params() -> PackedByteArray:
	push_constant.encode_u32(0, params.wall_vertex_base)
	push_constant.encode_u32(4, params.wall_face_base)
	push_constant.encode_u32(8, params.out_color_offset)
	push_constant.encode_u32(12, params.out_custom_offset)
	push_constant.encode_u32(16, params.out_attribute_stride)

	return push_constant


func compute() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.boundary.pipeline)
	rd.compute_list_set_push_constant(compute_list, pack_params(), SIZE_PARAMS)
	rd.compute_list_bind_uniform_set(compute_list, sets.out_mesh, 0)
	rd.compute_list_bind_uniform_set(compute_list, sets.boundary, 1)
	rd.compute_list_dispatch_indirect(compute_list, sets.dispatch_buffer, 72)
	rd.compute_list_end()
