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

var bake_workers: Array[ComputeWorker]


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

	bake_workers = [
		BevelShrink.new(mesh, surface, params, uniforms),
		BevelFill.new(mesh, surface, params, uniforms),
	]

	bake()


func bake() -> void:
	for bake_worker in bake_workers:
		bake_worker.compute()


## TODO Reposition the added mesh surface
func update() -> void:
	#_compute_shape()
	pass


#region Debug
#func _init_debug() -> void:
	#debug_buffer = rd.storage_buffer_create(4)
	#debug_uniform_set = rd.uniform_set_create([
		#ComputeUtil.create_uniform([debug_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0)
	#], SurfaceShaders.verts.shader, 3)


#func debug() -> void:
	##var data := RenderingServer.mesh_get_surface(mesh_rid, surface.source_idx)
	##print_rich("[color=rosy_brown]", data, "[/color]")
	##var vertex_data: PackedByteArray = data.vertex_data
	##print_rich("[color=pale_green]", data.vertex_count, " source verts:\n", vertex_data.to_vector3_array(), "[/color]\n")
#
	#var faces := rd.buffer_get_data(faces_buffer, FACES_HEADER, faces_buffer_size - FACES_HEADER)
	#print_rich("[color=pale_green] faces:", ComputeUtil.to_vector3i_array(faces.to_int32_array()), "[/color]")
#
	#var edges := rd.buffer_get_data(edges_buffer, EDGES_HEADER, edges_buffer_size - EDGES_HEADER)
	#print_rich("[color=pale_green] edges:", ComputeUtil.to_vector2i_array(edges), "[/color]")
#
	#print_rich(
		#"[color=peach_puff]",
		#" faces_dispatch=", rd.buffer_get_data(faces_dispatch_buffer, 0, 12).to_int32_array(),
		#" -> faces_count=", rd.buffer_get_data(faces_buffer, 0, 4).decode_u32(0),
		#"\n edges_dispatch=", rd.buffer_get_data(edges_dispatch_buffer, 0, 12).to_int32_array(),
		#" -> edges_count=", rd.buffer_get_data(edges_buffer, 0, 4).decode_u32(0),
		#"\n unique_count=", rd.buffer_get_data(slot_buffer, 0, 4).decode_u32(0),
		#"[/color]"
	#)
#
	#print_rich("[color=khaki] out_vertex_count=", params.out_vertex_count,
	#" out_vertex_stride=", params.out_vertex_stride,
	#" out_normal_offset=", params.out_normal_offset,
	#" out_normal_stride=", params.out_normal_stride,
	#" out_marker_offset=", params.out_marker_offset,
	#" out_attribute_stride=", params.out_attribute_stride,
	#" out_index_stride=", params.out_index_stride,
	#"[/color]")
#
	#print_rich("[color=khaki] in_vertex_count=", params.in_vertex_count,
	#" in_vertex_stride=", params.in_vertex_stride,
	#" in_normal_offset=", params.in_normal_offset,
	#" in_normal_stride=", params.in_normal_stride,
	#" in_attribute_stride=", params.in_attribute_stride,
	#" in_index_stride=", params.in_index_stride,
	#"[/color]")
#
	#var out_verts := rd.buffer_get_data(RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(mesh_rid, surface.idx))
	#var out_idx := rd.buffer_get_data(RenderingServer.mesh_surface_get_index_buffer_rd_rid(mesh_rid, surface.idx))
	#print_rich(
		#"[color=pale_green] out verts:\n", out_verts.slice(0, params.out_vertex_count * params.out_vertex_stride).to_vector3_array(), "[/color]")
	#print_rich(
		#"[color=pale_green] out indices:\n", ComputeUtil.to_int16_array(out_idx), "[/color]")
#
	##var out_map_data := rd.buffer_get_data(out_in_map_buffer).to_int32_array()
	##var out_positions := out_data.slice(0, params.out_vertex_count * params.out_vertex_stride).to_float32_array()
#
	##for i in params.out_vertex_count:
		##var p := Vector3(out_positions[i*3], out_positions[i*3+1], out_positions[i*3+2])
		##print("out[%d] in=%d pos=%s" % [i, out_map_data[i], p])
#endregion
