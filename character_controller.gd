class_name CharacterController
extends Node3D

## Character controller with world/proxy physics switching
## Handles movement in both world space and proxy interior spaces

@export var physics_proxy: PhysicsProxy
@export var move_speed: float = 5.0
@export var run_speed: float = 10.0
@export var jump_force: float = 8.0

# Character bodies
var world_body: RID  # Character in main world (when outside vehicles)
var proxy_body: RID  # Character in proxy interior (when inside vehicles)
var character_visual: MeshInstance3D  # Character mesh

# State
var is_in_vehicle: bool = true
var is_in_container: bool = false
var current_space: String = "vehicle_interior"  # 'vehicle_interior', 'space', 'container_interior'
var transition_lock: bool = false  # Prevents movement during transition frame

# Visual orientation transition
# Transitions smoothly when moving between spaces, but stays fixed when space rotates
var target_visual_basis: Basis = Basis.IDENTITY
var current_visual_basis: Basis = Basis.IDENTITY
var visual_orientation_speed: float = 5.0  # How fast to transition orientation
var is_transitioning: bool = false  # True during space transitions, false otherwise

# Input
var input_direction: Vector3 = Vector3.ZERO
var jump_pressed: bool = false
var is_running: bool = false

func _ready() -> void:
	_create_character_visual()
	_create_world_body()
	_create_proxy_body()

	# Start OUTSIDE vehicle in world space
	is_in_vehicle = false
	current_space = "space"

func _create_character_visual() -> void:
	# Character visual mesh
	character_visual = MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.4
	character_visual.mesh = capsule
	character_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 1.0, 0.2)
	material.emission_enabled = true
	material.emission = Color(0.1, 0.3, 0.1)
	material.emission_energy_multiplier = 0.5
	character_visual.material_override = material

	add_child(character_visual)

func _create_world_body() -> void:
	# Character body in main world (for when outside vehicles)
	if not physics_proxy:
		push_warning("PhysicsProxy not assigned to CharacterController")
		return

	var world_space = physics_proxy.get_world_space()

	var capsule_shape := PhysicsServer3D.capsule_shape_create()
	PhysicsServer3D.shape_set_data(capsule_shape, {"radius": 0.3, "height": 1.4})

	world_body = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(world_body, PhysicsServer3D.BODY_MODE_RIGID)
	PhysicsServer3D.body_set_space(world_body, world_space)
	PhysicsServer3D.body_add_shape(world_body, capsule_shape)

	# Use parent position for initial spawn
	var spawn_pos = global_position
	PhysicsServer3D.body_set_state(world_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), spawn_pos))

	# Lock rotations for character
	PhysicsServer3D.body_set_axis_lock(world_body, PhysicsServer3D.BODY_AXIS_ANGULAR_X, true)
	PhysicsServer3D.body_set_axis_lock(world_body, PhysicsServer3D.BODY_AXIS_ANGULAR_Y, true)
	PhysicsServer3D.body_set_axis_lock(world_body, PhysicsServer3D.BODY_AXIS_ANGULAR_Z, true)

	# Enable collision settings
	PhysicsServer3D.body_set_collision_layer(world_body, 1)
	PhysicsServer3D.body_set_collision_mask(world_body, 1)
	PhysicsServer3D.body_set_state(world_body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)

func _create_proxy_body() -> void:
	# Character body for proxy interiors (vehicles/containers)
	# Space will be dynamically set based on which vehicle/container player enters
	# Each vehicle/container has its own interior physics space for recursive nesting
	var capsule_shape := PhysicsServer3D.capsule_shape_create()
	PhysicsServer3D.shape_set_data(capsule_shape, {"radius": 0.3, "height": 1.4})

	proxy_body = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(proxy_body, PhysicsServer3D.BODY_MODE_RIGID)
	# NOTE: Space not set here - will be dynamically set when entering vehicle/container
	PhysicsServer3D.body_add_shape(proxy_body, capsule_shape)
	PhysicsServer3D.body_set_state(proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3.ZERO))

	# Lock rotations for character
	PhysicsServer3D.body_set_axis_lock(proxy_body, PhysicsServer3D.BODY_AXIS_ANGULAR_X, true)
	PhysicsServer3D.body_set_axis_lock(proxy_body, PhysicsServer3D.BODY_AXIS_ANGULAR_Y, true)
	PhysicsServer3D.body_set_axis_lock(proxy_body, PhysicsServer3D.BODY_AXIS_ANGULAR_Z, true)

	# Enable collision settings
	PhysicsServer3D.body_set_collision_layer(proxy_body, 1)
	PhysicsServer3D.body_set_collision_mask(proxy_body, 1)
	PhysicsServer3D.body_set_state(proxy_body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)

	# Add damping for stability in proxy space
	PhysicsServer3D.body_set_param(proxy_body, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP, 0.1)
	PhysicsServer3D.body_set_param(proxy_body, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, 1.0)

