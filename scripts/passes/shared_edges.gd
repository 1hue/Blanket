extends ComputePass
class_name SharedEdgesPass

const WORKGROUP_SIZE = 64
const SIZE_PARAMS = 12
const STRUCT_STRIDE = 32

var shared_edge_set: RID
var shared_edge_buffer: RID
var shared_edge_buffer_size: int

var shared_mask_set: RID
var shared_mask_buffer: RID
var shared_mask_buffer_size: int


func _pre() -> void:
	push_constant.resize(SIZE_PARAMS)
	init_shared_edge_buffer()
	init_shared_mask_buffer()


func init_shared_edge_buffer() -> void:
	# shared_count, then one entry per manifold edge pair across the whole source mesh
	shared_edge_buffer_size = align_buffer(4 + params.max_shared_edges * STRUCT_STRIDE)
	shared_edge_buffer = rd.storage_buffer_create(shared_edge_buffer_size)

	shared_edge_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([shared_edge_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER),
	], SurfaceShaders.shared_edges.shader, 1)

	sets.shared_edge_buffer = shared_edge_buffer
	sets.shared_edge = shared_edge_set


func init_shared_mask_buffer() -> void:
	# One 3-bit mask per face, marking which of its edges are shared
	shared_mask_buffer_size = align_buffer(maxi(params.in_face_count, 1) * 4)
	shared_mask_buffer = rd.storage_buffer_create(shared_mask_buffer_size)

	shared_mask_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([shared_mask_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER),
	], SurfaceShaders.shared_edges.shader, 2)

	sets.shared_mask_buffer = shared_mask_buffer
	sets.shared_mask = shared_mask_set


func pack_params() -> PackedByteArray:
	push_constant.encode_u32(0, params.out_custom_offset)
	push_constant.encode_u32(4, params.out_attribute_stride)
	push_constant.encode_u32(8, params.max_shared_edges)

	return push_constant


func compute() -> void:
	rd.buffer_clear(shared_edge_buffer, 0, 16)
	rd.buffer_clear(shared_mask_buffer, 0, shared_mask_buffer_size)

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.shared_edges.pipeline)
	rd.compute_list_set_push_constant(compute_list, pack_params(), SIZE_PARAMS)
	rd.compute_list_bind_uniform_set(compute_list, sets.faces_scratch, 0)
	rd.compute_list_bind_uniform_set(compute_list, shared_edge_set, 1)
	rd.compute_list_bind_uniform_set(compute_list, shared_mask_set, 2)
	rd.compute_list_bind_uniform_set(compute_list, sets.dispatch, 3)
	rd.compute_list_dispatch_indirect(compute_list, sets.dispatch_buffer, 24)
	rd.compute_list_end()


func _notification(what) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	for rid in [
		shared_edge_set, shared_edge_buffer,
		shared_mask_set, shared_mask_buffer,
	]:
		if rid.is_valid():
			rd.free_rid(rid)
