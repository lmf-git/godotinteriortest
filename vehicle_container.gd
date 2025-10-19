class_name VehicleContainer
extends Node3D

## VehicleContainer with exterior physics and proxy interior system
## Similar to vehicle but larger, with docking bay for vehicles

@export var physics_proxy: PhysicsProxy
@export var size_multiplier: float = 5.0  # How many times larger than ship (default: 5x ship = 15x base)

# Station proxy Y offset in proxy space - MUST be different from ship to avoid overlap!
# Ship floor: y=-4.2, Station floor: y=50 (small), y=100 (medium), y=150 (large)
# Each container size gets its own Y offset to avoid collisions in proxy space
const STATION_PROXY_Y_OFFSET_BASE: float = 50.0
var station_proxy_y_offset: float = 0.0  # Set in _ready()

# VehicleContainer components
var exterior_body: RigidBody3D  # VehicleContainer exterior in world
var interior_proxy_colliders: Array[RID]  # Static colliders in this container's proxy space
var container_interior_space: RID  # This container's OWN proxy interior space
var dock_proxy_body: RID  # This container's body when docked in a larger container
var transition_zone: Area3D  # Zone where vehicles/players can transition to interior
var is_docked: bool = false  # Is this container docked in a larger container?

func _ready() -> void:
	# Calculate unique Y offset based on size to avoid proxy space collisions
	# Small (5x): Y=50, Medium (10x): Y=100, Large (15x): Y=150
	station_proxy_y_offset = STATION_PROXY_Y_OFFSET_BASE * (size_multiplier / 5.0)

	# Create this container's OWN physics space for its interior
	_create_container_physics_space()

	_create_container_exterior()
	_create_container_proxy_interior()
	_create_container_dock_proxy()
	_create_transition_zone()

func _create_container_physics_space() -> void:
	# Each container has its own interior physics space for recursive nesting
	container_interior_space = PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(container_interior_space, true)  # Keep always active to avoid initialization issues

	# Create gravity for this container's interior
	var gravity_area = PhysicsServer3D.area_create()
	PhysicsServer3D.area_set_space(gravity_area, container_interior_space)
	PhysicsServer3D.area_set_param(gravity_area, PhysicsServer3D.AREA_PARAM_GRAVITY, 9.8)
	PhysicsServer3D.area_set_param(gravity_area, PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR, Vector3(0, -1, 0))
	PhysicsServer3D.area_set_param(gravity_area, PhysicsServer3D.AREA_PARAM_GRAVITY_IS_POINT, false)

	var large_box_shape = PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(large_box_shape, Vector3(10000, 10000, 10000))
	PhysicsServer3D.area_add_shape(gravity_area, large_box_shape)
	PhysicsServer3D.area_set_shape_transform(gravity_area, 0, Transform3D(Basis(), Vector3.ZERO))

func _physics_process(_delta: float) -> void:
	# Interior colliders are STATIC and don't need updates
	# They stay at fixed positions in the container's interior space
	pass

func _is_player_in_container() -> bool:
	# Check if player is in this container's interior
	var game_manager = get_parent()
	if not game_manager:
		return false

	for child in game_manager.get_children():
		if child is CharacterController:
			return child.is_in_container

	return false

func _refresh_interior_colliders() -> void:
	# Re-set collider transforms to keep them active for collision detection
	# Station colliders are stationary, but need to be refreshed each frame
	if interior_proxy_colliders.size() == 0:
		return

	# Ship is 3x base, container is size_multiplier times ship
	var size_scale = 3.0 * size_multiplier

	# Fixed positions for container interior colliders in its own coordinate system
	var collider_positions = [
		Vector3(0, -1.4 * size_scale, 0),  # Floor
		Vector3(-3.0 * size_scale, 0, 0),  # Left wall
		Vector3(3.0 * size_scale, 0, 0),  # Right wall
		Vector3(0, 0, -5.0 * size_scale),  # Back wall
		Vector3(0, 1.4 * size_scale, 0)  # Ceiling
	]

	# Update each collider to maintain collision detection
	for i in range(min(interior_proxy_colliders.size(), collider_positions.size())):
		var collider = interior_proxy_colliders[i]
		if collider.is_valid():
			var collider_transform = Transform3D(Basis(), collider_positions[i])
			PhysicsServer3D.body_set_state(collider, PhysicsServer3D.BODY_STATE_TRANSFORM, collider_transform)

