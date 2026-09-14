## Covers one mesh
##
## Add this under a [MeshInstance3D] and it grows a layer of cover over every surface facing upward.
## [Blanket] adds these across a whole scene - place one by hand when a mesh needs its own depth or material.
@icon("res://assets/blanket_instance.svg")
extends Node3D
class_name BlanketInstance

const GROUP = &"blanket_instances"
const EPSILON = 0.0001
const MIN_REBAKE_DELAY = 0.01

@export var material: Material = preload("res://assets/snow.tres")
@export_range(0, 3, 0.05, "or_greater") var depth := BlanketParams.DEFAULT_DEPTH:
	set(value):
		depth = value
		update_processing()
## How quickly the layer settles toward [member depth]
@export_range(0.1, 20.0, 0.1, "or_greater") var settle_rate := 6.0
## Rotating or scaling a mesh moves which faces point up, so the selection needs rebuilding
@export var rebake_on_transform := true:
	set(value):
		rebake_on_transform = value
		prev_basis = current_basis()
## Quiet time before a rebake - dragging the slider spams updates
@export_range(MIN_REBAKE_DELAY, 1.0, 0.01, "or_greater") var rebake_delay := 0.2:
	set(value):
		rebake_delay = maxf(value, MIN_REBAKE_DELAY)

@export_group("Debug", "debug")
@export var debug_enabled := false:
	set(value):
		debug_enabled = value
		draw_normals.call_deferred()

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
	get: return mesh_instance.mesh if mesh_instance else null
var debug_normals_mesh: MeshInstance3D: set = set_debug_normals_mesh
var pipelines: Array[BlanketPipeline]
var current_depth := BlanketParams.DEFAULT_DEPTH
var prev_basis: Basis
var rebake_countdown := 0.0


func _ready() -> void:
	visible = false
	set_notify_transform(true)
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

	if rebake_delay <= 0.0:
		rebake()
		return

	rebake_countdown = rebake_delay
	set_process(true)


func _process(delta: float) -> void:
	settle_depth(delta)
	tick_rebake(delta)


func setup() -> void:
	convert_to_storage_buffer_mesh()
	validate()

	mesh.changed.connect(on_mesh_changed)

	for i in mesh.get_surface_count():
		pipelines.append(BlanketPipeline.new(mesh, i, mesh_instance.global_transform))

	for pipeline in pipelines:
		pipeline.bake()

	prev_basis = current_basis()
	apply_depth()


## Framerate-independent exponential ease - lerp alone would tie the curve to framerate
func settle_depth(delta: float) -> void:
	if is_equal_approx(current_depth, depth):
		return

	current_depth = lerp(current_depth, depth, 1.0 - exp(-settle_rate * delta))

	if absf(depth - current_depth) < EPSILON:
		current_depth = depth
		update_processing()

	apply_depth()


func tick_rebake(delta: float) -> void:
	if rebake_countdown <= 0.0:
		return

	rebake_countdown -= delta

	if rebake_countdown <= 0.0:
		rebake()
		update_processing()


func apply_depth() -> void:
	for pipeline in pipelines:
		pipeline.params.depth = current_depth
		pipeline.update()

	draw_normals.call_deferred()


func rebake() -> void:
	for pipeline in pipelines:
		pipeline.params.local_up = mesh_instance.global_transform.basis.inverse() * Vector3.UP
		pipeline.params.depth = current_depth
		pipeline.bake()

	draw_normals.call_deferred()


func current_basis() -> Basis:
	return global_transform.basis if is_inside_tree() else Basis()


func update_processing() -> void:
	set_process(rebake_countdown > 0.0 or not is_equal_approx(depth, current_depth))


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


func draw_normals() -> void:
	if not is_inside_tree() or not is_node_ready():
		return

	debug_normals_mesh = null

	if not debug_enabled or not debug_normals_enabled:
		return

	debug_normals_mesh = build_normal_lines(mesh_instance.global_transform, debug_normals_length)


## Every computed surface into one mesh - surface.idx is where each landed
func build_normal_lines(transform: Transform3D, length := 0.2) -> MeshInstance3D:
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
			var world_pos := transform * vertices[i]
			var world_normal := (transform.basis * normals[i]).normalized()

			im.surface_set_color(debug_normals_color)
			im.surface_add_vertex(world_pos)
			im.surface_add_vertex(world_pos + world_normal * length)

	im.surface_end()

	var mi := MeshInstance3D.new()
	mi.mesh = im
	return mi


func validate() -> void:
	assert(mesh is ArrayMesh,
		"Must be an ArrayMesh - primitives like BoxMesh cannot have the STORAGE_BUFFER flag")
	var format := mesh.surface_get_format(0)
	var uses_storage_buffer := (format & Mesh.ARRAY_FLAG_USE_STORAGE_BUFFER) != 0
	assert(uses_storage_buffer, "Mesh must have the STORAGE_BUFFER flag")


## Already converted on re-entry - rebuilding would drop the computed surfaces
func convert_to_storage_buffer_mesh() -> void:
	var source_mesh := mesh

	if source_mesh.get_surface_count() > 0 \
			and source_mesh.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_STORAGE_BUFFER:
		return

	var new_mesh := ArrayMesh.new()

	for i in source_mesh.get_surface_count():
		var arrays := source_mesh.surface_get_arrays(i)

		new_mesh.add_surface_from_arrays(
			source_mesh.surface_get_primitive_type(i),
			arrays,
			[],
			{},
			Mesh.ARRAY_FLAG_USE_STORAGE_BUFFER
		)

		var source_material := source_mesh.surface_get_material(i)

		if source_material != null:
			new_mesh.surface_set_material(i, source_material)

	mesh_instance.mesh = new_mesh
