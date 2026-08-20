extends ComputeWorker
class_name SelectEdgesWorker

const SIZE_PARAMS = 8
const EDGES_BUFFER_HEADER = 4 # edges_count

## Source vert indices of outer edges as uvec2, e.g. [(3, 1), (1, 2), (0, 2)]
var edges_buffer: RID
var edges_buffer_size: int
var edges_uniform_set: RID
var dispatch_buffer: RID
var dispatch_uniform_set: RID


func _pre() -> void:
	push_constant.resize(SIZE_PARAMS)
	_init_uniforms()
	_init_indirect_dispatch()


func _init_uniforms() -> void:
	edges_buffer_size = EDGES_BUFFER_HEADER + params.in_index_count * 12

	edges_buffer = rd.storage_buffer_create(
		edges_buffer_size, PackedByteArray(), RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT
	)

	edges_uniform_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([edges_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 1)
	], SurfaceShaders.selection_edges.shader, 2)


## Separate dispatch buffers. WARNING: must not be passed into target shader - engine constraint.
func _init_indirect_dispatch() -> void:
	dispatch_buffer = rd.storage_buffer_create(
		12, PackedByteArray(), RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT
	)

	uniforms.edges_dispatch_buffer = dispatch_buffer

	dispatch_uniform_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([dispatch_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
	], SurfaceShaders.selection_edges.shader, 3)


func pack_params() -> PackedByteArray:
	push_constant.encode_u32(0, params.in_vertex_stride)
	push_constant.encode_u32(4, params.in_vertex_count)

	return push_constant


## Select outer edges
func compute() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.selection_edges.pipeline)
	rd.compute_list_set_push_constant(compute_list, pack_params(), SIZE_PARAMS)
	rd.compute_list_bind_uniform_set(compute_list, uniforms.source_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, edges_uniform_set, 1)
	rd.compute_list_bind_uniform_set(compute_list, uniforms.faces_set, 1)
	rd.compute_list_bind_uniform_set(compute_list, dispatch_uniform_set, 2)
	rd.compute_list_dispatch_indirect(compute_list, uniforms.faces_dispatch_buffer, 0)
	rd.compute_list_end()
