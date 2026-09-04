extends ComputePass
class_name SharedEdgesPass

const SIZE_PARAMS = 16
const STRUCT_STRIDE = 32

var shared_edge_buffer: RID
var shared_edge_buffer_size: int
var shared_edge_uniform_set: RID

var shared_mask_buffer: RID
var shared_mask_buffer_size: int
var shared_mask_uniform_set: RID

var dispatch_buffer: RID
var dispatch_uniform_set: RID


func _pre() -> void:
	push_constant.resize(SIZE_PARAMS)


## Sizes depend on the selection, so this runs after faces_write
func init_uniforms() -> void:
	# shared_count, then at most one entry per pair of selected face edges
	shared_edge_buffer_size = align_buffer(16 + params.max_shared_edges * STRUCT_STRIDE)
	shared_edge_buffer = rd.storage_buffer_create(shared_edge_buffer_size)

	shared_edge_uniform_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([shared_edge_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER),
	], SurfaceShaders.shared_edges.shader, 1)

	# One 3-bit mask per face, marking which of its edges are shared
	shared_mask_buffer_size = align_buffer(maxi(params.selected_face_count, 1) * 4)
	shared_mask_buffer = rd.storage_buffer_create(shared_mask_buffer_size)

	shared_mask_uniform_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([shared_mask_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER),
	], SurfaceShaders.shared_edges.shader, 2)

	dispatch_buffer = rd.storage_buffer_create(
		12, PackedByteArray(), RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT
	)

	dispatch_uniform_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([dispatch_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER),
	], SurfaceShaders.shared_edges.shader, 3)

	uniforms.shared_edge_set = shared_edge_uniform_set
	uniforms.shared_mask_set = shared_mask_uniform_set
	uniforms.shared_edge_buffer = shared_edge_buffer
	uniforms.shared_mask_buffer = shared_mask_buffer
	uniforms.bevel_fill_dispatch_buffer = dispatch_buffer


func pack_params() -> PackedByteArray:
	push_constant.encode_u32(0, params.selected_vertex_count)
	push_constant.encode_u32(4, params.selected_face_count)
	push_constant.encode_u32(8, params.out_custom_offset)
	push_constant.encode_u32(12, params.out_attribute_stride)

	return push_constant


func compute() -> void:
	init_uniforms()
	rd.buffer_clear(shared_edge_buffer, 0, shared_edge_buffer_size)
	rd.buffer_clear(shared_mask_buffer, 0, shared_mask_buffer_size)
	rd.buffer_clear(dispatch_buffer, 0, 12)

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.shared_edges.pipeline)
	rd.compute_list_set_push_constant(compute_list, pack_params(), SIZE_PARAMS)
	rd.compute_list_bind_uniform_set(compute_list, uniforms.out_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, shared_edge_uniform_set, 1)
	rd.compute_list_bind_uniform_set(compute_list, shared_mask_uniform_set, 2)
	rd.compute_list_bind_uniform_set(compute_list, dispatch_uniform_set, 3)
	rd.compute_list_dispatch(compute_list, ceili(params.selected_face_count / 64.0), 1, 1)
	rd.compute_list_end()


func _notification(what) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	for rid in [
		shared_edge_uniform_set, shared_edge_buffer, shared_mask_uniform_set, shared_mask_buffer,
		dispatch_uniform_set, dispatch_buffer,
	]:
		if rid.is_valid():
			rd.free_rid(rid)
