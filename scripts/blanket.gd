## Scene-wide dispatcher
##
## Walks the tree once at [code]_ready[/code] and inserts a [BlanketInstance] under every eligible [MeshInstance3D].
extends Node
class_name Blanket

## Meshes in this group are skipped, as are those under a parent in it
@export var exclude_group: StringName = &"blanket_exclude"
@export var material: Material = preload("res://assets/snow.tres")

@export_group("Debug", "debug")
@export var debug_enabled := true
@export_subgroup("Normals", "debug_normals")
@export var debug_normals_enabled := false
@export_range(0, 2, 0.01, "or_greater", "prefer_slider") var debug_normals_length := 0.2
@export var debug_normals_color := Color.ORANGE_RED

var instances: Array[BlanketInstance]


func _ready() -> void:
	var parent := get_parent()

	if parent == null:
		return

	for sibling in parent.get_children():
		if sibling != self:
			cover(sibling)


## Dropping the instances frees their RIDs through the RefCounted destructors
func _exit_tree() -> void:
	for instance in instances:
		if is_instance_valid(instance):
			instance.queue_free()

	instances.clear()


## Excluded tree branches are skipped whole - any parent can exclude everything it owns
func cover(node: Node) -> void:
	if node.is_in_group(exclude_group):
		return

	if node is MeshInstance3D and is_eligible(node):
		instances.append(add_instance(node))

	for child in node.get_children():
		cover(child)


## A manually placed instance is left alone, config and all
func is_eligible(mesh_instance: MeshInstance3D) -> bool:
	if mesh_instance.mesh == null:
		return false

	for child in mesh_instance.get_children():
		if child is BlanketInstance:
			return false

	return true


## Exports are applied before add_child, so they land before _ready bakes
func add_instance(mesh_instance: MeshInstance3D) -> BlanketInstance:
	var instance := BlanketInstance.new()

	instance.name = "BlanketInstance"
	instance.material = material
	instance.debug_enabled = debug_enabled
	instance.debug_normals_enabled = debug_normals_enabled
	instance.debug_normals_length = debug_normals_length
	instance.debug_normals_color = debug_normals_color

	mesh_instance.add_child(instance)

	return instance
