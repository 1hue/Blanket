## Covers one mesh
##
## Add this under a [MeshInstance3D] and it grows a layer of cover over every surface facing upward.
## [Blanket] adds these across a whole scene - place one by hand when a mesh needs its own depth or material.
@icon("res://assets/blanket_instance.svg")
extends Node3D
class_name BlanketInstance

## Joined on enter, so a Blanket above can find us without a tree walk
const GROUP = &"blanket_instances"
const EPSILON = 0.0001
const MIN_REBAKE_DELAY = 0.03
const DEFAULT_MATERIAL: ShaderMaterial = preload("res://addons/blanket/materials/snow.tres")

@export var material: Material = DEFAULT_MATERIAL
@export_range(0, 3, 0.05, "or_greater") var depth := BlanketParams.DEFAULT_DEPTH:
	set(value):
		depth = value
		set_process(not is_equal_approx(depth, current_depth))
## How quickly the layer settles toward [member depth]
@export_range(0.1, 20.0, 0.1, "or_greater") var settle_rate := 6.0
## How far a face may tilt from up and still get covered. 90 includes vertical walls
@export_range(0.0, 90.0, 1.0, "degrees") var max_slope_degrees := BlanketParams.DEFAULT_MAX_SLOPE_DEGREES:
	set(value):
		max_slope_degrees = value
		queue_rebake()
## Rotating or scaling a mesh moves which faces point up, so the selection needs rebuilding
@export var rebake_on_transform := true:
	set(value):
		rebake_on_transform = value
		prev_basis = current_basis()
## Quiet time before a rebake - dragging a rotation handle would otherwise rebake every frame
@export_range(0.03, 1.0, 0.01, "or_greater") var rebake_delay := 0.2:
	set(value):
		rebake_delay = maxf(value, MIN_REBAKE_DELAY)

		if rebake_timer:
			rebake_timer.wait_time = rebake_delay

@export_group("Debug", "debug")
@export_subgroup("Normals", "debug_normals")
@export var debug_normals_enabled := false:
	set(value):
		debug_normals_enabled = value
		draw_normals.call_deferred()
@export_range(0, 2, 0.01, "or_greater", "prefer_slider") var debug_normals_length := 0.2:
	set(value):
		debug_normals_length = value
		draw_normals.call_deferred()
@export var debug_normals_color := Color.ORANGE_RED:
	set(value):
		debug_normals_color = value
		draw_normals.call_deferred()

@onready var mesh_instance: MeshInstance3D = $".."

var mesh: ArrayMesh:
	get: return mesh_instance.mesh as ArrayMesh if mesh_instance else null
var debug_normals_mesh: MeshInstance3D: set = set_debug_normals_mesh
var pipelines: Array[BlanketPipeline]
var current_depth := BlanketParams.DEFAULT_DEPTH
var prev_basis: Basis
var rebake_timer: Timer


## Triangles in an ArrayMesh only - primitives can't take the storage flag, and
## other topologies have no faces to select
static func is_supported(source: Mesh) -> bool:
	if source is not ArrayMesh:
		return false

	if source.get_surface_count() == 0:
		return false

	for i in source.get_surface_count():
		if source.surface_get_primitive_type(i) != Mesh.PRIMITIVE_TRIANGLES:
			return false

	return true


func _ready() -> void:
	set_notify_transform(true)

	rebake_timer = Timer.new()
	rebake_timer.one_shot = true
	rebake_timer.wait_time = rebake_delay
	rebake_timer.timeout.connect(rebake)
	add_child(rebake_timer)

	setup()


## Tree re-entry after a teardown. First time through, _ready hasn't run and mesh_instance is still null
func _enter_tree() -> void:
	add_to_group(GROUP)

	if is_node_ready():
		setup()


## Dropping the pipelines frees their RIDs through the RefCounted destructors
func _exit_tree() -> void:
	remove_from_group(GROUP)

	if mesh and mesh.changed.is_connected(on_mesh_changed):
		mesh.changed.disconnect(on_mesh_changed)

	debug_normals_mesh = null
	pipelines.clear()


## Fires on our own global transform, parent movement included. Translation leaves local_up
## alone, so the basis still needs checking
func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSFORM_CHANGED or not rebake_on_transform:
		return

	var next_basis := current_basis()

	if next_basis.is_equal_approx(prev_basis):
		return

	prev_basis = next_basis
	queue_rebake()


