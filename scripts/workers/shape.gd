extends ComputeWorker
class_name Shape


func _pre() -> void:
	pass


## Dispatch shape.glsl to reposition the spawned mesh surface
func compute() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.shape.pipeline)
	rd.compute_list_set_push_constant(compute_list, params.pack_shape(), ComputeParams.SIZE_SHAPE)
	rd.compute_list_bind_uniform_set(compute_list, in_uniform_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, out_uniform_set, 2)
	rd.compute_list_dispatch(compute_list, ceili(params.out_vertex_count / 256.0), 1, 1)
	rd.compute_list_end()
