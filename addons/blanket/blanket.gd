## Covers every mesh in a scene
##
## Drop this in once and it finds the meshes around it, adding a [BlanketInstance] to each one.
## To skip a mesh, add it to [member exclude_group] - or a parent node, to skip everything under it.
@icon("res://addons/blanket/assets/blanket.svg")
extends Node
class_name Blanket

#region Exports
## Off stops new insertions and broadcasts. Existing instances stay put
@export var enabled := true:
	set(value):
		enabled = value

		if enabled:
			cover_siblings()

@export_range(0, 3, 0.01, "or_greater") var depth := BlanketParams.DEFAULT_DEPTH:
	set(value):
		depth = value
		push_settings()

## How far a face may tilt from up and still get covered. 90 includes vertical walls
@export_range(0.0, 90.0, 1.0, "degrees") var max_slope_degrees := BlanketParams.DEFAULT_MAX_SLOPE_DEGREES:
	set(value):
		max_slope_degrees = value
		push_settings()

## When is an edge betwen two faces considered flat
@export_range(0.0, 90.0, 1.0, "degrees") var min_crease_degrees := BlanketParams.DEFAULT_MIN_CREASE_DEGREES:
	set(value):
		min_crease_degrees = value
		push_settings()

## Meshes in this group are skipped, as are those under a parent in it
@export var exclude_group: StringName = &"blanket_exclude"
@export var material: Material = BlanketInstance.DEFAULT_MATERIAL

@export_group("Debug", "debug")
@export_subgroup("Normals", "debug_normals")
@export var debug_normals_enabled := false
@export_range(0, 2, 0.01, "or_greater", "prefer_slider") var debug_normals_length := 0.2
@export var debug_normals_color := Color.ORANGE_RED

@export_subgroup("Indices", "debug_indices")
@export var debug_indices_enabled := false
@export_range(0.001, 0.1, 0.001, "or_greater") var debug_indices_size := 0.02
@export var debug_indices_color := Color("f2e86d")
#endregion

func _ready() -> void:
	cover_siblings()


## Idempotent - is_eligible skips anything already covered
func cover_siblings() -> void:
	if not enabled or not is_inside_tree():
		return

	var parent := get_parent()

	if parent == null:
		return

	for sibling in parent.get_children():
		if sibling != self:
			cover(sibling)

	push_settings()


func cover(node: Node) -> void:
	if node.is_in_group(exclude_group):
		return

	if node is MeshInstance3D and is_eligible(node):
		add_instance(node)

	for child in node.get_children():
		cover(child)


## A hand-placed instance keeps its own settings. Leave it be
func is_eligible(mesh_instance: MeshInstance3D) -> bool:
	if not BlanketInstance.is_supported(mesh_instance.mesh):
		return false

	for child in mesh_instance.get_children():
		if child is BlanketInstance:
			return false

	return true


## Settings land before add_child - in place by the time _ready bakes
func add_instance(mesh_instance: MeshInstance3D) -> void:
	var instance := BlanketInstance.new()

	instance.name = "BlanketInstance"
	instance.material = material
	instance.depth = depth
	instance.max_slope_degrees = max_slope_degrees
	instance.min_crease_degrees = min_crease_degrees
	instance.debug_normals_enabled = debug_normals_enabled
	instance.debug_normals_length = debug_normals_length
	instance.debug_normals_color = debug_normals_color
	instance.debug_indices_enabled = debug_indices_enabled
	instance.debug_indices_size = debug_indices_size
	instance.debug_indices_color = debug_indices_color

	mesh_instance.add_child(instance)


## The group spans the whole scene. Filter to what our parent owns - hand-placed instances included
func push_settings() -> void:
	if not enabled or not is_inside_tree():
		return

	var parent := get_parent()

	if parent == null:
		return

	for instance in get_tree().get_nodes_in_group(BlanketInstance.GROUP):
		if parent.is_ancestor_of(instance):
			if instance is BlanketInstance:
				instance.depth = depth
				instance.max_slope_degrees = max_slope_degrees
				instance.min_crease_degrees = min_crease_degrees


func change_depth(delta: int) -> void:
	depth = BlanketParams.DEFAULT_DEPTH if delta == 0 else depth + delta