func _create_container_exterior() -> void:
	# Create container as SCALED UP VERSION OF SHIP (exactly like ship but bigger)
	exterior_body = RigidBody3D.new()
	exterior_body.name = "ExteriorBody"
	exterior_body.mass = 50000.0 * size_multiplier  # Mass scales with size
	exterior_body.gravity_scale = 1.0  # Enable gravity so it sits on ground
	exterior_body.linear_damp = 5.0  # Heavy damping - it's a station
	exterior_body.angular_damp = 5.0
	add_child(exterior_body)

	var material := StandardMaterial3D.new()
	# Use slightly different color than ship to distinguish containers
	material.albedo_color = Color(0.7, 0.75, 0.8)  # Slightly blue-gray
	material.metallic = 0.3
	material.roughness = 0.7

	# Container is size_multiplier times ship size
	# Ship base dimensions (scale 1): 6 wide, 3 tall, 10 long
	# Ship dimensions (3x): 18 wide, 9 tall, 30 long
	# Container dimensions: size_multiplier * ship size
	var size_scale = 3.0 * size_multiplier

	# Floor (same proportions as ship)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = BoxMesh.new()
	floor_mesh.mesh.size = Vector3(6 * size_scale, 0.2, 10 * size_scale)
	floor_mesh.material_override = material
	floor_mesh.position = Vector3(0, -1.4 * size_scale, 0)
	floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	exterior_body.add_child(floor_mesh)

	var floor_collision := CollisionShape3D.new()
	floor_collision.shape = BoxShape3D.new()
	floor_collision.shape.size = Vector3(6 * size_scale, 0.2, 10 * size_scale)
	floor_collision.position = Vector3(0, -1.4 * size_scale, 0)
	exterior_body.add_child(floor_collision)

	# Left wall (same proportions as ship)
	var left_wall := MeshInstance3D.new()
	left_wall.mesh = BoxMesh.new()
	left_wall.mesh.size = Vector3(0.2, 3 * size_scale, 10 * size_scale)
	left_wall.material_override = material
	left_wall.position = Vector3(-3 * size_scale, 0, 0)
	exterior_body.add_child(left_wall)

	var left_collision := CollisionShape3D.new()
	left_collision.shape = BoxShape3D.new()
	left_collision.shape.size = Vector3(0.2, 3 * size_scale, 10 * size_scale)
	left_collision.position = Vector3(-3 * size_scale, 0, 0)
	exterior_body.add_child(left_collision)

	# Right wall (same proportions as ship)
	var right_wall := MeshInstance3D.new()
	right_wall.mesh = BoxMesh.new()
	right_wall.mesh.size = Vector3(0.2, 3 * size_scale, 10 * size_scale)
	right_wall.material_override = material
	right_wall.position = Vector3(3 * size_scale, 0, 0)
	exterior_body.add_child(right_wall)

	var right_collision := CollisionShape3D.new()
	right_collision.shape = BoxShape3D.new()
	right_collision.shape.size = Vector3(0.2, 3 * size_scale, 10 * size_scale)
	right_collision.position = Vector3(3 * size_scale, 0, 0)
	exterior_body.add_child(right_collision)

	# Back wall (same proportions as ship)
	var back_wall := MeshInstance3D.new()
	back_wall.mesh = BoxMesh.new()
	back_wall.mesh.size = Vector3(6 * size_scale, 3 * size_scale, 0.2)
	back_wall.material_override = material
	back_wall.position = Vector3(0, 0, -5 * size_scale)
	exterior_body.add_child(back_wall)

	var back_collision := CollisionShape3D.new()
	back_collision.shape = BoxShape3D.new()
	back_collision.shape.size = Vector3(6 * size_scale, 3 * size_scale, 0.2)
	back_collision.position = Vector3(0, 0, -5 * size_scale)
	exterior_body.add_child(back_collision)

	# Front wall - OPENING (completely open entrance, no obstruction)
	# No front wall mesh or collision - fully open for entry/exit

	# Ceiling (same proportions as ship)
	var ceiling := MeshInstance3D.new()
	ceiling.mesh = BoxMesh.new()
	ceiling.mesh.size = Vector3(6 * size_scale, 0.2, 10 * size_scale)
	ceiling.material_override = material
	ceiling.position = Vector3(0, 1.4 * size_scale, 0)
	exterior_body.add_child(ceiling)

	var ceiling_collision := CollisionShape3D.new()
	ceiling_collision.shape = BoxShape3D.new()
	ceiling_collision.shape.size = Vector3(6 * size_scale, 0.2, 10 * size_scale)
	ceiling_collision.position = Vector3(0, 1.4 * size_scale, 0)
	exterior_body.add_child(ceiling_collision)

