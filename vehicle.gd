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

	# Front wall - OPENING (completely open entrance, no obstruction)
	# No front wall mesh or collision - fully open for entry/exit

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

	# No front collision - fully open entrance

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
	# KINEMATIC colliders in proxy world - player can collide with these
	# These move with the dock_proxy_body when ship is docked
	# SCALED 3x to match exterior
	if not physics_proxy:
		push_warning("PhysicsProxy not assigned to Vehicle")
		return

	var proxy_space = physics_proxy.get_proxy_interior_space()
	interior_proxy_colliders = []

	var size_scale = 3.0

	# Floor collider - Match exterior width exactly
	# Width: 3.0 * size_scale (9 units) matches exterior walls at ±9
	# Length: 5.0 * size_scale (15 units) matches exterior 15 units
	var floor_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(floor_shape, Vector3(3.0 * size_scale, 0.05, 5.0 * size_scale))

	var floor_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(floor_body, PhysicsServer3D.BODY_MODE_KINEMATIC)  # Changed from STATIC
	PhysicsServer3D.body_set_space(floor_body, proxy_space)
	PhysicsServer3D.body_add_shape(floor_body, floor_shape)
	PhysicsServer3D.body_set_state(floor_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(0, -1.4 * size_scale, 0)))
	interior_proxy_colliders.append(floor_body)

	# Left wall collider - matches floor length and width
	var left_wall_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(left_wall_shape, Vector3(0.05, 1.25 * size_scale, 5.0 * size_scale))

	var left_wall_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(left_wall_body, PhysicsServer3D.BODY_MODE_KINEMATIC)  # Changed from STATIC
	PhysicsServer3D.body_set_space(left_wall_body, proxy_space)
	PhysicsServer3D.body_add_shape(left_wall_body, left_wall_shape)
	PhysicsServer3D.body_set_state(left_wall_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(-3.0 * size_scale, 0, 0)))
	interior_proxy_colliders.append(left_wall_body)

	# Right wall collider - matches floor length and width
	var right_wall_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(right_wall_shape, Vector3(0.05, 1.25 * size_scale, 5.0 * size_scale))

	var right_wall_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(right_wall_body, PhysicsServer3D.BODY_MODE_KINEMATIC)  # Changed from STATIC
	PhysicsServer3D.body_set_space(right_wall_body, proxy_space)
	PhysicsServer3D.body_add_shape(right_wall_body, right_wall_shape)
	PhysicsServer3D.body_set_state(right_wall_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(3.0 * size_scale, 0, 0)))
	interior_proxy_colliders.append(right_wall_body)

	# Back wall collider - matches floor width
	var back_wall_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(back_wall_shape, Vector3(3.0 * size_scale, 1.25 * size_scale, 0.05))

	var back_wall_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(back_wall_body, PhysicsServer3D.BODY_MODE_KINEMATIC)  # Changed from STATIC
	PhysicsServer3D.body_set_space(back_wall_body, proxy_space)
	PhysicsServer3D.body_add_shape(back_wall_body, back_wall_shape)
	PhysicsServer3D.body_set_state(back_wall_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(0, 0, -5.0 * size_scale)))
	interior_proxy_colliders.append(back_wall_body)

	# Ceiling collider - matches floor dimensions
	var ceiling_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(ceiling_shape, Vector3(3.0 * size_scale, 0.05, 5.0 * size_scale))

	var ceiling_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(ceiling_body, PhysicsServer3D.BODY_MODE_KINEMATIC)  # Changed from STATIC
	PhysicsServer3D.body_set_space(ceiling_body, proxy_space)
	PhysicsServer3D.body_add_shape(ceiling_body, ceiling_shape)
	PhysicsServer3D.body_set_state(ceiling_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(0, 1.4 * size_scale, 0)))
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
	# Create vehicle physics body in proxy interior space (for when vehicle is docked)
	# The docked ship shares the same physics space as the player/station interior
	if not physics_proxy:
		return

	var proxy_space = physics_proxy.get_proxy_interior_space()

	var vehicle_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(vehicle_shape, Vector3(3, 1.5, 5))

	dock_proxy_body = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(dock_proxy_body, PhysicsServer3D.BODY_MODE_RIGID)
	PhysicsServer3D.body_set_space(dock_proxy_body, proxy_space)
	PhysicsServer3D.body_add_shape(dock_proxy_body, vehicle_shape)
	PhysicsServer3D.body_set_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3.ZERO))

	# Physics parameters for docked ship
	PhysicsServer3D.body_set_param(dock_proxy_body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 1.0)  # Normal gravity
	PhysicsServer3D.body_set_param(dock_proxy_body, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP, 2.0)  # Same as exterior_body
	PhysicsServer3D.body_set_param(dock_proxy_body, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, 2.0)  # Same as exterior_body
	PhysicsServer3D.body_set_param(dock_proxy_body, PhysicsServer3D.BODY_PARAM_MASS, 1000.0)  # Same as exterior_body

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
		# Ship is docked: transform dock proxy position (in proxy space) to world space
		var proxy_transform: Transform3D = PhysicsServer3D.body_get_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM)

		# DEBUG: Monitor dock_proxy_body state every frame
		var dock_vel = PhysicsServer3D.body_get_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
		if dock_vel.length() > 0.001:  # Only log if moving
			print("[DOCK MONITOR] Ship moving! Vel: ", dock_vel, " | Pos Y: ", proxy_transform.origin.y)

		# CRITICAL: Update interior collider positions to match dock_proxy_body
		# The interior colliders need to move with the ship when docked
		_update_interior_colliders_position(proxy_transform)

		# Get parent container (we need to find the container in the scene)
		var container = get_parent().get_node_or_null("VehicleContainer")
		if container and container.exterior_body:
			var container_transform = container.exterior_body.global_transform

			# Convert from proxy space to container local space
			# Proxy Y=50 is station floor, Container local Y=-21 is station floor
			# So: container_local_y = proxy_y - 50 + (-21) = proxy_y - 71
			var station_floor_proxy = VehicleContainer.STATION_PROXY_Y_OFFSET  # 50
			var station_floor_local = -21.0  # Container exterior floor at y=-21 in local space
			var y_offset = station_floor_local - station_floor_proxy  # -71

			var local_pos = Vector3(
				proxy_transform.origin.x,
				proxy_transform.origin.y + y_offset,
				proxy_transform.origin.z
			)
			var local_transform = Transform3D(proxy_transform.basis, local_pos)

			# Transform container local position to world space
			var world_transform = container_transform * local_transform
			exterior_body.global_transform = world_transform
	elif exterior_body:
		# Ship in world space: exterior_body controls its own position (physics drives it)
		pass

	# Interior visuals automatically rotate with exterior_body (they're parented to it)

