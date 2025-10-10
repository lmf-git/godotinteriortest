class_name PhysicsProxy
extends Node

## Physics Proxy System for Interior Spaces
## Manages separate physics spaces for stable interior physics while exteriors move/rotate

var world_space: RID
var proxy_interior_space: RID
var dock_proxy_space: RID

func _ready() -> void:
	# Get default world space from scene tree
	await get_tree().process_frame  # Wait for scene to be ready
	world_space = get_viewport().get_world_3d().space

	# Create proxy interior space with gravity
	proxy_interior_space = PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(proxy_interior_space, true)
	# Note: Gravity will be applied manually in character physics

	# Create dock proxy space without gravity (space-like for vehicles)
	dock_proxy_space = PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(dock_proxy_space, true)

func _exit_tree() -> void:
	# Clean up created physics spaces
	if proxy_interior_space.is_valid():
		PhysicsServer3D.free_rid(proxy_interior_space)
	if dock_proxy_space.is_valid():
		PhysicsServer3D.free_rid(dock_proxy_space)

func get_world_space() -> RID:
	return world_space

func get_proxy_interior_space() -> RID:
	return proxy_interior_space

func get_dock_proxy_space() -> RID:
	return dock_proxy_space

var gravity_enabled: bool = true

func set_proxy_interior_gravity(enabled: bool) -> void:
	## Toggle artificial gravity in proxy interior (for magnetism)
	gravity_enabled = enabled
