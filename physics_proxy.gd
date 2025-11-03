class_name PhysicsProxy
extends Node

## Physics Proxy System for Interior Spaces
## Manages separate physics spaces for stable interior physics while exteriors move/rotate

var world_space: RID
var proxy_interior_space: RID
var dock_proxy_space: RID
var proxy_gravity_area: RID  # Gravity area for proxy interior space

func _ready() -> void:
	# Get default world space from scene tree
	await get_tree().process_frame  # Wait for scene to be ready
	world_space = get_viewport().get_world_3d().space

	# Create proxy interior space with gravity
	proxy_interior_space = PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(proxy_interior_space, true)

	# Create gravity area for proxy interior space
	# UNIVERSAL: Match world gravity (9.81) for consistency across all spaces
	# This provides gravity for docked ships and character
	proxy_gravity_area = PhysicsServer3D.area_create()
	PhysicsServer3D.area_set_space(proxy_gravity_area, proxy_interior_space)
	PhysicsServer3D.area_set_param(proxy_gravity_area, PhysicsServer3D.AREA_PARAM_GRAVITY, 9.81)
	PhysicsServer3D.area_set_param(proxy_gravity_area, PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR, Vector3(0, -1, 0))
	PhysicsServer3D.area_set_param(proxy_gravity_area, PhysicsServer3D.AREA_PARAM_GRAVITY_IS_POINT, false)
	# Make the gravity area very large so it covers the entire proxy space
	var large_box_shape = PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(large_box_shape, Vector3(10000, 10000, 10000))
	PhysicsServer3D.area_add_shape(proxy_gravity_area, large_box_shape)
	PhysicsServer3D.area_set_shape_transform(proxy_gravity_area, 0, Transform3D(Basis(), Vector3.ZERO))

	# Create dock proxy space without gravity (space-like for vehicles)
	dock_proxy_space = PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(dock_proxy_space, true)

func _exit_tree() -> void:
	# Clean up created physics spaces and areas
	if proxy_gravity_area.is_valid():
		PhysicsServer3D.free_rid(proxy_gravity_area)
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