func _physics_process(delta: float) -> void:
	_handle_movement(delta)

	# Clear transition lock AFTER movement is processed
	# This ensures movement is blocked for the full physics frame after position change
	if transition_lock:
		transition_lock = false

func _process(delta: float) -> void:
	# Update visual orientation transition (only when changing spaces)
	_update_visual_orientation_transition(delta)
	
	# Update visual every frame for smooth rendering (not just physics frames)
	_update_character_visual_position(delta)

func _update_visual_orientation_transition(delta: float) -> void:
	# During space transitions, smoothly interpolate toward target
	# During normal movement within a space, instantly match the space orientation
	# This is controlled by is_transitioning flag set during space changes
	
	# Debug: Print transitioning state and orientation
	if Engine.get_frames_drawn() % 120 == 0:
		print("[CHAR ORIENT] is_transitioning: ", is_transitioning)
		if is_transitioning:
			print("[CHAR ORIENT] WARNING: Transitioning when shouldn't be!")
	
	if is_transitioning and not current_visual_basis.is_equal_approx(target_visual_basis):
		# Use slerp for smooth rotation transition between spaces
		var current_quat = Quaternion(current_visual_basis)
		var target_quat = Quaternion(target_visual_basis)
		var interpolated_quat = current_quat.slerp(target_quat, visual_orientation_speed * delta)
		current_visual_basis = Basis(interpolated_quat)
		
		# Check if transition is complete
		if current_visual_basis.is_equal_approx(target_visual_basis):
			is_transitioning = false
	else:
		# Not transitioning - instantly match the target (which tracks current space)
		current_visual_basis = target_visual_basis

func _handle_movement(delta: float) -> void:
	# Use appropriate physics body based on current space
	var current_body = proxy_body if is_in_vehicle or is_in_container else world_body
	if not current_body.is_valid():
		return

	# Block movement during transition frame
	if transition_lock:
		return

	# Get current velocity
	var velocity: Vector3 = PhysicsServer3D.body_get_state(current_body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)

	# Apply gravity manually when in proxy interior (world space uses engine gravity)
	if (is_in_vehicle or is_in_container) and physics_proxy and physics_proxy.gravity_enabled:
		velocity.y -= 9.81 * delta

	# Apply horizontal movement
	if input_direction.length() > 0:
		var current_speed = run_speed if is_running else move_speed
		var move_vec = input_direction.normalized() * current_speed
		velocity.x = move_vec.x
		velocity.z = move_vec.z
	else:
		# Strong damping when not moving to prevent sliding
		velocity.x = lerp(velocity.x, 0.0, 0.5)
		velocity.z = lerp(velocity.z, 0.0, 0.5)
		# Stop completely if velocity is very small
		if abs(velocity.x) < 0.1:
			velocity.x = 0.0
		if abs(velocity.z) < 0.1:
			velocity.z = 0.0

	# Jump (only when on ground - use raycast)
	if jump_pressed:
		var is_grounded = _check_ground(current_body)
		if is_grounded:
			velocity.y = jump_force

	# Set velocity
	PhysicsServer3D.body_set_state(current_body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, velocity)

