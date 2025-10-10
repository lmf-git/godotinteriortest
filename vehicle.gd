class_name Vehicle
extends Node3D

## Vehicle with exterior physics and proxy interior system
## Exterior body exists in world or dock proxy, interior is stable proxy space

@export var physics_proxy: PhysicsProxy

# Vehicle components
var exterior_body: RigidBody3D  # Vehicle exterior in world or dock proxy
var dock_proxy_body: RID  # Vehicle body when docked (in dock proxy space)
var interior_visuals: Node3D  # Interior geometry (visual only)
var interior_proxy_colliders: Array[RID]  # Static colliders in proxy space
var transition_zone: Area3D  # Zone where player can enter vehicle

var is_docked: bool = false
var magnetism_enabled: bool = false

func _ready() -> void:
	_create_vehicle_exterior()
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

	# Floor
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = BoxMesh.new()
	floor_mesh.mesh.size = Vector3(6 * size_scale, 0.2, 10 * size_scale)
	floor_mesh.material_override = exterior_material
	floor_mesh.position = Vector3(0, -1.4 * size_scale, 0)
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

	# Front wall - OPENING (no mesh, this is the entrance)
	# Top part of front wall (above opening)
	var front_top := MeshInstance3D.new()
	front_top.mesh = BoxMesh.new()
	front_top.mesh.size = Vector3(6 * size_scale, 1.0 * size_scale, 0.2)
	front_top.material_override = exterior_material
	front_top.position = Vector3(0, 2.5 * size_scale, 5 * size_scale)
	exterior_body.add_child(front_top)

	# Ceiling
	var ceiling := MeshInstance3D.new()
	ceiling.mesh = BoxMesh.new()
	ceiling.mesh.size = Vector3(6 * size_scale, 0.2, 10 * size_scale)
	ceiling.material_override = exterior_material
	ceiling.position = Vector3(0, 1.4 * size_scale, 0)
	exterior_body.add_child(ceiling)

	# Collision shapes for exterior - match the actual wall geometry
	# Floor collision
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(6 * size_scale, 0.2, 10 * size_scale)
	floor_collision.shape = floor_shape
	floor_collision.position = Vector3(0, -1.4 * size_scale, 0)
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

	# Front top collision (above opening)
	var front_top_collision := CollisionShape3D.new()
	var front_top_shape := BoxShape3D.new()
	front_top_shape.size = Vector3(6 * size_scale, 1.0 * size_scale, 0.2)
	front_top_collision.shape = front_top_shape
	front_top_collision.position = Vector3(0, 2.5 * size_scale, 5 * size_scale)
	exterior_body.add_child(front_top_collision)

	# Ceiling collision
	var ceiling_collision := CollisionShape3D.new()
	var ceiling_shape := BoxShape3D.new()
	ceiling_shape.size = Vector3(6 * size_scale, 0.2, 10 * size_scale)
	ceiling_collision.shape = ceiling_shape
	ceiling_collision.position = Vector3(0, 1.4 * size_scale, 0)
	exterior_body.add_child(ceiling_collision)

	# Configure rigid body
	exterior_body.mass = 1000.0
	exterior_body.lock_rotation = false
	exterior_body.gravity_scale = 1.0  # Enable gravity so it sits on ground
	exterior_body.linear_damp = 2.0  # Add damping so it doesn't bounce
	exterior_body.angular_damp = 2.0

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
	# Proxy collider: half-extents 4.9 * size_scale = total 9.8 * size_scale
	# Position at y=-1.4 * size_scale to match exterior floor and proxy collider
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = BoxMesh.new()
	floor_mesh.mesh.size = Vector3(5.8 * size_scale, 0.1, 9.8 * size_scale)
	floor_mesh.material_override = floor_material
	floor_mesh.position = Vector3(0, -1.4 * size_scale, 0)  # Match exterior and proxy collider
	floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	interior_visuals.add_child(floor_mesh)

	# Left wall - MATCHES proxy collider length
	var left_wall := MeshInstance3D.new()
	left_wall.mesh = BoxMesh.new()
	left_wall.mesh.size = Vector3(0.1, 2.8 * size_scale, 9.8 * size_scale)
	left_wall.material_override = wall_material
	left_wall.position = Vector3(-2.9 * size_scale, 0, 0)
	interior_visuals.add_child(left_wall)

	# Right wall - MATCHES proxy collider length
	var right_wall := MeshInstance3D.new()
	right_wall.mesh = BoxMesh.new()
	right_wall.mesh.size = Vector3(0.1, 2.8 * size_scale, 9.8 * size_scale)
	right_wall.material_override = wall_material
	right_wall.position = Vector3(2.9 * size_scale, 0, 0)
	interior_visuals.add_child(right_wall)

	# Back wall - MATCHES proxy collider position (at -4.9 * size_scale)
	var back_wall := MeshInstance3D.new()
	back_wall.mesh = BoxMesh.new()
	back_wall.mesh.size = Vector3(5.8 * size_scale, 2.8 * size_scale, 0.1)
	back_wall.material_override = wall_material
	back_wall.position = Vector3(0, 0, -4.9 * size_scale)
	interior_visuals.add_child(back_wall)

	# Front wall - no wall (opening)
	# Front wall removed so player can see out the opening

