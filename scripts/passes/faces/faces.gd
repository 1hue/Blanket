extends BlanketPass
class_name FacesPass


func _pre() -> void:
	pass


func compute() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, BlanketShaders.faces.pipeline)
	rd.compute_list_bind_uniform_set(compute_list, sets.in_mesh, 0)
	rd.compute_list_bind_uniform_set(compute_list, sets.selected_faces, 1)
	rd.compute_list_bind_uniform_set(compute_list, sets.faces_table, 2)
	rd.compute_list_dispatch_indirect(compute_list, sets.dispatch_buffer, BlanketSets.Dispatch.FACES)
	rd.compute_list_end()
