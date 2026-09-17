## Collection of compute passes per mesh surface.
extends RefCounted
class_name BlanketPipeline

var mesh: ArrayMesh
var mesh_rid: RID:
	get: return mesh.get_rid()
var rd: RenderingDevice
var params: BlanketParams
var sets: BlanketSets
var surface: BlanketSurface
var select_passes: Array[BlanketPass]
var build_passes: Array[BlanketPass]
var update_passes: Array[BlanketPass]


func _init(p_mesh: ArrayMesh, surface_idx: int, global_transform: Transform3D) -> void:
	rd = RenderingServer.get_rendering_device()
	assert(rd != null, "No RenderingDevice - compute shaders require Forward+ or Mobile renderer")
	assert(BlanketShaders is Node, "BlanketShaders autoload missing - check Project Settings > Autoload")
	assert(p_mesh != null, "Mesh is null")
	assert(surface_idx >= 0 and surface_idx < p_mesh.get_surface_count(),
		"Surface %d out of range on %s (%d surfaces)" % [surface_idx, p_mesh, p_mesh.get_surface_count()])

	mesh = p_mesh
	surface = BlanketSurface.new(p_mesh, surface_idx)
	sets = BlanketSets.new(surface)
	params = BlanketParams.new(surface, global_transform)

	select_passes = [
		SelectPass.new(mesh, surface, params, sets),
		DedupePass.new(mesh, surface, params, sets),
		FacesPass.new(mesh, surface, params, sets),
		EdgesPass.new(mesh, surface, params, sets),
		OutMeshPass.new(mesh, surface, params, sets),
	]

	build_passes = [
		ShrinkPass.new(mesh, surface, params, sets),
		FillPass.new(mesh, surface, params, sets),
		#BoundaryResolvePass.new(mesh, surface, params, sets),
		#BoundaryWritePass.new(mesh, surface, params, sets),
	]

	update_passes = [
		OffsetPass.new(mesh, surface, params, sets),
		#SmoothPass.new(mesh, surface, params, sets),
		#NormalsSumPass.new(mesh, surface, params, sets),
		#NormalsWritePass.new(mesh, surface, params, sets),
	]


func bake() -> void:
	for select_pass in select_passes:
		select_pass.compute()

	if params.is_out_mesh_empty:
		return

	for build_pass in build_passes:
		build_pass.compute()

	#update()


func update() -> void:
	if params.is_out_mesh_empty:
		return

	for update_pass in update_passes:
		update_pass.compute()

	debug()


#region Debug
func dumpi(buffer: RID, name := "") -> void:
	var bytes := rd.buffer_get_data(buffer)
	print_rich("[color=burlywood]%s: " % name, bytes.to_int32_array() ,"[/color]")


func dumpf(buffer: RID, name := "") -> void:
	var bytes := rd.buffer_get_data(buffer)
	print_rich("[color=burlywood]%s: " % name, bytes.to_float32_array() ,"[/color]")


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


func dump_attributes() -> void:
	var buffer := RenderingServer.mesh_surface_get_attribute_buffer_rd_rid(surface.mesh_rid, surface.idx)
	var bytes := rd.buffer_get_data(buffer)
	var stride: int = params.out_attribute_stride
	var count := bytes.size() / stride

	for i in count:
		var base := i * stride
		var color := bytes.decode_u32(base + params.out_color_offset)
		var w := bytes.decode_float(base + params.out_custom_offset + 12)

		print_rich("[color=goldenrod]attributes[%d]: color=%08X anchor=%.0f" % [i, color, w])


func dump_vert_faces(vert: int) -> void:
	var index_buffer := RenderingServer.mesh_surface_get_index_buffer_rd_rid(surface.mesh_rid, surface.idx)
	var vertex_buffer := RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(surface.mesh_rid, surface.idx)
	var indices := rd.buffer_get_data(index_buffer)
	var positions := rd.buffer_get_data(vertex_buffer).slice(0, params.out_vertex_count * 12).to_vector3_array()

	for face in params.out_face_count:
		var at := face * 6
		var tri := Vector3i(indices.decode_u16(at), indices.decode_u16(at + 2), indices.decode_u16(at + 4))

		if vert != tri.x and vert != tri.y and vert != tri.z:
			continue

		var a := positions[tri.x]
		var b := positions[tri.y]
		var c := positions[tri.z]
		var normal := (c - a).cross(b - a)
		var area := normal.length()

		if area < 1e-12:
			continue

		normal /= area
		var up := normal.dot(params.local_up)
		var weight := maxf(up, 0.0) if vert < params.wall_rim_base else maxf(1.0 - absf(up), 0.0)

		print_rich("[color=khaki]  face=%d %s n=%s inverse=%s up=%+.3f w=%.3f[/color]" %
			[face, tri, normal, normal.inverse(), up, weight])


