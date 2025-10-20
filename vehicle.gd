class_name Vehicle
extends Node3D

## Vehicle with exterior physics and proxy interior system
## Exterior body exists in world or dock proxy, interior is stable proxy space

@export var physics_proxy: PhysicsProxy

# Vehicle components
var exterior_body: RigidBody3D  # Vehicle exterior in world or dock proxy
var dock_proxy_body: RID  # Vehicle body when docked (in parent container's interior space)
var interior_visuals: Node3D  # Interior geometry (visual only)
var interior_proxy_colliders: Array[RID]  # STATIC colliders in THIS vehicle's interior space
var transition_zone: Area3D  # Zone where player can enter vehicle

# Recursive physics space - each vehicle has its own interior space
var vehicle_interior_space: RID  # This vehicle's OWN interior physics space (for player/objects inside)

var is_docked: bool = false
var magnetism_enabled: bool = false

func _ready() -> void:
	_create_vehicle_exterior()
	_create_vehicle_physics_space()  # Create vehicle's own interior physics space
	_create_proxy_interior_colliders()
	_create_proxy_interior_visuals()  # Add visual geometry to proxy space
	_create_vehicle_dock_proxy()
	_create_transition_zone()

func _create_vehicle_exterior() -> void:
	# Vehicle exterior visual and physics body
	exterior_body = RigidBody3D.new()
	exterior_body.name = "ExteriorBody"
	add_child(exterior_body)

	# Create vehicle exterior as walls with opening (not a solid box) - BIGGER
	var exterior_material := StandardMaterial3D.new()
	exterior_material.albedo_color = Color(0.8, 0.3, 0.3)
	exterior_material.metallic = 0.3
	exterior_material.roughness = 0.7

	# Scale up by 3x (even bigger)
	var size_scale = 3.0

	# Floor (flush with bottom of walls)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = BoxMesh.new()
	floor_mesh.mesh.size = Vector3(6 * size_scale, 0.2, 10 * size_scale)
	floor_mesh.material_override = exterior_material
	floor_mesh.position = Vector3(0, -1.5 * size_scale + 0.1, 0)  # -1.5 * scale + half thickness
	floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	exterior_body.add_child(floor_mesh)

	# Left wall
	var left_wall := MeshInstance3D.new()
	left_wall.mesh = BoxMesh.new()
	left_wall.mesh.size = Vector3(0.2, 3 * size_scale, 10 * size_scale)
	left_wall.material_override = exterior_material
	left_wall.position = Vector3(-3 * size_scale, 0, 0)
	exterior_body.add_child(left_wall)

	# Right wall
	var right_wall := MeshInstance3D.new()
	right_wall.mesh = BoxMesh.new()
	right_wall.mesh.size = Vector3(0.2, 3 * size_scale, 10 * size_scale)
	right_wall.material_override = exterior_material
	right_wall.position = Vector3(3 * size_scale, 0, 0)
	exterior_body.add_child(right_wall)

	# Back wall (closed)
	var back_wall := MeshInstance3D.new()
	back_wall.mesh = BoxMesh.new()
	back_wall.mesh.size = Vector3(6 * size_scale, 3 * size_scale, 0.2)
	back_wall.material_override = exterior_material
	back_wall.position = Vector3(0, 0, -5 * size_scale)
	exterior_body.add_child(back_wall)

	# Front wall - OPENING (completely open entrance, no obstruction)
	# No front wall mesh or collision - fully open for entry/exit

	# Ceiling (flush with top of walls)
	var ceiling := MeshInstance3D.new()
	ceiling.mesh = BoxMesh.new()
	ceiling.mesh.size = Vector3(6 * size_scale, 0.2, 10 * size_scale)
	ceiling.material_override = exterior_material
	ceiling.position = Vector3(0, 1.5 * size_scale - 0.1, 0)  # 1.5 * scale - half thickness
	exterior_body.add_child(ceiling)

	# Collision shapes for exterior - match the actual wall geometry
	# Floor collision (flush with bottom of walls)
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(6 * size_scale, 0.2, 10 * size_scale)
	floor_collision.shape = floor_shape
	floor_collision.position = Vector3(0, -1.5 * size_scale + 0.1, 0)
	exterior_body.add_child(floor_collision)

	# Left wall collision
	var left_collision := CollisionShape3D.new()
	var left_shape := BoxShape3D.new()
	left_shape.size = Vector3(0.2, 3 * size_scale, 10 * size_scale)
	left_collision.shape = left_shape
	left_collision.position = Vector3(-3 * size_scale, 0, 0)
	exterior_body.add_child(left_collision)

	# Right wall collision
	var right_collision := CollisionShape3D.new()
	var right_shape := BoxShape3D.new()
	right_shape.size = Vector3(0.2, 3 * size_scale, 10 * size_scale)
	right_collision.shape = right_shape
	right_collision.position = Vector3(3 * size_scale, 0, 0)
	exterior_body.add_child(right_collision)

	# Back wall collision
	var back_collision := CollisionShape3D.new()
	var back_shape := BoxShape3D.new()
	back_shape.size = Vector3(6 * size_scale, 3 * size_scale, 0.2)
	back_collision.shape = back_shape
	back_collision.position = Vector3(0, 0, -5 * size_scale)
	exterior_body.add_child(back_collision)

	# No front collision - fully open entrance

	# Ceiling collision (flush with top of walls)
	var ceiling_collision := CollisionShape3D.new()
	var ceiling_shape := BoxShape3D.new()
	ceiling_shape.size = Vector3(6 * size_scale, 0.2, 10 * size_scale)
	ceiling_collision.shape = ceiling_shape
	ceiling_collision.position = Vector3(0, 1.5 * size_scale - 0.1, 0)
	exterior_body.add_child(ceiling_collision)

	# Configure rigid body
	exterior_body.mass = 1000.0
	exterior_body.lock_rotation = false
	exterior_body.gravity_scale = 1.0  # Enable gravity so it sits on ground
	exterior_body.linear_damp = 2.0  # Add damping so it doesn't bounce
	exterior_body.angular_damp = 2.0

