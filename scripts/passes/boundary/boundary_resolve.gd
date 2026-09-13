extends ComputePass
class_name BoundaryResolvePass

const WORKGROUP_SIZE = 64


func _pre() -> void:
	pass


func compute() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.boundary_resolve.pipeline)
	rd.compute_list_bind_uniform_set(compute_list, sets.boundary, 0)
	rd.compute_list_bind_uniform_set(compute_list, sets.face_edge_mask, 1)
	rd.compute_list_bind_uniform_set(compute_list, sets.shared_edge, 2)
	rd.compute_list_bind_uniform_set(compute_list, sets.selected_faces, 3)
	rd.compute_list_dispatch_indirect(compute_list, sets.dispatch_buffer, ComputeSets.Dispatch.BOUNDARY)
	rd.compute_list_end()
