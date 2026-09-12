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
		SharedEdgesPass.new(mesh, surface, params, sets),
		OutMeshPass.new(mesh, surface, params, sets),
		BevelShrinkPass.new(mesh, surface, params, sets),
		BevelFillPass.new(mesh, surface, params, sets),
		BoundaryPass.new(mesh, surface, params, sets),
		OffsetPass.new(mesh, surface, params, sets),
		NormalsSumPass.new(mesh, surface, params, sets),
		NormalsWritePass.new(mesh, surface, params, sets),
		#SmoothSumPass.new(mesh, surface, params, sets),
		#SmoothWritePass.new(mesh, surface, params, sets),
	]


func bake() -> void:
	for bake_pass in bake_passes:
		bake_pass.compute()
	debug()


func update() -> void:
	var offset_pass := find_pass(OffsetPass)

	if offset_pass:
		offset_pass.compute()


func find_pass(type: Variant) -> ComputePass:
	for bake_pass in bake_passes:
		if is_instance_of(bake_pass, type):
			return bake_pass

	return null

#region Debug
func dump_shared_mask(buffer: RID, name := "shared_mask") -> void:
	var bytes := rd.buffer_get_data(buffer)
	var words := bytes.to_int32_array()
	var labels: Array[String] = []

	for i in mini(words.size(), params.in_face_count):
		labels.append("%d:%s%s%s" % [
			i,
			"a" if words[i] & 1 else ".",
			"b" if words[i] & 2 else ".",
			"c" if words[i] & 4 else ".",
		])

	print_rich("[color=orchid]%s[%d]: " % [name, labels.size()], " ".join(labels), "[/color]")


func dump_vertex_flags(buffer: RID, name := "vertex_flags") -> void:
	var bytes := rd.buffer_get_data(buffer)
	var words := bytes.to_int32_array()
	var anchored: Array[int] = []

	for i in words.size():
		if words[i] & 1:
			anchored.append(i)

	print_rich("[color=orchid]%s[anchored=%d]: " % [name, anchored.size()], anchored, "[/color]")

func debug_shared_edges() -> void:
	var shared_edges := rd.buffer_get_data(sets.shared_edge_buffer)
	var shared_edge_count := shared_edges.decode_u32(0)
	var shared_edges_struct: Array[Array] = []

	const SHARED_EDGE_OFFSET := 4

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


func dump_uvec3(buffer: RID, name := "", has_count := false) -> void:
	const INDEX_STRIDE := 12
	var bytes := rd.buffer_get_data(buffer)
	var offset := 4 if has_count else 0
	var capacity := (bytes.size() - offset) / INDEX_STRIDE
	var values: Array[Vector3i] = []
	values.resize(capacity)

	for i in capacity:
		var at := offset + i * INDEX_STRIDE
		values[i] = Vector3i(bytes.decode_u32(at), bytes.decode_u32(at + 4), bytes.decode_u32(at + 8))

	var label := "%s[count=%d/%d]" % [name, bytes.decode_u32(0), capacity] if has_count else "%s[%d]" % [name, capacity]
	print_rich("[color=light_sea_green]%s: " % label, values, "[/color]")


func dump_u16vec3(buffer: RID, name := "", has_count := false) -> void:
	const STRIDE := 6
	var bytes := rd.buffer_get_data(buffer)
	var offset := 4 if has_count else 0
	var capacity := (bytes.size() - offset) / STRIDE
	var values: Array[Vector3i] = []
	values.resize(capacity)

	for i in capacity:
		var at := offset + i * STRIDE
		values[i] = Vector3i(bytes.decode_u16(at), bytes.decode_u16(at + 2), bytes.decode_u16(at + 4))

	var label := "%s[count=%d/%d]" % [name, bytes.decode_u32(0), capacity] if has_count else "%s[%d]" % [name, capacity]
	print_rich("[color=light_sea_green]%s: " % label, values, "[/color]")


func dump_vec3(buffer: RID, name := "", has_count := false) -> void:
	var bytes := rd.buffer_get_data(buffer)
	var offset := 4 if has_count else 0
	var capacity := (bytes.size() - offset) / 12
	var values := bytes.slice(offset, offset + capacity * 12).to_vector3_array()
	var label := "%s[count=%d/%d]" % [name, bytes.decode_u32(0), capacity] if has_count else "%s[%d]" % [name, capacity]
	print_rich("[color=goldenrod]%s: " % label, values)


func dump_attributes(buffer: RID, name := "") -> void:
	var bytes := rd.buffer_get_data(buffer)
	var stride: int = params.out_attribute_stride
	var count := bytes.size() / stride

	for i in count:
		var base := i * stride
		var color := bytes.decode_u32(base + params.out_color_offset)
		var w := bytes.decode_float(base + params.out_custom_offset + 12)

		print_rich("[color=goldenrod]%s[%d]: color=%08X anchor=%.0f" % [name, i, color, w])