func _create_vehicle_physics_space() -> void:
	# Each vehicle has its own interior physics space for recursive nesting
	# This allows ships inside containers, containers inside containers, etc.
	if not physics_proxy:
		push_warning("PhysicsProxy not assigned to Vehicle")
		return

	vehicle_interior_space = PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(vehicle_interior_space, false)  # Start inactive, activate on demand

	# Create gravity area for this vehicle's interior
	var gravity_area = PhysicsServer3D.area_create()
	PhysicsServer3D.area_set_space(gravity_area, vehicle_interior_space)
	PhysicsServer3D.area_set_param(gravity_area, PhysicsServer3D.AREA_PARAM_GRAVITY, 9.8)
	PhysicsServer3D.area_set_param(gravity_area, PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR, Vector3(0, -1, 0))
	PhysicsServer3D.area_set_param(gravity_area, PhysicsServer3D.AREA_PARAM_GRAVITY_IS_POINT, false)

	# Make the gravity area large enough to cover the vehicle interior
	var large_box_shape = PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(large_box_shape, Vector3(1000, 1000, 1000))
	PhysicsServer3D.area_add_shape(gravity_area, large_box_shape)
	PhysicsServer3D.area_set_shape_transform(gravity_area, 0, Transform3D(Basis(), Vector3.ZERO))