func _create_container_proxy_interior() -> void:
	# Create STATIC colliders in THIS container's own physics space
	# These colliders are for objects/players inside this container
	if not container_interior_space.is_valid():
		push_warning("Container interior space not created")
		return

	interior_proxy_colliders = []

	var size_scale = 3.0 * size_multiplier

	# Floor collider - at different Y than ship!
	var floor_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(floor_shape, Vector3(3.0 * size_scale, 0.05, 5.0 * size_scale))

	var floor_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(floor_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(floor_body, container_interior_space)  # Use container's own space
	PhysicsServer3D.body_add_shape(floor_body, floor_shape)
	# Floor at Y=0 in container's own coordinate system (not offset like before)
	PhysicsServer3D.body_set_state(floor_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(0, -1.4 * size_scale, 0)))
	# Enable collision with docked ships and players
	PhysicsServer3D.body_set_collision_layer(floor_body, 1)
	PhysicsServer3D.body_set_collision_mask(floor_body, 1)
	interior_proxy_colliders.append(floor_body)

	# Left wall - at station proxy Y offset
	var left_wall_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(left_wall_shape, Vector3(0.05, 1.25 * size_scale, 5.0 * size_scale))

	var left_wall_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(left_wall_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(left_wall_body, container_interior_space)
	PhysicsServer3D.body_add_shape(left_wall_body, left_wall_shape)
	PhysicsServer3D.body_set_state(left_wall_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(-3.0 * size_scale, 0, 0)))
	# Enable collision with docked ships and players
	PhysicsServer3D.body_set_collision_layer(left_wall_body, 1)
	PhysicsServer3D.body_set_collision_mask(left_wall_body, 1)
	interior_proxy_colliders.append(left_wall_body)

	# Right wall - at station proxy Y offset
	var right_wall_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(right_wall_shape, Vector3(0.05, 1.25 * size_scale, 5.0 * size_scale))

	var right_wall_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(right_wall_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(right_wall_body, container_interior_space)
	PhysicsServer3D.body_add_shape(right_wall_body, right_wall_shape)
	PhysicsServer3D.body_set_state(right_wall_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(3.0 * size_scale, 0, 0)))
	# Enable collision with docked ships and players
	PhysicsServer3D.body_set_collision_layer(right_wall_body, 1)
	PhysicsServer3D.body_set_collision_mask(right_wall_body, 1)
	interior_proxy_colliders.append(right_wall_body)

	# Back wall - at station proxy Y offset
	var back_wall_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(back_wall_shape, Vector3(3.0 * size_scale, 1.25 * size_scale, 0.05))

	var back_wall_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(back_wall_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(back_wall_body, container_interior_space)
	PhysicsServer3D.body_add_shape(back_wall_body, back_wall_shape)
	PhysicsServer3D.body_set_state(back_wall_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(0, 0, -5.0 * size_scale)))
	# Enable collision with docked ships and players
	PhysicsServer3D.body_set_collision_layer(back_wall_body, 1)
	PhysicsServer3D.body_set_collision_mask(back_wall_body, 1)
	interior_proxy_colliders.append(back_wall_body)

	# Ceiling - at station proxy Y offset + ceiling height
	var ceiling_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(ceiling_shape, Vector3(3.0 * size_scale, 0.05, 5.0 * size_scale))

	var ceiling_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(ceiling_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(ceiling_body, container_interior_space)
	PhysicsServer3D.body_add_shape(ceiling_body, ceiling_shape)
	PhysicsServer3D.body_set_state(ceiling_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(0, 1.4 * size_scale, 0)))
	# Enable collision with docked ships and players
	PhysicsServer3D.body_set_collision_layer(ceiling_body, 1)
	PhysicsServer3D.body_set_collision_mask(ceiling_body, 1)
	interior_proxy_colliders.append(ceiling_body)

	# Note: No front wall collider - this is the opening where players can enter

