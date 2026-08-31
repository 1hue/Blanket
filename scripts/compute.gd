extends RefCounted
class_name Compute

@warning_ignore("unused_signal")
signal output(message: String)

var rd: RenderingDevice
var params: ComputeParams
var uniforms: ComputeUniforms
var surface: ComputeSurface

var mesh: ArrayMesh
var mesh_rid: RID:
	get: return mesh.get_rid()
var in_uniform_set: RID # 0 = Verts, 1 = Indices, 2 = Attributes

#var debug_buffer: RID
#var debug_uniform_set: RID

var bake_passes: Array[ComputePass]


func _init(p_mesh: ArrayMesh, surface_idx: int, global_transform: Transform3D) -> void:
	rd = RenderingServer.get_rendering_device()
	assert(rd != null, "No RenderingDevice - compute requires Forward+ or Mobile renderer")
	assert(SurfaceShaders is Node, "SurfaceShaders autoload missing - check Project Settings > Autoload")
	assert(p_mesh != null, "Mesh is null")
	assert(surface_idx >= 0 and surface_idx < p_mesh.get_surface_count(),
		"Surface %d out of range on %s (%d surfaces)" % [surface_idx, p_mesh, p_mesh.get_surface_count()])

	mesh = p_mesh
	surface = ComputeSurface.new(p_mesh, surface_idx)
	uniforms = ComputeUniforms.new(surface)
	params = ComputeParams.new(surface, global_transform)

	bake_passes = [
		FacesSelectPass.new(mesh, surface, params, uniforms),
		FacesDedupePass.new(mesh, surface, params, uniforms),
		FacesWritePass.new(mesh, surface, params, uniforms),
		FacesPinPass.new(mesh, surface, params, uniforms),
		#BevelShrinkPass.new(mesh, surface, params, uniforms),
		#BevelFillPass.new(mesh, surface, params, uniforms),
		#SmoothSumPass.new(mesh, surface, params, uniforms),
		#SmoothWritePass.new(mesh, surface, params, uniforms),
		#NormalsSumPass.new(mesh, surface, params, uniforms),
		#NormalsWritePass.new(mesh, surface, params, uniforms),
		#ShapePass.new(mesh, surface, params, uniforms),
	]


func bake() -> void:
	for bake_pass in bake_passes:
		bake_pass.compute()
	debug()


## TODO Reposition the added mesh surface
func update() -> void:
	#_compute_shape()
	pass


#region Debug
func debug() -> void:
	var faces_buffer := rd.buffer_get_data(uniforms.faces_buffer)
	print_rich(
		"[color=gold]",
		"faces_buffer.face_count ", faces_buffer.decode_u32(0),
		" | faces_buffer.vertex_count ", faces_buffer.decode_u32(4),
		"\n[/color][color=cadet_blue]params.faces_table_size ", params.faces_table_size,
		" | params.faces_out_index_stride ", params.faces_out_index_stride,
		" | params.faces_out_vertex_count ", params.faces_out_vertex_count,
		" | params.faces_out_vertex_stride ", params.faces_out_vertex_stride,
		" | params.faces_out_color_offset ", params.faces_out_color_offset,
		"\nfaces_dedupe_dispatch_buffer: ",
		rd.buffer_get_data(uniforms.faces_dedupe_dispatch_buffer).to_int32_array(),
		" | faces_write_dispatch_buffer: ", rd.buffer_get_data(uniforms.faces_write_dispatch_buffer).to_int32_array(),
		"[/color]"
	)
	print_rich("[color=goldenrod]faces_buffer.faces[] int16: ", ComputeUtil.to_int16_array(faces_buffer.slice(8)), "[/color]")
	var table := rd.buffer_get_data(uniforms.faces_table_buffer)
	print_rich("[color=cadet_blue]table_buffer[", table.size() / 4, "] uint32: ", ComputeUtil.to_uint32_array(table), "[/color]")
	var slots := rd.buffer_get_data(uniforms.faces_slot_buffer)
	print_rich("[color=cadet_blue]slots_buffer[", slots.size() / 2, "] uint16: ", ComputeUtil.to_int16_array(slots), "[/color]")

	var index_buffer := RenderingServer.mesh_surface_get_index_buffer_rd_rid(mesh_rid, surface.idx)
	var indices := rd.buffer_get_data(index_buffer, 0, params.faces_out_index_count * params.faces_out_index_stride)

	var vertex_buffer := RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(mesh_rid, surface.idx)
	var positions := rd.buffer_get_data(vertex_buffer, 0, params.faces_out_vertex_count * params.faces_out_vertex_stride)
	print_rich(
		"[color=aqua]index_buffer[", indices.size() / 6, "]: ",
		ComputeUtil.to_vector3i_array(ComputeUtil.to_int16_array(indices)) , "[/color]",
		"\n[color=aqua]vertex_buffer[", params.faces_out_vertex_count, "]: ", positions.to_vector3_array(), "[/color]"
	)

	#var vertex_in_buffer := RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(mesh_rid, 0)
	#var positions_in := rd.buffer_get_data(vertex_in_buffer, 0, params.in_vertex_count * params.in_vertex_stride)
	#print_rich(
		#"\n[color=green]vertex_in_buffer[", params.in_vertex_count, "]: ", positions_in.to_vector3_array(), "[/color]"
	#)

	#print_rich(
		#"[color=peach_puff]",
		#" faces_dispatch=", rd.buffer_get_data(faces_dispatch_buffer, 0, 12).to_int32_array(),
		#" -> faces_count=", rd.buffer_get_data(faces_buffer, 0, 4).decode_u32(0),
		#"\n edges_dispatch=", rd.buffer_get_data(edges_dispatch_buffer, 0, 12).to_int32_array(),
		#" -> edges_count=", rd.buffer_get_data(edges_buffer, 0, 4).decode_u32(0),
		#"\n unique_count=", rd.buffer_get_data(slot_buffer, 0, 4).decode_u32(0),
		#"[/color]"
	#)
	pass
#endregion