func _create_proxy_interior_colliders() -> void:
	# STATIC colliders in proxy world - player can collide with these
	# These never move and provide stable surfaces for the player
	# SCALED 3x to match exterior
	if not physics_proxy:
		push_warning("PhysicsProxy not assigned to Vehicle")
		return

	var proxy_space = physics_proxy.get_proxy_interior_space()
	interior_proxy_colliders = []

	var size_scale = 3.0

	# Floor collider - LARGER for more walkable space, but still smaller than exterior
	# Use 4.9 * size_scale (14.7 units total) vs exterior 15 units = 0.3 unit gap each end
	var floor_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(floor_shape, Vector3(2.5 * size_scale, 0.05, 4.9 * size_scale))

	var floor_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(floor_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(floor_body, proxy_space)
	PhysicsServer3D.body_add_shape(floor_body, floor_shape)
	PhysicsServer3D.body_set_state(floor_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(0, -1.4 * size_scale, 0)))
	interior_proxy_colliders.append(floor_body)

	# Left wall collider - matches floor length
	var left_wall_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(left_wall_shape, Vector3(0.05, 1.25 * size_scale, 4.9 * size_scale))

	var left_wall_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(left_wall_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(left_wall_body, proxy_space)
	PhysicsServer3D.body_add_shape(left_wall_body, left_wall_shape)
	PhysicsServer3D.body_set_state(left_wall_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(-2.5 * size_scale, 0, 0)))
	interior_proxy_colliders.append(left_wall_body)

	# Right wall collider - matches floor length
	var right_wall_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(right_wall_shape, Vector3(0.05, 1.25 * size_scale, 4.9 * size_scale))

	var right_wall_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(right_wall_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(right_wall_body, proxy_space)
	PhysicsServer3D.body_add_shape(right_wall_body, right_wall_shape)
	PhysicsServer3D.body_set_state(right_wall_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(2.5 * size_scale, 0, 0)))
	interior_proxy_colliders.append(right_wall_body)

	# Back wall collider - matches floor position
	var back_wall_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(back_wall_shape, Vector3(2.5 * size_scale, 1.25 * size_scale, 0.05))

	var back_wall_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(back_wall_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(back_wall_body, proxy_space)
	PhysicsServer3D.body_add_shape(back_wall_body, back_wall_shape)
	PhysicsServer3D.body_set_state(back_wall_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(0, 0, -4.9 * size_scale)))
	interior_proxy_colliders.append(back_wall_body)

	# Ceiling collider - matches floor length
	var ceiling_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(ceiling_shape, Vector3(2.5 * size_scale, 0.05, 4.9 * size_scale))

	var ceiling_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(ceiling_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(ceiling_body, proxy_space)
	PhysicsServer3D.body_add_shape(ceiling_body, ceiling_shape)
	PhysicsServer3D.body_set_state(ceiling_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(0, 1.4 * size_scale, 0)))
	interior_proxy_colliders.append(ceiling_body)

	# Front wall collider - NO COLLIDER for opening
	# (removed so player can walk through the front entrance)