func dump_faces() -> void:
	var index_buffer := RenderingServer.mesh_surface_get_index_buffer_rd_rid(surface.mesh_rid, surface.idx)
	dump_u16vec3(index_buffer, "out_index_buffer")


func dump_verts() -> void:
	var vertex_buffer := RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(surface.mesh_rid, surface.idx)
	var bytes := rd.buffer_get_data(vertex_buffer, 0, params.out_vertex_count * params.out_vertex_stride)

	print_rich("[color=goldenrod]vertex_buffer: ", bytes.to_vector3_array())


func dump_shared_mask(buffer: RID, name := "shared_mask") -> void:
	var bytes := rd.buffer_get_data(buffer)
	var words := bytes.to_int32_array()
	var labels: Array[String] = []

	for i in mini(words.size(), params.in_face_count):
		labels.append("%d:%s%s%s|%s%s%s" % [
			i,
			"a" if words[i] & 1 else ".",
			"b" if words[i] & 2 else ".",
			"c" if words[i] & 4 else ".",
			"A" if words[i] & 8 else ".",
			"B" if words[i] & 16 else ".",
			"C" if words[i] & 32 else ".",
		])

	print_rich("[color=orchid]%s[%d]: " % [name, labels.size()], " ".join(labels), "[/color]")


func debug_shared_edges() -> void:
	var bytes := rd.buffer_get_data(sets.shared_edge_buffer)
	var count := bytes.decode_u32(0)
	var stride := EdgesPass.SHARED_EDGE_STRIDE

	print_rich("[color=gold]shared_edges[count=%d][/color]" % count)

	for i in mini(count, params.max_edges):
		var at := 4 + i * stride

		print_rich("[color=gold]  %d: faces=%s apexes=%s retracted=[%s, %s] crease=%d[/color]" % [
			i,
			Vector2i(bytes.decode_u32(at), bytes.decode_u32(at + 4)),
			Vector2i(bytes.decode_u32(at + 8), bytes.decode_u32(at + 12)),
			Vector2i(bytes.decode_u32(at + 16), bytes.decode_u32(at + 20)),
			Vector2i(bytes.decode_u32(at + 24), bytes.decode_u32(at + 28)),
			bytes.decode_u32(at + 32),
		])


func dump_face_edges() -> void:
	var bytes := rd.buffer_get_data(sets.face_edge_buffer)

	for face in params.in_face_count:
		var parts: Array[String] = []

		for corner in 3:
			var at := (face * 3 + corner) * 8
			var twin := bytes.decode_u32(at)
			var creased := bytes.decode_u32(at + 4)

			parts.append("%s%s" % [
				"-" if twin == 0 else str(twin - 1),
				"c" if creased else "."
			])

		print_rich("[color=orchid]face_edge[%d]: %s[/color]" % [face, " ".join(parts)])


func dump_merged_slots() -> void:
	var edges := rd.buffer_get_data(sets.face_edge_buffer)
	var index_buffer := RenderingServer.mesh_surface_get_index_buffer_rd_rid(surface.mesh_rid, surface.idx)
	var indices := rd.buffer_get_data(index_buffer)
	var sel_verts := rd.buffer_get_data(sets.selected_vertex_buffer).decode_u32(0)
	var faces := rd.buffer_get_data(sets.selected_index_buffer)
	var face_count := faces.decode_u32(0)

	for face in face_count:
		var parts: Array[String] = []

		for corner in 3:
			var at := (face * 3 + corner) * 8
			var twin := edges.decode_u32(at)
			var creased := edges.decode_u32(at + 4)
			var own := sel_verts + 3 * face + corner
			var slot := own

			if twin != 0 and creased == 0:
				var twin_corner: int = twin - 1
				var twin_face: int = twin_corner / 3

				if twin_face < face:
					slot = sel_verts + 3 * twin_face + (twin_corner % 3 + 1) % 3

			parts.append("c%d:own=%d->%d" % [corner, own, slot])

		var tri_at := face * 6
		var written := Vector3i(
			indices.decode_u16(tri_at), indices.decode_u16(tri_at + 2), indices.decode_u16(tri_at + 4)
		)

		print_rich("[color=orchid]face %d: %s written=%s[/color]" % [face, " ".join(parts), written])


func debug() -> void:
	#prints(
		#"params.out_vertex_count", params.out_vertex_count,
		#"params.out_index_count", params.out_index_count,
		#"params.out_face_count", params.out_face_count,
		#"params.out_index_stride", params.out_index_stride,
		#"params.wall_rim_base", params.wall_rim_base
	#)
	pass
#endregion