func _create_vehicle_interior_visuals() -> void:
	# Vehicle interior visuals - these are KINEMATIC (visual only, no player collision)
	# Player collides with proxy interior colliders instead
	# These visuals rotate with the ship so player sees the interior spinning
	interior_visuals = Node3D.new()
	interior_visuals.name = "InteriorVisuals"
	exterior_body.add_child(interior_visuals)  # Parent to exterior_body so it rotates with ship

	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.6, 0.6, 0.6)
	floor_material.metallic = 0.0
	floor_material.roughness = 0.8

	var wall_material := StandardMaterial3D.new()
	wall_material.albedo_color = Color(0.8, 0.8, 0.8)
	wall_material.metallic = 0.0
	wall_material.roughness = 0.7

	# Scale to match exterior (3x)
	var size_scale = 3.0

	# Floor - MATCHES proxy collider size AND position
	# Proxy collider: width 3.0 * size_scale (9 units), length 5.0 * size_scale (15 units)
	# Position at y=-1.4 * size_scale to match exterior floor and proxy collider
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = BoxMesh.new()
	floor_mesh.mesh.size = Vector3(3.0 * size_scale * 2, 0.1, 5.0 * size_scale * 2)
	floor_mesh.material_override = floor_material
	floor_mesh.position = Vector3(0, -1.4 * size_scale, 0)  # Match exterior and proxy collider
	floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	interior_visuals.add_child(floor_mesh)

	# Left wall - MATCHES proxy collider length
	var left_wall := MeshInstance3D.new()
	left_wall.mesh = BoxMesh.new()
	left_wall.mesh.size = Vector3(0.1, 2.5 * size_scale * 2, 5.0 * size_scale * 2)
	left_wall.material_override = wall_material
	left_wall.position = Vector3(-3.0 * size_scale, 0, 0)
	interior_visuals.add_child(left_wall)

	# Right wall - MATCHES proxy collider length
	var right_wall := MeshInstance3D.new()
	right_wall.mesh = BoxMesh.new()
	right_wall.mesh.size = Vector3(0.1, 2.5 * size_scale * 2, 5.0 * size_scale * 2)
	right_wall.material_override = wall_material
	right_wall.position = Vector3(3.0 * size_scale, 0, 0)
	interior_visuals.add_child(right_wall)

	# Back wall - MATCHES proxy collider width (at -5.0 * size_scale)
	var back_wall := MeshInstance3D.new()
	back_wall.mesh = BoxMesh.new()
	back_wall.mesh.size = Vector3(3.0 * size_scale * 2, 2.5 * size_scale * 2, 0.1)
	back_wall.material_override = wall_material
	back_wall.position = Vector3(0, 0, -5.0 * size_scale)
	interior_visuals.add_child(back_wall)

	# Front wall - no wall (opening)
	# Front wall removed so player can see out the opening