func _create_proxy_interior_visuals() -> void:
	# Create visual geometry in proxy space for PIP cameras to see
	# This is the STABLE interior that doesn't move with the ship
	# These need to be in a separate scene/world that the PIP viewport can see

	# NOTE: This requires creating a separate World3D for the viewport
	# which will be done in the dual_camera_view.gd
	# For now, we'll create the visual nodes that can be added to that world
	pass  # Implemented in dual_camera_view

func _create_vehicle_dock_proxy() -> void:
	# Create vehicle physics body in dock proxy world (for when vehicle is docked)
	if not physics_proxy:
		return

	var dock_space = physics_proxy.get_dock_proxy_space()

	var vehicle_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(vehicle_shape, Vector3(3, 1.5, 5))

	dock_proxy_body = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(dock_proxy_body, PhysicsServer3D.BODY_MODE_RIGID)
	PhysicsServer3D.body_set_space(dock_proxy_body, dock_space)
	PhysicsServer3D.body_add_shape(dock_proxy_body, vehicle_shape)
	PhysicsServer3D.body_set_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3.ZERO))

func _create_transition_zone() -> void:
	# Create invisible transition zone at vehicle entrance (front opening)
	transition_zone = Area3D.new()
	transition_zone.name = "TransitionZone"
	add_child(transition_zone)  # Add to vehicle, not exterior_body

	# Zone is just used for logic, no visible collision shape needed
	# Transition detection is done via position checks in game_manager

func _process(_delta: float) -> void:
	# Update exterior body visual based on docked state
	if is_docked and dock_proxy_body.is_valid() and exterior_body:
		# Ship is docked: transform dock proxy position to world space
		var dock_transform: Transform3D = PhysicsServer3D.body_get_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM)

		# Get parent container (we need to find the container in the scene)
		var container = get_parent().get_node_or_null("VehicleContainer")
		if container and container.exterior_body:
			var container_transform = container.exterior_body.global_transform

			# Transform dock proxy position by container transformation
			var world_transform = container_transform * dock_transform
			exterior_body.global_transform = world_transform
	elif exterior_body:
		# Ship in world space: exterior_body controls its own position (physics drives it)
		pass

	# Interior visuals automatically rotate with exterior_body (they're parented to it)

func apply_thrust(direction: Vector3, force: float) -> void:
	if is_docked and dock_proxy_body.is_valid():
		# Apply thrust in dock proxy
		var current_vel = PhysicsServer3D.body_get_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
		var new_vel = current_vel + direction * force
		PhysicsServer3D.body_set_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, new_vel)
	elif exterior_body:
		# Apply thrust in world
		exterior_body.apply_central_force(direction * force)

func apply_rotation(axis: Vector3, torque: float) -> void:
	if is_docked and dock_proxy_body.is_valid():
		# Apply rotation in dock proxy
		var current_angvel = PhysicsServer3D.body_get_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
		var new_angvel = current_angvel + axis * torque
		PhysicsServer3D.body_set_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, new_angvel)
	elif exterior_body:
		# Apply rotation in world
		exterior_body.apply_torque(axis * torque)

func toggle_magnetism() -> void:
	if is_docked and physics_proxy:
		magnetism_enabled = !magnetism_enabled
		physics_proxy.set_proxy_interior_gravity(magnetism_enabled)

func set_docked(docked: bool) -> void:
	is_docked = docked

func _exit_tree() -> void:
	# Clean up proxy colliders
	for collider in interior_proxy_colliders:
		if collider.is_valid():
			PhysicsServer3D.free_rid(collider)

	if dock_proxy_body.is_valid():
		PhysicsServer3D.free_rid(dock_proxy_body)