func _create_container_dock_proxy() -> void:
	# Create THIS container's body for when it's docked in a LARGER container
	# This allows containers to be nested recursively
	# The dock_proxy_body will be placed in the parent container's interior space

	var size_scale = 3.0 * size_multiplier
	var container_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(container_shape, Vector3(3.0 * size_scale, 1.5 * size_scale, 5.0 * size_scale))

	dock_proxy_body = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(dock_proxy_body, PhysicsServer3D.BODY_MODE_RIGID)
	# Space will be set when container docks in a parent container
	PhysicsServer3D.body_add_shape(dock_proxy_body, container_shape)
	PhysicsServer3D.body_set_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3.ZERO))

	PhysicsServer3D.body_set_param(dock_proxy_body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 1.0)
	PhysicsServer3D.body_set_param(dock_proxy_body, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP, 5.0)
	PhysicsServer3D.body_set_param(dock_proxy_body, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, 5.0)
	PhysicsServer3D.body_set_param(dock_proxy_body, PhysicsServer3D.BODY_PARAM_MASS, 50000.0 * size_multiplier)

func _create_transition_zone() -> void:
	# Create invisible trigger zone at container entrance
	# Match ship entrance zone proportions scaled by size_multiplier
	transition_zone = Area3D.new()
	transition_zone.name = "TransitionZone"
	add_child(transition_zone)

	var zone_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	# Ship entrance zone: Vector3(10, 8, 3) at z=16.5
	# Container entrance zone: size_multiplier times larger
	box_shape.size = Vector3(10 * size_multiplier, 8 * size_multiplier, 3 * size_multiplier)
	zone_shape.shape = box_shape
	transition_zone.add_child(zone_shape)

	transition_zone.position = Vector3(0, 0, 16.5 * size_multiplier)  # At container entrance
	transition_zone.monitoring = true
	transition_zone.monitorable = true

func apply_rotation(axis: Vector3, torque: float) -> void:
	if exterior_body:
		exterior_body.apply_torque(axis * torque)

func apply_thrust(direction: Vector3, force: float) -> void:
	if exterior_body:
		exterior_body.apply_central_force(direction * force)

func get_interior_space() -> RID:
	# Return this container's interior physics space
	return container_interior_space