func _update_character_visual_position(delta: float) -> void:
	# Handle smooth orientation transition when changing spaces
	if is_transitioning:
		# Slerp current_visual_basis toward target_visual_basis
		if not current_visual_basis.is_equal_approx(target_visual_basis):
			var current_quat = Quaternion(current_visual_basis)
			var target_quat = Quaternion(target_visual_basis)
			var interpolated_quat = current_quat.slerp(target_quat, visual_orientation_speed * delta)
			current_visual_basis = Basis(interpolated_quat)
			
			# Check if transition is complete
			if current_visual_basis.is_equal_approx(target_visual_basis):
				is_transitioning = false
		else:
			is_transitioning = false
	
	# Update character visual based on current physics space
	# Uses transitioning basis for smooth orientation changes
	# Also updates target orientation to match current space
	if is_in_container and proxy_body.is_valid():
		# Character in container interior - position relative to container
		# With recursive nesting, proxy_pos is already in container's local coordinate system
		var proxy_transform: Transform3D = PhysicsServer3D.body_get_state(proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM)
		var proxy_pos = proxy_transform.origin

		# Find the SPECIFIC container that the player is in by checking physics spaces
		var player_space = PhysicsServer3D.body_get_space(proxy_body)
		var game_manager = get_parent()
		var found_container = false
		if game_manager:
			for child in game_manager.get_children():
				if child is VehicleContainer:
					var container = child
					var container_space = container.get_interior_space()
					# Check if this is the container the player is actually in
					if container_space == player_space and container.exterior_body:
						found_container = true
						var container_transform = container.exterior_body.global_transform
						var container_basis = container_transform.basis

						# Update target to track container's orientation
						target_visual_basis = container_basis

						# Transform proxy position (in container's interior space) to world space
						# No Y offset needed - coordinates are already relative to container
						var world_pos = container_transform.origin + container_basis * proxy_pos
						character_visual.global_position = world_pos
						# Use transitioning basis (smoothly follows target)
						character_visual.global_transform.basis = current_visual_basis

						# Debug: Print which container we're using for visual
						if Engine.get_frames_drawn() % 60 == 0:  # Every 60 frames
							print("[CHAR VISUAL] In container: ", container.name, " proxy_pos: ", proxy_pos, " world_pos: ", world_pos)
						break

		if not found_container and Engine.get_frames_drawn() % 60 == 0:
			print("[CHAR VISUAL] ERROR: In container but no matching container found!")
	elif is_in_vehicle and proxy_body.is_valid():
		# Character in vehicle interior - position relative to vehicle
		var proxy_transform: Transform3D = PhysicsServer3D.body_get_state(proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM)
		var proxy_pos = proxy_transform.origin

		# Find vehicle through parent tree
		var game_manager = get_parent()
		if game_manager:
			for child in game_manager.get_children():
				if child is Vehicle:
					var vehicle = child

					# CRITICAL: If vehicle is docked, need to use dock_proxy position + container transform
					if vehicle.is_docked and vehicle.dock_proxy_body.is_valid():
						# Get ship's dock_proxy position in container space
						var ship_dock_transform = PhysicsServer3D.body_get_state(vehicle.dock_proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM)

						# Transform player proxy_pos (in ship interior space) to container space
						var container_proxy_pos = ship_dock_transform.origin + ship_dock_transform.basis * proxy_pos

						# Find which container the ship is docked in
						var docked_container = vehicle._get_docked_container()
						if docked_container and docked_container.exterior_body:
							var container_transform = docked_container.exterior_body.global_transform
							var container_basis = container_transform.basis

							# Update target to track ship's orientation in world space
							var ship_world_basis = container_basis * ship_dock_transform.basis
							target_visual_basis = ship_world_basis

							# Transform to world space
							var world_pos = container_transform.origin + container_basis * container_proxy_pos
							character_visual.global_position = world_pos
							# Use transitioning basis (smoothly follows target)
							character_visual.global_transform.basis = current_visual_basis
					elif vehicle.exterior_body:
						# Vehicle not docked - use exterior body transform
						var vehicle_transform = vehicle.exterior_body.global_transform
						var vehicle_basis = vehicle_transform.basis

						# Update target to track ship's orientation
						target_visual_basis = vehicle_basis

						# Transform proxy position to world space
						var world_pos = vehicle_transform.origin + vehicle_basis * proxy_pos
						character_visual.global_position = world_pos
						# Use transitioning basis (smoothly follows target)
						character_visual.global_transform.basis = current_visual_basis
					break
	elif not is_in_vehicle and not is_in_container and world_body.is_valid():
		# Character in world space
		var world_transform: Transform3D = PhysicsServer3D.body_get_state(world_body, PhysicsServer3D.BODY_STATE_TRANSFORM)
		character_visual.global_position = world_transform.origin

		# Update target to world up
		target_visual_basis = Basis.IDENTITY

		# Use transitioning basis (smoothly follows target)
		character_visual.global_transform.basis = current_visual_basis

	# Character visibility handled by camera system
	# Don't set visibility here - let dual_camera_view control it

func _check_ground(body: RID) -> bool:
	# Raycast downward to check if on ground
	if not body.is_valid():
		return false

	# Get body position
	var body_transform: Transform3D = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM)
	var from = body_transform.origin
	var to = from + Vector3(0, -0.8, 0)  # Ray slightly longer than capsule bottom (0.7 capsule height + 0.1 buffer)

	# Get the space the body is in
	var space = PhysicsServer3D.body_get_space(body)

	# Create ray parameters
	var ray_params = PhysicsRayQueryParameters3D.new()
	ray_params.from = from
	ray_params.to = to
	ray_params.exclude = [body]  # Don't hit self

	# Perform raycast using PhysicsDirectSpaceState3D
	var space_state = PhysicsServer3D.space_get_direct_state(space)
	var result = space_state.intersect_ray(ray_params)

	return not result.is_empty()

