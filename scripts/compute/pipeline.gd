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
var bake_passes: Array[BlanketPass]
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

	bake_passes = [
		SelectPass.new(mesh, surface, params, sets),
		DedupePass.new(mesh, surface, params, sets),
		FacesPass.new(mesh, surface, params, sets),
		EdgesPass.new(mesh, surface, params, sets),
		OutMeshPass.new(mesh, surface, params, sets),
		ShrinkPass.new(mesh, surface, params, sets),
		FillPass.new(mesh, surface, params, sets),
		BoundaryResolvePass.new(mesh, surface, params, sets),
		BoundaryWritePass.new(mesh, surface, params, sets),
	]

	update_passes = [
		OffsetPass.new(mesh, surface, params, sets),
		SmoothPass.new(mesh, surface, params, sets),
		NormalsSumPass.new(mesh, surface, params, sets),
		NormalsWritePass.new(mesh, surface, params, sets),
	]


func bake() -> void:
	for bake_pass in bake_passes:
		bake_pass.compute()

	update()
	debug()


func update() -> void:
	for update_pass in update_passes:
		update_pass.compute()


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
		var at := SHARED_EDGE_OFFSET + i * EdgesPass.STRUCT_STRIDE
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


## Positions occupy the first block, packed normal+tangent the second
func dump_vertices(idx: int, name := "vertices") -> void:
	var buffer := RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(surface.mesh_rid, idx)
	var bytes := rd.buffer_get_data(buffer)
	var format := mesh.surface_get_format(idx)
	var count := mesh.surface_get_array_len(idx)
	var normal_offset := RenderingServer.mesh_surface_get_format_offset(format, count, Mesh.ARRAY_NORMAL)
	var normal_stride := RenderingServer.mesh_surface_get_format_normal_tangent_stride(format, count)

	for i in count:
		var position := Vector3(
			bytes.decode_float(i * 12),
			bytes.decode_float(i * 12 + 4),
			bytes.decode_float(i * 12 + 8)
		)
		var normal := BlanketUtil.read_normal(bytes, normal_offset + i * normal_stride)

		print_rich("[color=%s]%s[%d]: pos=%s n=%s[/color]" % [
			"tomato" if position == Vector3.ZERO else "goldenrod",
			name, i, position, normal
		])

func dump_boundary(name := "boundary") -> void:
	var bytes := rd.buffer_get_data(sets.boundary_buffer)
	var masks := rd.buffer_get_data(sets.face_edge_mask_buffer).to_int32_array()
	var stride := EdgesPass.BOUNDARY_EDGE_STRIDE
	var header := EdgesPass.BOUNDARY_HEADER
	var count := bytes.decode_u32(0)
	var capacity := (bytes.size() - header) / stride

	print_rich("[color=gold]%s[count=%d/%d rim_verts=%d][/color]" % [
		name, count, capacity, bytes.decode_u32(4)
	])

	for i in mini(count, capacity):
		var at := header + i * stride
		var verts := Vector2i(bytes.decode_u32(at), bytes.decode_u32(at + 4))
		var face := bytes.decode_u32(at + 8)
		var corner := bytes.decode_u32(at + 12)
		var mask: int = masks[face] if face < masks.size() else 0
		var top: Array[Vector2i] = []

		for arc in BlanketParams.TOP_VERTS:
			var top_at := at + 16 + arc * 8
			top.append(Vector2i(bytes.decode_u32(top_at), bytes.decode_u32(top_at + 4)))

		# Collapsed = the column's outer end is the apex itself, so the quad pinches
		var outer: Vector2i = top[BlanketParams.BEVEL_ARCS]
		var pinch := "x" if outer.x == verts.x else ""
		pinch += "y" if outer.y == verts.y else ""

		print_rich("[color=%s]  %d: verts=%s face=%d corner=%d mask=%s%s%s top=%s%s[/color]" % [
			"tomato" if pinch else "gold",
			i, verts, face, corner,
			"a" if mask & 1 else ".",
			"b" if mask & 2 else ".",
			"c" if mask & 4 else ".",
			top,
			" PINCH:%s" % pinch if pinch else "",
		])


func dump_normal_sums(from := 0, to := -1) -> void:
	var bytes := rd.buffer_get_data(sets.normals_sum_buffer)
	var sums := bytes.slice(0, params.out_vertex_count * 12).to_vector3_array()

	if to < 0:
		to = sums.size()

	for i in range(from, mini(to, sums.size())):
		var sum := sums[i]
		var length := sum.length()
		var block := "surf"

		if i >= params.wall_grid_base:
			block = "grid"
		elif i >= params.wall_rim_base:
			block = "rim"

		print_rich("[color=%s]sum[%d] %s len=%.5f up=%+.3f dir=%s[/color]" % [
			"tomato" if length < 1e-4 else "cornflower_blue",
			i, block, length,
			sum.normalized().dot(params.local_up) if length > 0.0 else 0.0,
			#sum.normalized() if length > 0.0 else Vector3.ZERO,
			sum
		])


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
	dump_vec3(vertex_buffer, "out_vertex_buffer")


func debug() -> void:
	prints(
		"params.out_vertex_count", params.out_vertex_count,
		"params.out_index_count", params.out_index_count,
		"params.out_index_stride", params.out_index_stride,
	)
	#dump_uvec3(sets.selected_index_buffer, "selected_index_buffer", true)
	#dump_vec3(sets.selected_vertex_buffer, "selected_vertex_buffer", true)
	#dump_faces()
	#dump_verts()
	#dump_vertices(1, "out_vertex")
	#dump_vert_faces(0)
	#dump_vert_faces(3)
	#dump_normal_sums()
	#dump_normal_sums()
#endregion