func _create_proxy_interior_colliders() -> void:
	# STATIC colliders in THIS vehicle's own interior physics space
	# Player inside THIS vehicle collides with these
	# SCALED 3x to match exterior
	if not vehicle_interior_space.is_valid():
		push_warning("Vehicle interior space not created")
		return

	interior_proxy_colliders = []

	var size_scale = 3.0

	# Floor collider - Relative coordinates in vehicle's own space (flush with walls)
	# Width: 3.0 * size_scale (9 units) matches exterior walls at ±9
	# Length: 5.0 * size_scale (15 units) matches exterior 15 units
	var floor_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(floor_shape, Vector3(3.0 * size_scale, 0.05, 5.0 * size_scale))

	var floor_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(floor_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(floor_body, vehicle_interior_space)  # Vehicle's own space!
	PhysicsServer3D.body_add_shape(floor_body, floor_shape)
	PhysicsServer3D.body_set_state(floor_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(0, -1.5 * size_scale + 0.05, 0)))
	# Enable collision with players
	PhysicsServer3D.body_set_collision_layer(floor_body, 1)
	PhysicsServer3D.body_set_collision_mask(floor_body, 1)
	interior_proxy_colliders.append(floor_body)

	# Left wall collider - matches floor length and width
	var left_wall_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(left_wall_shape, Vector3(0.05, 1.25 * size_scale, 5.0 * size_scale))

	var left_wall_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(left_wall_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(left_wall_body, vehicle_interior_space)  # Vehicle's own space!
	PhysicsServer3D.body_add_shape(left_wall_body, left_wall_shape)
	PhysicsServer3D.body_set_state(left_wall_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(-3.0 * size_scale, 0, 0)))
	# Enable collision with players
	PhysicsServer3D.body_set_collision_layer(left_wall_body, 1)
	PhysicsServer3D.body_set_collision_mask(left_wall_body, 1)
	interior_proxy_colliders.append(left_wall_body)

	# Right wall collider - matches floor length and width
	var right_wall_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(right_wall_shape, Vector3(0.05, 1.25 * size_scale, 5.0 * size_scale))

	var right_wall_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(right_wall_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(right_wall_body, vehicle_interior_space)  # Vehicle's own space!
	PhysicsServer3D.body_add_shape(right_wall_body, right_wall_shape)
	PhysicsServer3D.body_set_state(right_wall_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(3.0 * size_scale, 0, 0)))
	# Enable collision with players
	PhysicsServer3D.body_set_collision_layer(right_wall_body, 1)
	PhysicsServer3D.body_set_collision_mask(right_wall_body, 1)
	interior_proxy_colliders.append(right_wall_body)

	# Back wall collider - matches floor width
	var back_wall_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(back_wall_shape, Vector3(3.0 * size_scale, 1.25 * size_scale, 0.05))

	var back_wall_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(back_wall_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(back_wall_body, vehicle_interior_space)  # Vehicle's own space!
	PhysicsServer3D.body_add_shape(back_wall_body, back_wall_shape)
	PhysicsServer3D.body_set_state(back_wall_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(0, 0, -5.0 * size_scale)))
	# Enable collision with players
	PhysicsServer3D.body_set_collision_layer(back_wall_body, 1)
	PhysicsServer3D.body_set_collision_mask(back_wall_body, 1)
	interior_proxy_colliders.append(back_wall_body)

	# Ceiling collider - flush with top of walls
	var ceiling_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(ceiling_shape, Vector3(3.0 * size_scale, 0.05, 5.0 * size_scale))

	var ceiling_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(ceiling_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(ceiling_body, vehicle_interior_space)  # Vehicle's own space!
	PhysicsServer3D.body_add_shape(ceiling_body, ceiling_shape)
	PhysicsServer3D.body_set_state(ceiling_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(0, 1.5 * size_scale - 0.05, 0)))
	# Enable collision with players
	PhysicsServer3D.body_set_collision_layer(ceiling_body, 1)
	PhysicsServer3D.body_set_collision_mask(ceiling_body, 1)
	interior_proxy_colliders.append(ceiling_body)

	# Front wall collider - NO COLLIDER for opening
	# (removed so player can walk through the front entrance)

func _update_interior_colliders_position(dock_transform: Transform3D) -> void:
	# Update interior collider positions to match dock_proxy_body when docked
	# This ensures the player walks on floors that move with the ship
	if interior_proxy_colliders.size() == 0:
		return

	var size_scale = 3.0

	# The interior colliders were created with these RELATIVE positions:
	# Floor: (0, -1.4 * size_scale, 0)
	# Left wall: (-3.0 * size_scale, 0, 0)
	# Right wall: (3.0 * size_scale, 0, 0)
	# Back wall: (0, 0, -5.0 * size_scale)
	# Ceiling: (0, 1.4 * size_scale, 0)

	var relative_positions = [
		Vector3(0, -1.4 * size_scale, 0),  # Floor
		Vector3(-3.0 * size_scale, 0, 0),   # Left wall
		Vector3(3.0 * size_scale, 0, 0),    # Right wall
		Vector3(0, 0, -5.0 * size_scale),   # Back wall
		Vector3(0, 1.4 * size_scale, 0)     # Ceiling
	]

	# Update each collider's position to be relative to dock_proxy_body
	for i in range(min(interior_proxy_colliders.size(), relative_positions.size())):
		var collider = interior_proxy_colliders[i]
		if collider.is_valid():
			# Transform relative position by dock_proxy_body's transform
			var world_pos = dock_transform.origin + dock_transform.basis * relative_positions[i]
			var collider_transform = Transform3D(dock_transform.basis, world_pos)
			PhysicsServer3D.body_set_state(collider, PhysicsServer3D.BODY_STATE_TRANSFORM, collider_transform)

func _create_proxy_interior_visuals() -> void:
	# Create visual geometry in proxy space for PIP cameras to see
	# This is the STABLE interior that doesn't move with the ship
	# These need to be in a separate scene/world that the PIP viewport can see

	# NOTE: This requires creating a separate World3D for the viewport
	# which will be done in the dual_camera_view.gd
	# For now, we'll create the visual nodes that can be added to that world
	pass  # Implemented in dual_camera_view

