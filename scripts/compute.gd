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

var out_uniform_set: RID
var out_in_map_buffer: RID

var debug_buffer: RID
var debug_uniform_set: RID

var neighbour_buffer: RID
var neighbour_buffer_size: int
var neighbour_uniform_set: RID

var bevel_vertex_buffer: RID
var bevel_index_buffer: RID
var bevel_src_uniform_set: RID
var bevel_dst_uniform_set: RID

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
	uniforms = ComputeUniforms.new()

	_init_params(global_transform)
	#_init_debug()
	_init_indirect_dispatch()
	_init_selection_uniforms()
	_init_bevel_uniforms()
	_init_dedupe_uniforms()


func _init_params(global_transform: Transform3D) -> void:
	var format := mesh.surface_get_format(surface.source_idx)
	var primitive := mesh.surface_get_primitive_type(surface.source_idx)
	var vertex_count := mesh.surface_get_array_len(surface.source_idx)

	assert(primitive == Mesh.PRIMITIVE_TRIANGLES, "Mesh must be triangles: %s is primitibe type %s" % [mesh, primitive])
	assert(format & Mesh.ARRAY_FORMAT_NORMAL != 0, "Mesh must have normals: %s" % mesh)
	assert(format & Mesh.ARRAY_FORMAT_COLOR != 0, "Mesh must have vertex colors: %s" % mesh)

	params = ComputeParams.new()
	params.in_vertex_count = vertex_count
	params.in_vertex_stride = RenderingServer.mesh_surface_get_format_vertex_stride(format, vertex_count)
	params.in_index_count = mesh.surface_get_array_index_len(surface.source_idx)
	params.in_index_stride = RenderingServer.mesh_surface_get_format_index_stride(format, vertex_count)
	params.in_normal_offset = RenderingServer.mesh_surface_get_format_offset(format, vertex_count, Mesh.ARRAY_NORMAL)
	params.in_normal_stride = RenderingServer.mesh_surface_get_format_normal_tangent_stride(format, vertex_count)
	params.in_color_offset = RenderingServer.mesh_surface_get_format_offset(format, vertex_count, Mesh.ARRAY_COLOR)
	params.in_attribute_stride = RenderingServer.mesh_surface_get_format_attribute_stride(format, vertex_count)
	params.local_up = global_transform.basis.inverse() * Vector3.UP
	params.changed.connect(update)


func _init_debug() -> void:
	debug_buffer = rd.storage_buffer_create(4)
	debug_uniform_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([debug_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0)
	], SurfaceShaders.verts.shader, 3)


func bake() -> void:
	pass
	#_compute_bevel()
	#_compute_selection()
	#_compute_dedupe()
	#_allocate_verts_out()
	#_compute_verts()
	#debug()
	#_cleanup_bake()
	#update()


## Add an empty mesh surface
func _allocate_verts_out() -> void:
	# Only read the counts - avoid a whole GPU-CPU-GPU data roundtrip
	var unique_count := rd.buffer_get_data(slot_buffer, 0, 4).decode_u32(0)
	var edge_count := rd.buffer_get_data(edges_buffer, 0, 4).decode_u32(0)
	var face_count := rd.buffer_get_data(faces_buffer, 0, 4).decode_u32(0)
	assert(face_count > 0, "Face count: %d" % face_count)
	#assert(edge_count > 0, "Edge count: %d" % edge_count)

	var vertex_count := unique_count + edge_count * 4
	var index_count := face_count * 3 + edge_count * 6

	surface.allocate(vertex_count, index_count)

	var format := mesh.surface_get_format(surface.idx)
	params.out_vertex_count = vertex_count
	params.out_vertex_stride = RenderingServer.mesh_surface_get_format_vertex_stride(format, vertex_count)
	params.out_normal_offset = RenderingServer.mesh_surface_get_format_offset(format, vertex_count, Mesh.ARRAY_NORMAL)
	params.out_normal_stride = RenderingServer.mesh_surface_get_format_normal_tangent_stride(format, vertex_count)
	params.out_marker_offset = RenderingServer.mesh_surface_get_format_offset(format, vertex_count, Mesh.ARRAY_CUSTOM0)
	params.out_attribute_stride = RenderingServer.mesh_surface_get_format_attribute_stride(format, vertex_count)
	params.out_index_stride = RenderingServer.mesh_surface_get_format_index_stride(format, vertex_count)

	_init_verts_out_uniforms(vertex_count)