func dumpf(buffer: RID, name := "") -> void:
	var bytes := rd.buffer_get_data(buffer)
	print_rich("[color=burlywood]%s: " % name, bytes.to_float32_array() ,"[/color]")


func debug_faces_multipass() -> void:
	dump_uvec3(sets.selected_index_buffer, "selected_index_buffer", true)
	dump_vec3(sets.selected_vertex_buffer, "selected_vertex_buffer", true)


func dump_edge_debug() -> void:
	var bytes := rd.buffer_get_data(sets.debug_buffer)
	var words := bytes.to_int32_array()

	for i in params.in_face_count * 3:
		var at := i * 4
		if words[at + 3] == 0:
			continue
		print_rich("[color=orchid]f%d c%d: twin=%d creased=%d shared=%d" % [
			i / 3, i % 3, words[at], words[at + 1], words[at + 2]
		])


func debug_out_mesh() -> void:
	var vertex_buffer := RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(mesh_rid, surface.idx)
	var index_buffer := RenderingServer.mesh_surface_get_index_buffer_rd_rid(mesh_rid, surface.idx)
	var attr_buffer := RenderingServer.mesh_surface_get_attribute_buffer_rd_rid(mesh_rid, surface.idx)

	prints(
		"params.in_face_count:", params.in_face_count,
		"params.bevel_arcs:", params.bevel_arcs,
		"params.bevel_segments:", params.bevel_segments,
		"params.out_index_count:", params.out_index_count,
		"params.out_vertex_count:", params.out_vertex_count,
		"params.out_index_stride", params.out_index_stride,
		"params.out_attribute_stride", params.out_attribute_stride,
	)
	dump_u16vec3(index_buffer, "index_buffer")
	dump_vec3(vertex_buffer, "vertex_buffer")
	#dump_attributes(attr_buffer, "attr_buffer")

func dump_boundary() -> void:
	var bytes := rd.buffer_get_data(sets.boundary_buffer)
	var count := bytes.decode_u32(0)

	const STRIDE := 16

	for i in count:
		var at := 4 + i * STRIDE
		var x := bytes.decode_u32(at)
		var y := bytes.decode_u32(at + 4)
		var face := bytes.decode_u32(at + 8)
		var corner := bytes.decode_u32(at + 12)
		var mask := rd.buffer_get_data(sets.face_edge_mask_buffer, face * 4, 4).decode_u32(0)
		var prev := (corner + 2) % 3
		var retracts: bool = (mask & (1 << prev)) != 0
		var top: int = params.selected_vertex_count + 3 * face + corner if retracts else x

		print_rich("[color=orchid]b%d: edge=(%d,%d) f%d c%d mask=%d prev=%d top_x=%d%s" % [
			i, x, y, face, corner, mask, prev, top, " (retracted)" if retracts else ""
		])


func dump_wall(name := "wall") -> void:
	var vertex_buffer := RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(mesh_rid, surface.idx)
	var index_buffer := RenderingServer.mesh_surface_get_index_buffer_rd_rid(mesh_rid, surface.idx)
	var verts := rd.buffer_get_data(vertex_buffer)
	var faces := rd.buffer_get_data(index_buffer)
	var boundary := rd.buffer_get_data(sets.boundary_buffer).decode_u32(0)

	print_rich("[color=orchid]%s: rim_base=%d arc_base=%d face_base=%d boundary=%d" % [
		name, params.wall_rim_base, params.wall_arc_base, params.wall_face_base, boundary
	])

	for i in boundary:
		for f in BoundaryPass.FACES:
			var face := params.wall_face_base + i * BoundaryPass.FACES + f
			var at := face * 6
			var tri := Vector3i(faces.decode_u16(at), faces.decode_u16(at + 2), faces.decode_u16(at + 4))
			var degenerate := tri.x == tri.y or tri.x == tri.z or tri.y == tri.z

			print_rich("[color=orchid]  b%d f%d: %s%s" % [i, f, tri, " DEGENERATE" if degenerate else ""])


func dump_vert(index: int, name := "vert") -> void:
	var vertex_buffer := RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(mesh_rid, surface.idx)
	var bytes := rd.buffer_get_data(vertex_buffer, index * 12, 12)

	print_rich("[color=orchid]%s[%d]: (%f, %f, %f)" % [
		name, index, bytes.decode_float(0), bytes.decode_float(4), bytes.decode_float(8)
	])


func debug() -> void:
	debug_faces_multipass()
	debug_shared_edges()
	dump_shared_mask(sets.face_edge_mask_buffer)
	dump_vertex_flags(sets.vertex_flag_buffer)
	dump_boundary()
	dump_wall()
	debug_out_mesh()
#endregion