func set_docked(docked: bool, parent_container: VehicleContainer = null) -> void:
	if docked and not is_docked:
		# Container entering dock in parent container
		if exterior_body and dock_proxy_body.is_valid() and parent_container:
			# CRITICAL: Set dock_proxy_body's space to parent container's interior space
			var parent_interior_space = parent_container.get_interior_space()
			if not parent_interior_space.is_valid():
				push_error("Parent container interior space not valid!")
				return
			PhysicsServer3D.body_set_space(dock_proxy_body, parent_interior_space)

			var parent_transform = parent_container.exterior_body.global_transform
			var world_transform = exterior_body.global_transform

			# Transform world position to parent container's local space (relative coordinates)
			var relative_transform = parent_transform.inverse() * world_transform

			# Place container in parent's interior space at floor level
			# Parent floor is at y = -1.4 * parent_size_scale
			# This container floor is at y = this_center + (-1.4 * this_size_scale)
			var parent_size = 3.0 * parent_container.size_multiplier
			var parent_floor_y = -1.4 * parent_size
			var this_floor_offset = -1.4 * 3.0 * size_multiplier
			var this_center_y = parent_floor_y - this_floor_offset + 0.1  # 0.1 units above parent floor
			var proxy_pos = Vector3(
				relative_transform.origin.x,
				this_center_y,
				relative_transform.origin.z
			)
			var proxy_transform = Transform3D(relative_transform.basis, proxy_pos)

			# Set dock proxy body to this position in parent's interior space
			PhysicsServer3D.body_set_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM, proxy_transform)

			# Zero out velocities
			PhysicsServer3D.body_set_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
			PhysicsServer3D.body_set_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
	elif not docked and is_docked:
		# Container leaving dock - transfer position from parent's interior space to world
		if exterior_body and dock_proxy_body.is_valid() and parent_container:
			var parent_transform = parent_container.exterior_body.global_transform
			var dock_transform = PhysicsServer3D.body_get_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM)

			# Transform dock proxy position (in parent's interior space) to world space
			var world_transform = parent_transform * dock_transform

			# Set exterior body to this world position
			exterior_body.global_transform = world_transform

			# Copy velocity from parent's interior space to world space
			var local_velocity = PhysicsServer3D.body_get_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
			var world_velocity = parent_transform.basis * local_velocity
			exterior_body.linear_velocity = world_velocity

			# Copy angular velocity
			var local_angvel = PhysicsServer3D.body_get_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
			var world_angvel = parent_transform.basis * local_angvel
			exterior_body.angular_velocity = world_angvel

			# Remove dock_proxy_body from parent's interior space
			PhysicsServer3D.body_set_space(dock_proxy_body, RID())

	is_docked = docked

func _process(_delta: float) -> void:
	# Update exterior body visual based on docked state
	# This is needed for nested containers - the small container's exterior must follow its dock_proxy_body
	if is_docked and dock_proxy_body.is_valid() and exterior_body:
		# Container is docked: find parent container and transform position
		var game_manager = get_parent()
		if game_manager:
			# Find the parent container (the one we're docked in)
			for child in game_manager.get_children():
				if child is VehicleContainer and child != self:
					var parent_container = child as VehicleContainer
					# Check if we're docked in this parent (larger container)
					# For now, assume small docks in large if both exist
					if parent_container.size_multiplier > size_multiplier:
						var proxy_transform: Transform3D = PhysicsServer3D.body_get_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM)
						var parent_transform = parent_container.exterior_body.global_transform

						# Transform from parent's interior space to world space
						var world_transform = parent_transform * proxy_transform
						exterior_body.global_transform = world_transform
						break
	elif exterior_body:
		# Container in world space: exterior_body controls its own position
		pass

func _exit_tree() -> void:
	# Clean up proxy colliders
	for collider in interior_proxy_colliders:
		if collider.is_valid():
			PhysicsServer3D.free_rid(collider)

	# Clean up this container's physics space
	if container_interior_space.is_valid():
		PhysicsServer3D.free_rid(container_interior_space)

	# Clean up dock proxy body
	if dock_proxy_body.is_valid():
		PhysicsServer3D.free_rid(dock_proxy_body)