## Prepare buffers for verts.glsl
func _init_verts_out_uniforms(vertex_count: int) -> void:
	if out_uniform_set.is_valid():
		rd.free_rid(out_uniform_set)
	if out_in_map_buffer.is_valid():
		rd.free_rid(out_in_map_buffer)

	var out_vertex_buffer := RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(mesh_rid, surface.idx)
	var out_index_buffer := RenderingServer.mesh_surface_get_index_buffer_rd_rid(mesh_rid, surface.idx)
	var out_attribute_buffer := RenderingServer.mesh_surface_get_attribute_buffer_rd_rid(mesh_rid, surface.idx)
	out_in_map_buffer = rd.storage_buffer_create(vertex_count * 4)

	out_uniform_set = rd.uniform_set_create([
		ComputeUtil.create_uniform([out_vertex_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0),
		ComputeUtil.create_uniform([out_index_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 1),
		ComputeUtil.create_uniform([out_attribute_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 2),
		ComputeUtil.create_uniform([out_in_map_buffer], RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 3)
	], SurfaceShaders.verts.shader, 2)


## Dispatch verts.glsl to fill the empty mesh surface GPU-side
func _compute_verts() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.verts.pipeline)
	rd.compute_list_set_push_constant(compute_list, params.pack_verts(), ComputeParams.SIZE_VERTS)
	rd.compute_list_bind_uniform_set(compute_list, in_uniform_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, selection_uniform_set, 1)
	rd.compute_list_bind_uniform_set(compute_list, out_uniform_set, 2)
	rd.compute_list_bind_uniform_set(compute_list, dedupe_uniform_set, 3)
	rd.compute_list_dispatch_indirect(compute_list, edges_dispatch_buffer, 0)
	rd.compute_list_end()


## Dispatch shape.glsl to reposition the spawned mesh surface
func _compute_shape() -> void:
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, SurfaceShaders.shape.pipeline)
	rd.compute_list_set_push_constant(compute_list, params.pack_shape(), ComputeParams.SIZE_SHAPE)
	rd.compute_list_bind_uniform_set(compute_list, in_uniform_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, out_uniform_set, 2)
	rd.compute_list_dispatch(compute_list, ceili(params.out_vertex_count / 256.0), 1, 1)
	rd.compute_list_end()


## Reposition the added mesh surface
func update() -> void:
	#_compute_shape()
	pass


func debug() -> void:
	#var data := RenderingServer.mesh_get_surface(mesh_rid, surface.source_idx)
	#print_rich("[color=rosy_brown]", data, "[/color]")
	#var vertex_data: PackedByteArray = data.vertex_data
	#print_rich("[color=pale_green]", data.vertex_count, " source verts:\n", vertex_data.to_vector3_array(), "[/color]\n")

	var faces := rd.buffer_get_data(faces_buffer, FACES_HEADER, faces_buffer_size - FACES_HEADER)
	print_rich("[color=pale_green] faces:", ComputeUtil.to_vector3i_array(faces.to_int32_array()), "[/color]")

	var edges := rd.buffer_get_data(edges_buffer, EDGES_HEADER, edges_buffer_size - EDGES_HEADER)
	print_rich("[color=pale_green] edges:", ComputeUtil.to_vector2i_array(edges), "[/color]")

	print_rich(
		"[color=peach_puff]",
		" faces_dispatch=", rd.buffer_get_data(faces_dispatch_buffer, 0, 12).to_int32_array(),
		" -> faces_count=", rd.buffer_get_data(faces_buffer, 0, 4).decode_u32(0),
		"\n edges_dispatch=", rd.buffer_get_data(edges_dispatch_buffer, 0, 12).to_int32_array(),
		" -> edges_count=", rd.buffer_get_data(edges_buffer, 0, 4).decode_u32(0),
		"\n unique_count=", rd.buffer_get_data(slot_buffer, 0, 4).decode_u32(0),
		"[/color]"
	)

	print_rich("[color=khaki] out_vertex_count=", params.out_vertex_count,
	" out_vertex_stride=", params.out_vertex_stride,
	" out_normal_offset=", params.out_normal_offset,
	" out_normal_stride=", params.out_normal_stride,
	" out_marker_offset=", params.out_marker_offset,
	" out_attribute_stride=", params.out_attribute_stride,
	" out_index_stride=", params.out_index_stride,
	"[/color]")

	print_rich("[color=khaki] in_vertex_count=", params.in_vertex_count,
	" in_vertex_stride=", params.in_vertex_stride,
	" in_normal_offset=", params.in_normal_offset,
	" in_normal_stride=", params.in_normal_stride,
	" in_attribute_stride=", params.in_attribute_stride,
	" in_index_stride=", params.in_index_stride,
	"[/color]")

	var out_verts := rd.buffer_get_data(RenderingServer.mesh_surface_get_vertex_buffer_rd_rid(mesh_rid, surface.idx))
	var out_idx := rd.buffer_get_data(RenderingServer.mesh_surface_get_index_buffer_rd_rid(mesh_rid, surface.idx))
	print_rich(
		"[color=pale_green] out verts:\n", out_verts.slice(0, params.out_vertex_count * params.out_vertex_stride).to_vector3_array(), "[/color]")
	print_rich(
		"[color=pale_green] out indices:\n", ComputeUtil.to_int16_array(out_idx), "[/color]")

	#var out_map_data := rd.buffer_get_data(out_in_map_buffer).to_int32_array()
	#var out_positions := out_data.slice(0, params.out_vertex_count * params.out_vertex_stride).to_float32_array()

	#for i in params.out_vertex_count:
		#var p := Vector3(out_positions[i*3], out_positions[i*3+1], out_positions[i*3+2])
		#print("out[%d] in=%d pos=%s" % [i, out_map_data[i], p])


func _notification(what) -> void:
	if what != NOTIFICATION_PREDELETE:
		return

	for rid in [
		faces_dispatch_uniform_set, faces_dispatch_buffer, edges_dispatch_uniform_set, edges_dispatch_buffer,
		in_uniform_set, selection_uniform_set, faces_buffer, edges_buffer, out_uniform_set, out_in_map_buffer,
		debug_uniform_set, debug_buffer,
		dedupe_uniform_set, slot_buffer, used_buffer,
	]:
		if rid.is_valid():
			rd.free_rid(rid)