func set_input_direction(direction: Vector3) -> void:
	input_direction = direction

func set_jump(pressed: bool) -> void:
	jump_pressed = pressed

func set_running(running: bool) -> void:
	is_running = running

func enter_vehicle(should_transition: bool = true, initial_basis: Basis = Basis.IDENTITY) -> void:
	is_in_vehicle = true
	current_space = "vehicle_interior"
	is_transitioning = should_transition  # Start smooth orientation transition only if requested
	
	# If transitioning and initial_basis provided, set it as target
	if should_transition and initial_basis != Basis.IDENTITY:
		target_visual_basis = initial_basis

func exit_vehicle(target_basis: Basis = Basis.IDENTITY) -> void:
	is_in_vehicle = false
	current_space = "space"
	is_transitioning = true  # Start smooth orientation transition
	
	# Set target for smooth transition
	if target_basis != Basis.IDENTITY:
		target_visual_basis = target_basis

func enter_container(target_basis: Basis = Basis.IDENTITY) -> void:
	is_in_container = true
	is_in_vehicle = false
	current_space = "container_interior"
	is_transitioning = true  # Start smooth orientation transition
	
	# Set target for smooth transition
	if target_basis != Basis.IDENTITY:
		target_visual_basis = target_basis

func exit_container(target_basis: Basis = Basis.IDENTITY) -> void:
	is_in_container = false
	current_space = "space"
	is_transitioning = true  # Start smooth orientation transition
	
	# Set target for smooth transition
	if target_basis != Basis.IDENTITY:
		target_visual_basis = target_basis

func set_target_visual_orientation(new_basis: Basis) -> void:
	# Set target orientation for smooth transition between spaces
	# NOTE: This function is no longer used - orientation is tracked automatically
	target_visual_basis = new_basis

func initialize_visual_orientation(initial_basis: Basis) -> void:
	# Initialize orientation at game start (no transition)
	# Sets both current and target so there's no initial lerp
	target_visual_basis = initial_basis
	current_visual_basis = initial_basis

func get_proxy_position() -> Vector3:
	if proxy_body.is_valid():
		var body_transform: Transform3D = PhysicsServer3D.body_get_state(proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM)
		return body_transform.origin
	return Vector3.ZERO

func get_world_position() -> Vector3:
	if world_body.is_valid():
		var body_transform: Transform3D = PhysicsServer3D.body_get_state(world_body, PhysicsServer3D.BODY_STATE_TRANSFORM)
		return body_transform.origin
	return Vector3.ZERO

func get_proxy_velocity() -> Vector3:
	if proxy_body.is_valid():
		return PhysicsServer3D.body_get_state(proxy_body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	return Vector3.ZERO

func get_world_velocity() -> Vector3:
	if world_body.is_valid():
		return PhysicsServer3D.body_get_state(world_body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	return Vector3.ZERO

func set_proxy_position(pos: Vector3, velocity: Vector3 = Vector3.ZERO) -> void:
	if proxy_body.is_valid():
		var body_transform: Transform3D = PhysicsServer3D.body_get_state(proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM)
		body_transform.origin = pos
		PhysicsServer3D.body_set_state(proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM, body_transform)
		# Preserve velocity for seamless transition (or reset if Vector3.ZERO passed)
		PhysicsServer3D.body_set_state(proxy_body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, velocity)
		PhysicsServer3D.body_set_state(proxy_body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
		# Lock movement for one frame to prevent input from pushing player
		transition_lock = true

func set_world_position(pos: Vector3, velocity: Vector3 = Vector3.ZERO) -> void:
	if world_body.is_valid():
		var body_transform: Transform3D = PhysicsServer3D.body_get_state(world_body, PhysicsServer3D.BODY_STATE_TRANSFORM)
		body_transform.origin = pos
		PhysicsServer3D.body_set_state(world_body, PhysicsServer3D.BODY_STATE_TRANSFORM, body_transform)
		# Preserve velocity for seamless transition (or reset if Vector3.ZERO passed)
		PhysicsServer3D.body_set_state(world_body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, velocity)
		PhysicsServer3D.body_set_state(world_body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
		# Lock movement for one frame to prevent input from pushing player
		transition_lock = true

func _exit_tree() -> void:
	# Clean up physics bodies
	if world_body.is_valid():
		PhysicsServer3D.free_rid(world_body)
	if proxy_body.is_valid():
		PhysicsServer3D.free_rid(proxy_body)