func apply_thrust(direction: Vector3, force: float) -> void:
	if is_docked and dock_proxy_body.is_valid():
		# Apply thrust in proxy interior space
		# Direction comes in world space from exterior_body.basis
		# Need to transform to proxy space where dock_proxy_body lives
		var container = get_parent().get_node_or_null("VehicleContainer")
		if container and container.exterior_body:
			var container_transform = container.exterior_body.global_transform
			# Transform world direction to container local (which matches proxy space orientation)
			var proxy_direction = container_transform.basis.inverse() * direction

			print("[THRUST DEBUG] World direction: ", direction, " | Proxy direction: ", proxy_direction)

			var impulse = proxy_direction * force * get_process_delta_time()
			var current_vel = PhysicsServer3D.body_get_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
			var new_vel = current_vel + impulse

			print("[THRUST DEBUG] Old vel: ", current_vel, " | Impulse: ", impulse, " | New vel: ", new_vel)

			PhysicsServer3D.body_set_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, new_vel)

			# Immediately verify the velocity was set
			var verify_vel = PhysicsServer3D.body_get_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
			var proxy_pos = PhysicsServer3D.body_get_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM).origin
			print("[THRUST DEBUG] Verified vel: ", verify_vel, " | Proxy pos: ", proxy_pos)
	elif exterior_body:
		# Apply thrust in world
		exterior_body.apply_central_force(direction * force)

func apply_rotation(axis: Vector3, torque: float) -> void:
	if is_docked and dock_proxy_body.is_valid():
		# Apply rotation in proxy interior space
		# Axis comes in world space, need to transform to container local space
		var container = get_parent().get_node_or_null("VehicleContainer")
		if container and container.exterior_body:
			var container_transform = container.exterior_body.global_transform
			var local_axis = container_transform.basis.inverse() * axis
			var angular_impulse = local_axis * torque * get_process_delta_time()
			var current_angvel = PhysicsServer3D.body_get_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
			var new_angvel = current_angvel + angular_impulse
			PhysicsServer3D.body_set_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, new_angvel)
	elif exterior_body:
		# Apply rotation in world
		exterior_body.apply_torque(axis * torque)