## Framerate-independent exponential ease - lerp alone would tie the curve to framerate
func _process(delta: float) -> void:
	if is_equal_approx(current_depth, depth):
		set_process(false)
		return

	current_depth = lerp(current_depth, depth, 1.0 - exp(-settle_rate * delta))

	if absf(depth - current_depth) < EPSILON:
		current_depth = depth

	apply_depth()


func setup() -> void:
	if not is_supported(mesh_instance.mesh):
		#push_warning("Blanket skipped %s - needs a triangle ArrayMesh" % mesh_instance.name)
		return

	convert_to_storage_buffer_mesh()

	if not has_normals():
		return

	mesh.changed.connect(on_mesh_changed)

	for i in mesh.get_surface_count():
		var pipeline := BlanketPipeline.new(mesh, i, mesh_instance.global_transform)

		pipeline.params.max_slope_degrees = max_slope_degrees
		pipelines.append(pipeline)

	for pipeline in pipelines:
		pipeline.bake()

	prev_basis = current_basis()
	apply_depth()


func has_normals() -> bool:
	for i in mesh.get_surface_count():
		if mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_NORMAL == 0:
			push_warning("Blanket skipped %s - surface %d has no normals" % [mesh_instance.name, i])
			return false

	return true


func queue_rebake() -> void:
	if rebake_timer:
		rebake_timer.start()


func apply_depth() -> void:
	for pipeline in pipelines:
		pipeline.params.depth = current_depth
		pipeline.update()

	draw_normals.call_deferred()


func rebake() -> void:
	for pipeline in pipelines:
		pipeline.params.local_up = mesh_instance.global_transform.basis.inverse() * Vector3.UP
		pipeline.params.max_slope_degrees = max_slope_degrees
		pipeline.params.depth = current_depth
		pipeline.bake()

	draw_normals.call_deferred()


func current_basis() -> Basis:
	return global_transform.basis if is_inside_tree() else Basis()


func on_mesh_changed() -> void:
	if material:
		for pipeline in pipelines:
			var idx := pipeline.surface.idx

			if idx > -1 and idx < mesh_instance.get_surface_override_material_count():
				mesh_instance.set_surface_override_material(idx, material)

	draw_normals.call_deferred()


func set_debug_normals_mesh(value: MeshInstance3D) -> void:
	if debug_normals_mesh:
		remove_child(debug_normals_mesh)
		debug_normals_mesh.queue_free()

	debug_normals_mesh = value

	if debug_normals_mesh:
		add_child(debug_normals_mesh)
		debug_normals_mesh.top_level = true


func draw_normals() -> void:
	if not is_inside_tree() or not is_node_ready():
		return

	debug_normals_mesh = null

	if not debug_normals_enabled:
		return

	debug_normals_mesh = build_normal_lines()


## Every computed surface into one mesh - surface.idx is where each landed
func build_normal_lines() -> MeshInstance3D:
	var im := ImmediateMesh.new()
	var normals_material := ORMMaterial3D.new()
	normals_material.vertex_color_use_as_albedo = true
	normals_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	normals_material.no_depth_test = true
	normals_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	im.surface_begin(Mesh.PRIMITIVE_LINES, normals_material)

	for pipeline in pipelines:
		var idx := pipeline.surface.idx

		if idx < 0 or idx >= mesh.get_surface_count():
			continue

		var arrays := mesh.surface_get_arrays(idx)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]

		for i in vertices.size():
			im.surface_set_color(debug_normals_color)
			im.surface_add_vertex(vertices[i])
			im.surface_add_vertex(vertices[i] + normals[i] * debug_normals_length)

	im.surface_end()

	var mi := MeshInstance3D.new()
	mi.mesh = im
	return mi


## Source meshes rarely carry the storage flag, so everything gets rebuilt once.
## Already converted on re-entry - rebuilding would drop the computed surfaces
func convert_to_storage_buffer_mesh() -> void:
	var source_mesh := mesh

	if source_mesh.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_STORAGE_BUFFER:
		return

	var new_mesh := ArrayMesh.new()

	for i in source_mesh.get_surface_count():
		var arrays := source_mesh.surface_get_arrays(i)

		new_mesh.add_surface_from_arrays(
			Mesh.PRIMITIVE_TRIANGLES,
			arrays,
			[],
			{},
			Mesh.ARRAY_FLAG_USE_STORAGE_BUFFER
		)

		var source_material := source_mesh.surface_get_material(i)

		if source_material != null:
			new_mesh.surface_set_material(i, source_material)

	mesh_instance.mesh = new_mesh
