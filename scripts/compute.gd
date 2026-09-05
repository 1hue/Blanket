extends RefCounted
class_name Compute

@warning_ignore("unused_signal")
signal output(message: String)

var rd: RenderingDevice
var params: ComputeParams
var sets: ComputeSets
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
	sets = ComputeSets.new(surface)
	params = ComputeParams.new(surface, global_transform)

	bake_passes = [
		FacesSelectPass.new(mesh, surface, params, sets),
		FacesDedupePass.new(mesh, surface, params, sets),
		FacesWritePass.new(mesh, surface, params, sets),
		#SharedEdgesPass.new(mesh, surface, params, sets),
		#BevelShrinkPass.new(mesh, surface, params, sets),
		#BevelFillPass.new(mesh, surface, params, sets),
		#SmoothSumPass.new(mesh, surface, params, sets),
		#SmoothWritePass.new(mesh, surface, params, sets),
		#NormalsSumPass.new(mesh, surface, params, sets),
		#NormalsWritePass.new(mesh, surface, params, sets),
		#ShapePass.new(mesh, surface, params, sets),
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
func debug_shared_edges() -> void:
	var shared_edges := rd.buffer_get_data(sets.shared_edge_buffer)
	var shared_edge_count := shared_edges.decode_u32(0)
	var shared_edges_struct: Array[Array] = []

	const SHARED_EDGE_OFFSET := 16

	for i in shared_edge_count:
		var at := SHARED_EDGE_OFFSET + i * SharedEdgesPass.STRUCT_STRIDE
		shared_edges_struct.append([
			Vector2i(shared_edges.decode_u32(at), shared_edges.decode_u32(at + 4)),
			Vector2i(shared_edges.decode_u32(at + 8), shared_edges.decode_u32(at + 12)),
			Vector2i(shared_edges.decode_u32(at + 16), shared_edges.decode_u32(at + 20)),
			Vector2i(shared_edges.decode_u32(at + 24), shared_edges.decode_u32(at + 28)),
		])

	print_rich("[color=gold]shared_edges[%s]: " % shared_edge_count, shared_edges_struct, "[/color]")


func dumpi(buffer: RID, name := "") -> void:
	var bytes := rd.buffer_get_data(buffer)
	print_rich("[color=burlywood]%s: " % name, bytes.to_int32_array() ,"[/color]")


func dump_uvec3(buffer: RID, name := "") -> void:
	const INDEX_STRIDE := 12
	var bytes := rd.buffer_get_data(buffer)
	var count := bytes.decode_u32(0)
	var capacity := (bytes.size() - 4) / INDEX_STRIDE
	var values: Array[Vector3i] = []
	values.resize(capacity)

	for i in capacity:
		var at := 4 + i * INDEX_STRIDE
		values[i] = Vector3i(bytes.decode_u32(at), bytes.decode_u32(at + 4), bytes.decode_u32(at + 8))

	print_rich("[color=light_sea_green]%s[count=%d/%d]: " % [name, count, capacity], values, "[/color]")


func dump_vec3(buffer: RID, name := "") -> void:
	var bytes := rd.buffer_get_data(buffer)
	var values := bytes.slice(4).to_vector3_array()
	print_rich("[color=goldenrod]%s[count=%d/%d]: " % [name, bytes.decode_u32(0), values.size()], values)


func dumpf(buffer: RID, name := "") -> void:
	var bytes := rd.buffer_get_data(buffer)
	print_rich("[color=burlywood]%s: " % name, bytes.to_float32_array() ,"[/color]")


func debug_faces_multipass() -> void:
	prints(
		#"params.max_shared_edges:", params.max_shared_edges,
		"params.in_face_count:", params.in_face_count,
		"params.bevel_arcs:", params.bevel_arcs,
		"params.bevel_segments:", params.bevel_segments,
		"params.out_vertex_count:", params.out_vertex_count,
		"params.out_attribute_stride", params.out_attribute_stride,
	)

	dump_uvec3(sets.index_scratch_buffer, "index_scratch_buffer")
	dump_vec3(sets.vertex_scratch_buffer, "vertex_scratch_buffer")


func debug() -> void:
	debug_faces_multipass()
	#print_rich("[color=goldenrod]faces_buffer.faces[] int16: ", ComputeUtil.to_int16_array(faces_buffer.slice(8)), "[/color]")
	#var table := rd.buffer_get_data(uniforms.faces_table_buffer)
	#print_rich("[color=cadet_blue]table_buffer[", table.size() / 4, "] uint32: ", ComputeUtil.to_uint32_array(table), "[/color]")
	#var slots := rd.buffer_get_data(uniforms.faces_slot_buffer)
	#print_rich("[color=cadet_blue]slots_buffer[", slots.size() / 2, "] uint16: ", ComputeUtil.to_int16_array(slots), "[/color]")

	#var attr_buffer := RenderingServer.mesh_surface_get_attribute_buffer_rd_rid(mesh_rid, surface.idx)
	#var attrs := rd.buffer_get_data(attr_buffer)
	#print_rich(
		#"[color=aqua]attr_buffer[%s]: " % attrs.size(), attrs, "[/color]"
	#)

	#var index_buffer := RenderingServer.mesh_surface_get_index_buffer_rd_rid(mesh_rid, surface.idx)
	#var indices := rd.buffer_get_data(index_buffer, 0, params.out_index_count * params.out_index_stride)
	#print_rich(
		#"[color=aqua]index_buffer[out_index_count=", params.out_index_count, "]: ", ComputeUtil.to_vector3i_array(ComputeUtil.to_int16_array(indices)), "[/color]"
	#)
##
	#var vertex_buffer := RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(mesh_rid, surface.idx)
	#var positions := rd.buffer_get_data(vertex_buffer, 0, params.out_vertex_count * params.out_vertex_stride)
	#print_rich(
		#"[color=gold]vertex_buffer[out_vertex_count=", params.out_vertex_count, "]: ", positions.to_vector3_array(), "[/color]"
	#)
	pass
#endregion