func toggle_magnetism() -> void:
	if is_docked and physics_proxy:
		magnetism_enabled = !magnetism_enabled
		physics_proxy.set_proxy_interior_gravity(magnetism_enabled)

func set_docked(docked: bool) -> void:
	if docked and not is_docked:
		# Ship is entering dock - transfer position from world to proxy interior space
		if exterior_body and dock_proxy_body.is_valid():
			# Get container to transform world position to container local space
			var container = get_parent().get_node_or_null("VehicleContainer")
			if container and container.exterior_body:
				var container_transform = container.exterior_body.global_transform
				var world_transform = exterior_body.global_transform

				# Transform world position to container local space
				var relative_transform = container_transform.inverse() * world_transform

				# DEBUG: Log world velocity before docking
				var world_vel = exterior_body.linear_velocity
				print("[DOCK DEBUG] World velocity before docking: ", world_vel)

				# Place ship in proxy interior space at station floor level (Y=50)
				# CRITICAL: Ship's interior floor is at dock_proxy_body.Y + (-1.4 * size_scale)
				# We want interior floor at station floor level (Y=50), so:
				# dock_proxy_body.Y + (-4.2) = 50
				# dock_proxy_body.Y = 50 + 4.2 = 54.2
				var station_floor_y = VehicleContainer.STATION_PROXY_Y_OFFSET  # 50
				var ship_floor_offset = -1.4 * 3.0  # -4.2 (interior floor relative to center)
				var ship_center_y = station_floor_y - ship_floor_offset + 0.1  # 54.3 (0.1 units above floor)
				var proxy_pos = Vector3(
					relative_transform.origin.x,
					ship_center_y,
					relative_transform.origin.z
				)
				var proxy_transform = Transform3D(relative_transform.basis, proxy_pos)

				# Set dock proxy body to this proxy position
				PhysicsServer3D.body_set_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM, proxy_transform)
				print("[DOCK DEBUG] Dock transform set to: ", proxy_transform.origin)
				print("[DOCK DEBUG] Ship center Y: ", ship_center_y, " | Interior floor should be at Y: ", ship_center_y + ship_floor_offset)

				# Zero out velocities so ship doesn't bounce
				PhysicsServer3D.body_set_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
				PhysicsServer3D.body_set_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)

				# Ship is in RIGID mode and will fall to floor with gravity
				var verify_vel = PhysicsServer3D.body_get_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
				var body_mode = PhysicsServer3D.body_get_mode(dock_proxy_body)
				var space_rid = PhysicsServer3D.body_get_space(dock_proxy_body)
				print("[DOCK DEBUG] Immediately after - Velocity: ", verify_vel, " | Position Y: ", proxy_transform.origin.y, " | Mode: ", body_mode)
				print("[DOCK DEBUG] Space RID: ", space_rid, " | Expected proxy_interior_space: ", physics_proxy.get_proxy_interior_space())
	elif not docked and is_docked:
		# Ship is leaving dock - transfer position from dock proxy to world
		if exterior_body and dock_proxy_body.is_valid():
			var container = get_parent().get_node_or_null("VehicleContainer")
			if container and container.exterior_body:
				var container_transform = container.exterior_body.global_transform
				var dock_transform = PhysicsServer3D.body_get_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM)

				# Transform dock proxy position to world space
				var world_transform = container_transform * dock_transform

				# Set exterior body to this world position
				exterior_body.global_transform = world_transform

				# Copy velocity
				var local_velocity = PhysicsServer3D.body_get_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
				var world_velocity = container_transform.basis * local_velocity
				exterior_body.linear_velocity = world_velocity

				# Copy angular velocity
				var local_angvel = PhysicsServer3D.body_get_state(dock_proxy_body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
				var world_angvel = container_transform.basis * local_angvel
				exterior_body.angular_velocity = world_angvel

				# Switch back to RIGID mode - ship is now free-flying
				PhysicsServer3D.body_set_mode(dock_proxy_body, PhysicsServer3D.BODY_MODE_RIGID)

	is_docked = docked

func _exit_tree() -> void:
	# Clean up proxy colliders
	for collider in interior_proxy_colliders:
		if collider.is_valid():
			PhysicsServer3D.free_rid(collider)

	if dock_proxy_body.is_valid():
		PhysicsServer3D.free_rid(dock_proxy_body)