func _create_vehicle_dock_proxy() -> void:
	# Create vehicle physics body for when docked in a container
	# Space will be set to parent container's interior space during docking
	# CRITICAL: Shape must match exterior_body - walls with OPEN FRONT for player access

	var size_scale = 3.0

	dock_proxy_body = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(dock_proxy_body, PhysicsServer3D.BODY_MODE_RIGID)
	PhysicsServer3D.body_set_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3.ZERO))

	# Create separate collision shapes matching exterior_body geometry (flush with walls)
	# Floor
	var floor_shape = PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(floor_shape, Vector3(3.0 * size_scale, 0.1, 5.0 * size_scale))
	PhysicsServer3D.body_add_shape(dock_proxy_body, floor_shape)
	PhysicsServer3D.body_set_shape_transform(dock_proxy_body, 0, Transform3D(Basis(), Vector3(0, -1.5 * size_scale + 0.1, 0)))

	# Left wall
	var left_wall_shape = PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(left_wall_shape, Vector3(0.1, 1.5 * size_scale, 5.0 * size_scale))
	PhysicsServer3D.body_add_shape(dock_proxy_body, left_wall_shape)
	PhysicsServer3D.body_set_shape_transform(dock_proxy_body, 1, Transform3D(Basis(), Vector3(-3.0 * size_scale, 0, 0)))

	# Right wall
	var right_wall_shape = PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(right_wall_shape, Vector3(0.1, 1.5 * size_scale, 5.0 * size_scale))
	PhysicsServer3D.body_add_shape(dock_proxy_body, right_wall_shape)
	PhysicsServer3D.body_set_shape_transform(dock_proxy_body, 2, Transform3D(Basis(), Vector3(3.0 * size_scale, 0, 0)))

	# Back wall (closed)
	var back_wall_shape = PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(back_wall_shape, Vector3(3.0 * size_scale, 1.5 * size_scale, 0.1))
	PhysicsServer3D.body_add_shape(dock_proxy_body, back_wall_shape)
	PhysicsServer3D.body_set_shape_transform(dock_proxy_body, 3, Transform3D(Basis(), Vector3(0, 0, -5.0 * size_scale)))

	# Ceiling
	var ceiling_shape = PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(ceiling_shape, Vector3(3.0 * size_scale, 0.1, 5.0 * size_scale))
	PhysicsServer3D.body_add_shape(dock_proxy_body, ceiling_shape)
	PhysicsServer3D.body_set_shape_transform(dock_proxy_body, 4, Transform3D(Basis(), Vector3(0, 1.5 * size_scale - 0.1, 0)))

	# NO FRONT WALL - this is the opening where player can enter

	# Enable collision with container interiors (layer 1, mask 1)
	PhysicsServer3D.body_set_collision_layer(dock_proxy_body, 1)
	PhysicsServer3D.body_set_collision_mask(dock_proxy_body, 1)

	# Physics parameters for docked ship
	PhysicsServer3D.body_set_param(dock_proxy_body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 1.0)  # Normal gravity
	PhysicsServer3D.body_set_param(dock_proxy_body, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP, 0.1)  # Minimal damping - same as free flight
	PhysicsServer3D.body_set_param(dock_proxy_body, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, 0.1)  # Minimal damping for rotation
	PhysicsServer3D.body_set_param(dock_proxy_body, PhysicsServer3D.BODY_PARAM_MASS, 1000.0)  # Same as exterior_body
	PhysicsServer3D.body_set_param(dock_proxy_body, PhysicsServer3D.BODY_PARAM_BOUNCE, 0.0)  # No bounce
	PhysicsServer3D.body_set_param(dock_proxy_body, PhysicsServer3D.BODY_PARAM_FRICTION, 1.0)  # Maximum friction to prevent sliding
	PhysicsServer3D.body_set_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, true)  # Allow sleeping when settled

func _create_transition_zone() -> void:
	# Create invisible transition zone at vehicle entrance (front opening)
	transition_zone = Area3D.new()
	transition_zone.name = "TransitionZone"
	add_child(transition_zone)  # Add to vehicle, not exterior_body

	# Zone is just used for logic, no visible collision shape needed
	# Transition detection is done via position checks in game_manager

