extends BlanketPass
class_name EdgesPass

const SIZE_PARAMS = 4
const SHARED_EDGE_STRIDE = 36
const FACE_EDGE_STRIDE = 8
const BOUNDARY_EDGE_STRIDE = 16 + (BlanketParams.MAX_BEVEL + 1) * 8
const BOUNDARY_HEADER = 8 # boundary_count, boundary_vert_count

var shared_edge_set: RID
var shared_edge_buffer: RID
var shared_edge_buffer_size: int

var face_edge_set: RID
var face_edge_buffer: RID
var face_edge_buffer_size: int

var vertex_flag_set: RID
var vertex_flag_buffer: RID
var vertex_flag_buffer_size: int

var boundary_set: RID
var boundary_buffer: RID
var boundary_buffer_size: int


func _pre() -> void:
	push_constant.resize(SIZE_PARAMS)
	init_shared_edge_buffer()
	init_face_edge_buffer()
	init_vertex_flag_buffer()
	init_boundary_buffer()


func init_shared_edge_buffer() -> void:
	shared_edge_buffer_size = align_buffer(4 + params.max_edges * SHARED_EDGE_STRIDE)
	shared_edge_buffer = rd.storage_buffer_create(shared_edge_buffer_size)

	shared_edge_set = rd.uniform_set_create([
		BlanketUtil.create_uniform([shared_edge_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER),
	], BlanketShaders.edges.shaders[version], 1)

	sets.shared_edge_buffer = shared_edge_buffer
	sets.shared_edge = shared_edge_set


func init_face_edge_buffer() -> void:
	# One entry per corner, holding the twin's address
	face_edge_buffer_size = align_buffer(maxi(params.max_edges, 1) * FACE_EDGE_STRIDE)
	face_edge_buffer = rd.storage_buffer_create(face_edge_buffer_size)

	face_edge_set = rd.uniform_set_create([
		BlanketUtil.create_uniform([face_edge_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER),
	], BlanketShaders.edges.shaders[version], 2)

	sets.face_edge_buffer = face_edge_buffer
	sets.face_edge = face_edge_set


func init_vertex_flag_buffer() -> void:
	# One flag word per deduped vert - in_vertex_count is the upper bound
	vertex_flag_buffer_size = align_buffer(maxi(params.in_vertex_count, 1) * 4)
	vertex_flag_buffer = rd.storage_buffer_create(vertex_flag_buffer_size)

	vertex_flag_set = rd.uniform_set_create([
		BlanketUtil.create_uniform([vertex_flag_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER),
	], BlanketShaders.edges.shaders[version], 3)

	sets.vertex_flag_buffer = vertex_flag_buffer
	sets.vertex_flag = vertex_flag_set

func init_boundary_buffer() -> void:
	boundary_buffer_size = align_buffer(BOUNDARY_HEADER + params.max_edges * BOUNDARY_EDGE_STRIDE)
	boundary_buffer = rd.storage_buffer_create(boundary_buffer_size)

	boundary_set = rd.uniform_set_create([
		BlanketUtil.create_uniform([boundary_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER),
	], BlanketShaders.edges.shaders[version], 4)

	sets.boundary_buffer = boundary_buffer
	sets.boundary = boundary_set


func pack_params() -> PackedByteArray:
	push_constant.encode_u32(0, params.max_edges)

	return push_constant


func compute() -> void:
	rd.buffer_clear(shared_edge_buffer, 0, shared_edge_buffer_size)
	rd.buffer_clear(face_edge_buffer, 0, face_edge_buffer_size)
	rd.buffer_clear(vertex_flag_buffer, 0, vertex_flag_buffer_size)
	rd.buffer_clear(boundary_buffer, 0, boundary_buffer_size)

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, BlanketShaders.edges.pipelines[version])
	rd.compute_list_set_push_constant(compute_list, pack_params(), SIZE_PARAMS)
	rd.compute_list_bind_uniform_set(compute_list, sets.selected_faces, 0)
	rd.compute_list_bind_uniform_set(compute_list, shared_edge_set, 1)
	rd.compute_list_bind_uniform_set(compute_list, face_edge_set, 2)
	rd.compute_list_bind_uniform_set(compute_list, vertex_flag_set, 3)
	rd.compute_list_bind_uniform_set(compute_list, boundary_set, 4)
	rd.compute_list_bind_uniform_set(compute_list, sets.dispatch, 5)
	rd.compute_list_dispatch_indirect(compute_list, sets.dispatch_buffer, BlanketSets.Dispatch.EDGES)
	rd.compute_list_end()


func _notification(what) -> void:
	if what != NOTIFICATION_PREDELETE:
		return

	for rid in [
		shared_edge_set, shared_edge_buffer,
		face_edge_set, face_edge_buffer,
		vertex_flag_set, vertex_flag_buffer,
		boundary_set, boundary_buffer,
	]:
		if rid:
			rd.free_rid(rid)
