extends ComputePass
class_name SmoothSumPass

var buffer: RID
var buffer_size: int
var uniform_set: RID


func _pre() -> void:
	buffer_size = params.bevel_vertex_count * 16
	buffer = rd.storage_buffer_create(buffer_size)

	uniform_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
	], SurfaceShaders.smooth_sum.shader, 0)

	uniforms.smooth_sum = buffer
	uniforms.smooth_sum_set = uniform_set


## Normals must be recalculated after this.
func compute() -> void:
	rd.buffer_clear(buffer, 0, buffer_size)

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.smooth_sum.pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, uniforms.bevel_out_set, 1)
	rd.compute_list_dispatch(compute_list, ceili(params.bevel_index_count / 3.0 / 256.0), 1, 1)
	rd.compute_list_end()


func _notification(what) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	for rid in [uniform_set, buffer]:
		if rid.is_valid():
			rd.free_rid(rid)