func _process(_delta: float) -> void:
	# Update visual every frame for smooth rendering (not just physics frames)
	_update_vehicle_visual_position()

func _physics_process(_delta: float) -> void:
	# Interior colliders are STATIC and don't need updates
	# They stay at fixed positions in the ship's vehicle_interior_space
	pass

func _update_vehicle_visual_position() -> void:
	# Update vehicle visual based on current physics space
	if is_docked and dock_proxy_body.is_valid() and exterior_body:
		# Vehicle is docked in container - sync exterior visual with proxy physics
		var proxy_transform: Transform3D = PhysicsServer3D.body_get_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM)

		# Get parent container
		var container = _get_docked_container()
		if container and container.exterior_body:
			var container_transform = container.exterior_body.global_transform

			# Transform proxy position (in container's interior space) to world space
			var world_transform = container_transform * proxy_transform

			# Update exterior body to match proxy position
			exterior_body.global_transform = world_transform
	# When not docked, exterior_body is already in world space and doesn't need updating

func _is_player_in_ship() -> bool:
	# Check if player is in this ship's interior
	var game_manager = get_parent()
	if not game_manager:
		return false

	for child in game_manager.get_children():
		if child is CharacterController:
			return child.is_in_vehicle

	return false

func _refresh_interior_colliders_at_origin() -> void:
	# Keep KINEMATIC colliders active when ship is free-flying
	# Colliders are stationary at origin in proxy space
	if interior_proxy_colliders.size() == 0:
		return

	var size_scale = 3.0

	var collider_positions = [
		Vector3(0, -1.4 * size_scale, 0),  # Floor
		Vector3(-3.0 * size_scale, 0, 0),   # Left wall
		Vector3(3.0 * size_scale, 0, 0),    # Right wall
		Vector3(0, 0, -5.0 * size_scale),   # Back wall
		Vector3(0, 1.4 * size_scale, 0)     # Ceiling
	]

	for i in range(min(interior_proxy_colliders.size(), collider_positions.size())):
		var collider = interior_proxy_colliders[i]
		if collider.is_valid():
			var collider_transform = Transform3D(Basis(), collider_positions[i])
			PhysicsServer3D.body_set_state(collider, PhysicsServer3D.BODY_STATE_TRANSFORM, collider_transform)

func apply_thrust(direction: Vector3, force: float) -> void:
	if is_docked and dock_proxy_body.is_valid():
		# Apply thrust in proxy interior space
		# Direction comes in world space from exterior_body.basis
		# Need to transform to proxy space where dock_proxy_body lives
		var container = _get_docked_container()
		if container and container.exterior_body:
			var container_transform = container.exterior_body.global_transform
			# Transform world direction to container local (which matches proxy space orientation)
			var proxy_direction = container_transform.basis.inverse() * direction

			# Full thrust power when docked, but clamp resulting velocity to safe limits
			var mass = PhysicsServer3D.body_get_param(dock_proxy_body, PhysicsServer3D.BODY_PARAM_MASS)
			var acceleration = force / mass
			var impulse = proxy_direction * acceleration * get_process_delta_time()
			var current_vel = PhysicsServer3D.body_get_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
			var new_vel = current_vel + impulse

			# Clamp to high max speeds - only prevent physics explosions, not normal flight
			new_vel.x = clamp(new_vel.x, -30.0, 30.0)
			new_vel.y = clamp(new_vel.y, -20.0, 20.0)
			new_vel.z = clamp(new_vel.z, -30.0, 30.0)

			PhysicsServer3D.body_set_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, new_vel)
	elif exterior_body:
		# Apply thrust in world
		exterior_body.apply_central_force(direction * force)

