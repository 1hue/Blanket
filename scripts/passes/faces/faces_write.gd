extends ComputePass
class_name FacesWritePass


func _pre() -> void:
	pass


func compute() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.faces_write.pipeline)
	rd.compute_list_bind_uniform_set(compute_list, sets.in_mesh, 0)
	rd.compute_list_bind_uniform_set(compute_list, sets.faces_scratch, 1)
	rd.compute_list_bind_uniform_set(compute_list, sets.faces_table, 2)
	rd.compute_list_dispatch_indirect(compute_list, sets.faces_write_dispatch_buffer, 0)
	rd.compute_list_end()
