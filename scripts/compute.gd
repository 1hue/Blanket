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
	prints(
		"params.faces_table_size", params.faces_table_size,
		"face_count", faces_buffer.decode_u32(0),
		"params.out_index_stride", params.out_index_stride,
		"params.out_vertex_count", params.out_vertex_count,
		"params.out_vertex_stride", params.out_vertex_stride,
		"params.out_color_offset", params.out_color_offset,
		"params.out_normal_offset", params.out_normal_offset,
		"dispatch:",
		rd.buffer_get_data(uniforms.faces_dedupe_dispatch_buffer).to_int32_array(),
		rd.buffer_get_data(uniforms.faces_write_dispatch_buffer).to_int32_array()
	)
	#var table := rd.buffer_get_data(uniforms.faces_table_buffer)
	#print_rich("[color=aqua]table[", table.size() / 4, "]: ", ComputeUtil.to_uint32_array(table), "[/color]")
	#var slots := rd.buffer_get_data(uniforms.faces_slot_buffer)
	#print_rich("[color=aqua]slots[", slots.size() / 2, "] uint16: ", ComputeUtil.to_int16_array(slots), "[/color]")

	var vertex_buffer := RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(mesh_rid, surface.idx)
	var index_buffer := RenderingServer.mesh_surface_get_index_buffer_rd_rid(mesh_rid, surface.idx)
	var indices := rd.buffer_get_data(index_buffer)
	var positions := rd.buffer_get_data(vertex_buffer).slice(0, params.out_vertex_count * params.out_vertex_stride)
	print_rich(
		"[color=aqua]index_buffer[", indices.size() / 6, "]: ",
		ComputeUtil.to_vector3i_array(ComputeUtil.to_int16_array(indices)) , "[/color]",
		"\n[color=aqua]verts[", positions.size(), "]: ", positions.to_vector3_array(), "[/color]"
	)

	#print_rich(
		#"[color=peach_puff]",
		#" faces_dispatch=", rd.buffer_get_data(faces_dispatch_buffer, 0, 12).to_int32_array(),
		#" -> faces_count=", rd.buffer_get_data(faces_buffer, 0, 4).decode_u32(0),
		#"\n edges_dispatch=", rd.buffer_get_data(edges_dispatch_buffer, 0, 12).to_int32_array(),
		#" -> edges_count=", rd.buffer_get_data(edges_buffer, 0, 4).decode_u32(0),
		#"\n unique_count=", rd.buffer_get_data(slot_buffer, 0, 4).decode_u32(0),
		#"[/color]"
	#)

	#print_rich("[color=khaki] out_vertex_count=", params.bevel_vertex_count,
	#" out_vertex_stride=", params.bevel_vertex_stride,
	#" out_normal_offset=", params.bevel_normal_offset,
	#" out_normal_stride=", params.bevel_normal_stride,
	#" out_marker_offset=", params.bevel_marker_offset,
	#" out_attribute_stride=", params.bevel_attribute_stride,
	#" out_index_stride=", params.bevel_index_stride,
	#"[/color]")
#
	#var out_verts := rd.buffer_get_data(RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(mesh_rid, surface.idx))
	#var out_idx := rd.buffer_get_data(RenderingServer.mesh_surface_get_index_buffer_rd_rid(mesh_rid, surface.idx))
	#print_rich(
		#"[color=pale_green] indices:\n", ComputeUtil.to_int16_array(out_idx), "[/color]")
	#print_rich(
		#"[color=pale_green] verts:\n", out_verts.slice(0, params.bevel_vertex_count * params.bevel_vertex_stride).to_vector3_array(), "[/color]")

	#var out_map_data := rd.buffer_get_data(out_in_map_buffer).to_int32_array()
	#var out_positions := out_data.slice(0, params.out_vertex_count * params.out_vertex_stride).to_float32_array()

	#for i in params.out_vertex_count:
		#var p := Vector3(out_positions[i*3], out_positions[i*3+1], out_positions[i*3+2])
		#print("out[%d] in=%d pos=%s" % [i, out_map_data[i], p])
	pass
#endregion