func apply_rotation(axis: Vector3, torque: float) -> void:
	if is_docked and dock_proxy_body.is_valid():
		# Apply rotation in proxy interior space
		# Axis comes in world space, need to transform to container local space
		var container = _get_docked_container()
		if container and container.exterior_body:
			var container_transform = container.exterior_body.global_transform
			var local_axis = container_transform.basis.inverse() * axis

			# Full rotation power when docked, but clamp resulting angular velocity
			var mass = PhysicsServer3D.body_get_param(dock_proxy_body, PhysicsServer3D.BODY_PARAM_MASS)
			var angular_acceleration = torque / mass
			var angular_impulse = local_axis * angular_acceleration * get_process_delta_time()
			var current_angvel = PhysicsServer3D.body_get_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
			var new_angvel = current_angvel + angular_impulse

			# Clamp angular velocity to reasonable rotation speeds (3.0 rad/s = ~172 deg/s)
			new_angvel.x = clamp(new_angvel.x, -3.0, 3.0)
			new_angvel.y = clamp(new_angvel.y, -3.0, 3.0)
			new_angvel.z = clamp(new_angvel.z, -3.0, 3.0)

			PhysicsServer3D.body_set_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, new_angvel)
	elif exterior_body:
		# Apply rotation in world
		exterior_body.apply_torque(axis * torque)

func toggle_magnetism() -> void:
	# Toggle artificial gravity in THIS vehicle's interior space
	if vehicle_interior_space.is_valid():
		magnetism_enabled = !magnetism_enabled
		# Note: In the new architecture, each vehicle has its own gravity area
		# which was created in _create_vehicle_physics_space()
		# We would need to store the gravity_area RID to toggle it
		# For now, this is a placeholder for future implementation

func set_docked(docked: bool, parent_container: VehicleContainer = null) -> void:
	if docked and not is_docked:
		# Ship is entering dock - transfer position from world to container's interior space
		if exterior_body and dock_proxy_body.is_valid():
			# Get container to transform world position to container local space
			# If not provided, try to find VehicleContainerSmall (backwards compatibility)
			var container = parent_container
			if not container:
				container = get_parent().get_node_or_null("VehicleContainerSmall")
			if container and container.exterior_body:
				var container_transform = container.exterior_body.global_transform
				var world_transform = exterior_body.global_transform

				# Transform world position to container local space (preserve current position)
				var relative_transform = container_transform.inverse() * world_transform

				# Safety check: Clamp Y position to prevent spawning below floor
				# Container floor is at y = -1.4 * size_scale (for small container: -21)
				# Ensure ship spawns at least 3 units above floor
				var container_size_scale = 3.0 * container.size_multiplier
				var floor_y = -1.4 * container_size_scale
				var min_y = floor_y + 3.0  # 3 units above floor minimum

				if relative_transform.origin.y < min_y:
					relative_transform.origin.y = min_y

				# CRITICAL: Set transform and velocities BEFORE adding to space
				# This prevents spawning at (0,0,0) inside floor collider
				PhysicsServer3D.body_set_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM, relative_transform)

				# Preserve velocity for seamless entry
				# Transform from world space to container local space
				var world_velocity = exterior_body.linear_velocity
				var local_velocity = container_transform.basis.inverse() * world_velocity

				# Moderate clamping to prevent extreme velocities
				var clamped_velocity = Vector3(
					clamp(local_velocity.x, -15.0, 15.0),
					clamp(local_velocity.y, -8.0, 8.0),
					clamp(local_velocity.z, -15.0, 15.0)
				)
				# Light damping (keep 70% of velocity)
				clamped_velocity *= 0.7

				# CRITICAL: Wake up the body BEFORE setting velocities
				# Otherwise physics engine might ignore velocity on a sleeping body
				PhysicsServer3D.body_set_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_SLEEPING, false)

				# Set velocities
				PhysicsServer3D.body_set_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, clamped_velocity)

				# Preserve angular velocity with light damping for stability
				var world_angvel = exterior_body.angular_velocity
				var local_angvel = container_transform.basis.inverse() * world_angvel
				# Apply 30% damping to match linear velocity damping
				PhysicsServer3D.body_set_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, local_angvel * 0.7)

				# Force wake up again after setting velocities
				PhysicsServer3D.body_set_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_SLEEPING, false)

				# CRITICAL: NOW add to space AFTER all state is configured
				# This prevents spawning at origin and getting ejected from floor
				var container_interior_space = container.get_interior_space()
				if not container_interior_space.is_valid():
					push_error("Container interior space not valid!")
					return

				# Activate container space if not already active
				if not PhysicsServer3D.space_is_active(container_interior_space):
					PhysicsServer3D.space_set_active(container_interior_space, true)

				PhysicsServer3D.body_set_space(dock_proxy_body, container_interior_space)

				# CRITICAL: State might be reset when adding to space - set it AGAIN after adding
				PhysicsServer3D.body_set_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM, relative_transform)
				PhysicsServer3D.body_set_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, clamped_velocity)
				PhysicsServer3D.body_set_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, local_angvel * 0.7)
				PhysicsServer3D.body_set_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_SLEEPING, false)

				# Make exterior_body kinematic (not frozen) - it becomes a visual follower
				# Similar to how player's world_body continues to exist when in vehicle/container
				exterior_body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
				exterior_body.freeze = true  # Enable kinematic mode

				# CRITICAL: Disable collision on exterior_body to prevent physics conflicts
				# Only dock_proxy_body should have active physics when docked
				exterior_body.collision_layer = 0
				exterior_body.collision_mask = 0
	elif not docked and is_docked:
		# Ship is leaving dock - transfer position from container's interior space to world
		if exterior_body and dock_proxy_body.is_valid():
			# Get container (if not provided, try to find VehicleContainerSmall)
			var container = parent_container
			if not container:
				container = get_parent().get_node_or_null("VehicleContainerSmall")
			if container and container.exterior_body:
				var container_transform = container.exterior_body.global_transform
				var dock_transform = PhysicsServer3D.body_get_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM)

				# Transform dock proxy position (in container's interior space) to world space
				var world_transform = container_transform * dock_transform

				# Set exterior body to this world position
				exterior_body.global_transform = world_transform

				# CRITICAL: Zero velocities BEFORE unfreezing to clear phantom velocities from kinematic mode
				exterior_body.linear_velocity = Vector3.ZERO
				exterior_body.angular_velocity = Vector3.ZERO

				# CRITICAL: Restore exterior_body to rigid mode after undocking
				# Exterior_body is now the active physics body again
				exterior_body.freeze = false  # Disable kinematic

				# Re-enable collision on exterior_body
				exterior_body.collision_layer = 1
				exterior_body.collision_mask = 1

				# NOW set correct velocities from container's interior space to world space
				var local_velocity = PhysicsServer3D.body_get_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
				var world_velocity = container_transform.basis * local_velocity
				exterior_body.linear_velocity = world_velocity

				# Copy angular velocity
				var local_angvel = PhysicsServer3D.body_get_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
				var world_angvel = container_transform.basis * local_angvel
				exterior_body.angular_velocity = world_angvel

				# Remove dock_proxy_body from container's interior space
				# (it will be added to a new space when docking again)
				PhysicsServer3D.body_set_space(dock_proxy_body, RID())

	is_docked = docked

func get_interior_space() -> RID:
	# Return this vehicle's interior physics space (for recursive nesting)
	return vehicle_interior_space

func _get_docked_container() -> VehicleContainer:
	# Find the container that this ship is currently docked in
	# Returns null if not docked or container not found
	if not is_docked or not dock_proxy_body.is_valid():
		return null

	var game_manager = get_parent()
	if not game_manager:
		return null

	# Find the container whose interior space contains our dock_proxy_body
	var dock_space = PhysicsServer3D.body_get_space(dock_proxy_body)
	for child in game_manager.get_children():
		if child is VehicleContainer:
			var test_container = child as VehicleContainer
			if dock_space == test_container.get_interior_space():
				return test_container

	return null

func _exit_tree() -> void:
	# Clean up proxy colliders
	for collider in interior_proxy_colliders:
		if collider.is_valid():
			PhysicsServer3D.free_rid(collider)

	if dock_proxy_body.is_valid():
		PhysicsServer3D.free_rid(dock_proxy_body)

	# Clean up vehicle's interior physics space
	if vehicle_interior_space.is_valid():
		PhysicsServer3D.free_rid(vehicle_interior_space)
