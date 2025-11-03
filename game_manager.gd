extends Node3D

## Main game manager - handles all systems and transitions

var physics_proxy: PhysicsProxy
var character: CharacterController
var vehicle: Vehicle
var vehicle_container_small: VehicleContainer  # 5x ship (default size)
var vehicle_container_large: VehicleContainer  # 10x ship (2x default)
var dual_camera: DualCameraView

# Transition cooldowns to prevent rapid switching
var vehicle_transition_cooldown: float = 0.0
var container_transition_cooldown: float = 0.0
const TRANSITION_COOLDOWN_TIME: float = 0.5  # Half second cooldown

# Debug log debouncing
var last_ship_station_log: Dictionary = {}
var last_docking_log: Dictionary = {}
const LOG_DEBOUNCE_TIME: float = 0.5  # Only log same message every 0.5 seconds

# FPS tracking
var fps_counter: float = 0.0
var fps_update_timer: float = 0.0
const FPS_UPDATE_INTERVAL: float = 0.25  # Update FPS display 4 times per second

# Physics space sleep optimization
var space_sleep_check_timer: float = 0.0
const SPACE_SLEEP_CHECK_INTERVAL: float = 1.0  # Check every second if spaces can sleep

func _debounced_log(category: String, message: String, data: Dictionary) -> void:
	# Only log if different data or enough time has passed
	var current_time = Time.get_ticks_msec() / 1000.0
	var cache_key = category + ":" + message

	if cache_key in last_ship_station_log:
		var last_log = last_ship_station_log[cache_key]
		# Check if data changed significantly or enough time passed
		var data_changed = false
		for key in data:
			if not key in last_log["data"] or abs(last_log["data"][key] - data[key]) > 0.1:
				data_changed = true
				break

		if not data_changed and (current_time - last_log["time"]) < LOG_DEBOUNCE_TIME:
			return  # Skip logging - same data, too soon

	# Log it
	last_ship_station_log[cache_key] = {"time": current_time, "data": data}

func _ready() -> void:
	# Setup lighting FIRST
	_create_lighting()

	# Create ground plane for testing
	_create_ground_plane()

	# Create UI instructions
	_create_instructions_ui()

	# Create physics proxy
	physics_proxy = PhysicsProxy.new()
	add_child(physics_proxy)

	# Wait for physics proxy to initialize (it needs 2 frames)
	await get_tree().process_frame
	await get_tree().process_frame

	# Create vehicle (spawn on ground with opening facing player)
	# Vehicle is now 9 units tall (3*3), so y=4.5 puts bottom at ground level
	vehicle = Vehicle.new()
	vehicle.physics_proxy = physics_proxy
	vehicle.position = Vector3(0, 4.5, 50)  # Spaced further from player
	vehicle.rotation_degrees = Vector3(0, 180, 0)  # Rotate 180° so opening faces player
	add_child(vehicle)

	# Create character OUTSIDE vehicle (starts in world space)
	character = CharacterController.new()
	character.physics_proxy = physics_proxy
	character.position = Vector3(0, 2, -30)  # Spawn behind ship, facing forward
	add_child(character)

	# Initialize character visual orientation (world up)
	character.initialize_visual_orientation(Basis.IDENTITY)

	# Create SMALL vehicle container (5x ship = default)
	# Container is 45 units tall (3*3*5), so y=22.5 puts bottom at ground level (like ship)
	vehicle_container_small = VehicleContainer.new()
	vehicle_container_small.name = "VehicleContainerSmall"
	vehicle_container_small.physics_proxy = physics_proxy
	vehicle_container_small.size_multiplier = 5.0  # 5x ship size (default)
	vehicle_container_small.position = Vector3(0, 22.5, 350)  # Closer container
	vehicle_container_small.rotation_degrees = Vector3(0, 180, 0)  # Rotate 180° so opening faces player
	add_child(vehicle_container_small)

	# Create LARGE vehicle container (10x ship = 2x default size)
	# Container is 90 units tall (3*3*10), so y=45.0 puts bottom at ground level (like ship)
	vehicle_container_large = VehicleContainer.new()
	vehicle_container_large.name = "VehicleContainerLarge"
	vehicle_container_large.physics_proxy = physics_proxy
	vehicle_container_large.size_multiplier = 10.0  # 10x ship size (2x default container)
	vehicle_container_large.position = Vector3(0, 45.0, 750)  # Further back, larger container
	vehicle_container_large.rotation_degrees = Vector3(0, 180, 0)  # Rotate 180° so opening faces player
	add_child(vehicle_container_large)

	# Create dual camera system (it will be current automatically)
	dual_camera = DualCameraView.new()
	dual_camera.character = character
	dual_camera.vehicle = vehicle
	dual_camera.vehicle_container = vehicle_container_small  # Use small container for camera

	# Calculate initial facing towards nearest vehicle
	# Player at z=-30, vehicle at z=50, so need to face +Z direction
	var to_vehicle = (vehicle.position - character.position)
	# atan2 for yaw: atan2(x, z) where default forward is -Z, so we need the angle to rotate
	var initial_yaw = atan2(to_vehicle.x, to_vehicle.z) + PI  # Add PI because default is -Z
	dual_camera.base_rotation.y = initial_yaw

	add_child(dual_camera)

	# Create stars
	_create_stars()

func _create_ground_plane() -> void:
	# Create a HUGE ground plane for testing
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	add_child(ground)

	# Ground mesh - make it MUCH larger (10000x10000)
	var ground_mesh := MeshInstance3D.new()
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(10000, 10000)
	ground_mesh.mesh = plane_mesh
	ground_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # Disable shadows for performance

	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.6, 0.7, 0.6)  # Brighter ground
	ground_material.metallic = 0.0
	ground_material.roughness = 0.8
	ground_mesh.material_override = ground_material
	ground.add_child(ground_mesh)

	# Ground collision - make it 10000x10000
	var ground_collision := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(10000, 0.1, 10000)
	ground_collision.shape = box_shape
	ground.add_child(ground_collision)

func _create_lighting() -> void:
	# 3-Point Lighting Setup - BRIGHT for visibility

	# 1. KEY LIGHT - Main light source (casts shadows)
	var key_light := DirectionalLight3D.new()
	key_light.name = "KeyLight"
	key_light.light_energy = 1.0  # Moderate brightness
	key_light.light_color = Color(1.0, 1.0, 1.0)  # Pure white
	key_light.rotation_degrees = Vector3(-45, -30, 0)
	key_light.shadow_enabled = true
	key_light.shadow_bias = 0.05
	key_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(key_light)

	# 2. FILL LIGHT - Softens shadows from key light
	var fill_light := DirectionalLight3D.new()
	fill_light.name = "FillLight"
	fill_light.light_energy = 0.5  # Soft fill
	fill_light.light_color = Color(0.9, 0.95, 1.0)  # Slightly cool
	fill_light.rotation_degrees = Vector3(-30, 150, 0)
	fill_light.shadow_enabled = false
	add_child(fill_light)

	# 3. RIM/BACK LIGHT - Creates separation from background
	var rim_light := DirectionalLight3D.new()
	rim_light.name = "RimLight"
	rim_light.light_energy = 0.4  # Subtle rim
	rim_light.light_color = Color(1.0, 1.0, 1.0)
	rim_light.rotation_degrees = Vector3(-20, 180, 0)
	rim_light.shadow_enabled = false
	add_child(rim_light)

	# AMBIENT - Overall base illumination - MUCH BRIGHTER
	var ambient_env := Environment.new()
	ambient_env.background_mode = Environment.BG_COLOR
	ambient_env.background_color = Color(0.0, 0.0, 0.0)  # Pure black space
	ambient_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	ambient_env.ambient_light_color = Color(0.3, 0.35, 0.4)  # Subtle neutral light
	ambient_env.ambient_light_energy = 0.3  # Gentle ambient
	ambient_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC  # Better contrast
	ambient_env.adjustment_enabled = true
	ambient_env.adjustment_brightness = 1.2  # Boost overall brightness

	# Disable SSAO/SSIL for better performance
	ambient_env.ssao_enabled = false
	ambient_env.ssil_enabled = false

	var world_env := WorldEnvironment.new()
	world_env.environment = ambient_env
	add_child(world_env)

func _create_stars() -> void:
	# Create starfield
	var immediate_mesh := ImmediateMesh.new()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = immediate_mesh
	add_child(mesh_instance)

	immediate_mesh.surface_begin(Mesh.PRIMITIVE_POINTS)
	for i in range(200):  # Reduced from 1000 for performance
		var x = randf_range(-1000, 1000)
		var y = randf_range(-1000, 1000)
		var z = randf_range(-1000, 1000)
		immediate_mesh.surface_add_vertex(Vector3(x, y, z))
	immediate_mesh.surface_end()

	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_instance.material_override = material

func _create_instructions_ui() -> void:
	# Create on-screen instructions
	var canvas_layer := CanvasLayer.new()
	canvas_layer.name = "InstructionsUI"
	add_child(canvas_layer)

	var label := Label.new()
	label.name = "InstructionsLabel"
	label.text = """CONTROLS:

PLAYER MOVEMENT:
  WASD - Move
  Shift - Run (2x speed)
  Space - Jump
  Mouse - Look around
  O - Toggle Third Person Camera

SHIP CONTROLS (when inside ship):
  T - Forward    | R - Raise
  F - Left       | Y - Lower
  G - Backward   |
  H - Right      |
  Z/C - Pitch (up/down)
  X/V - Yaw (left/right)
  Q/E - Roll (left/right)
  B - Toggle Docking Magnetism

CONTAINER CONTROLS (when in active container):
  I - Forward    | U - Raise
  J - Left       | P - Lower
  K - Backward   |
  L - Right      |
  Arrow Keys - Pitch/Yaw
  N/M - Roll
"""

	# Style the label
	label.position = Vector2(10, 10)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)

	canvas_layer.add_child(label)

	# Create debug info label (bottom left)
	var debug_label := Label.new()
	debug_label.name = "DebugLabel"
	debug_label.position = Vector2(10, 500)  # Will be adjusted in _process
	debug_label.add_theme_color_override("font_color", Color(0, 1, 1, 0.9))  # Cyan
	debug_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	debug_label.add_theme_constant_override("shadow_offset_x", 2)
	debug_label.add_theme_constant_override("shadow_offset_y", 2)
	canvas_layer.add_child(debug_label)

func _process(delta: float) -> void:
	# Update cooldowns
	if vehicle_transition_cooldown > 0:
		vehicle_transition_cooldown -= delta
	if container_transition_cooldown > 0:
		container_transition_cooldown -= delta

	# Update FPS counter
	fps_update_timer += delta
	if fps_update_timer >= FPS_UPDATE_INTERVAL:
		fps_counter = Engine.get_frames_per_second()
		fps_update_timer = 0.0

	# Update camera's container reference based on which container player is in
	_update_camera_container()

	_update_debug_ui()
	_handle_input()
	_check_transitions()

func _physics_process(delta: float) -> void:
	# Periodically check if physics spaces can be put to sleep for optimization
	space_sleep_check_timer += delta
	if space_sleep_check_timer >= SPACE_SLEEP_CHECK_INTERVAL:
		space_sleep_check_timer = 0.0
		_check_space_sleep_optimization()

func _update_camera_container() -> void:
	# Dynamically update camera's container reference based on which container player is in
	# UNIVERSAL: Automatically detects correct container by matching physics spaces
	if not is_instance_valid(dual_camera) or not is_instance_valid(character):
		return

	# Check if player is directly in a container
	if character.is_in_container:
		var player_space = PhysicsServer3D.body_get_space(character.proxy_body)

		# UNIVERSAL: Loop through all children to find VehicleContainer nodes
		for child in get_children():
			if child is VehicleContainer:
				var container = child
				if not is_instance_valid(container):
					continue

				var container_space = container.get_interior_space()
				# Match physics space to determine which container player is in
				if player_space == container_space:
					# CRITICAL: Camera tracks the IMMEDIATE container player is in
					# Not outermost - player is physically in this specific container's space
					if dual_camera.vehicle_container != container:
						dual_camera.vehicle_container = container
					return

	# Check if player is in a vehicle docked in a container
	elif character.is_in_vehicle and is_instance_valid(vehicle) and vehicle.is_docked:
		var docked_container = vehicle._get_docked_container()
		if docked_container:
			# CRITICAL: Camera tracks the container the vehicle is docked in
			# Player is in vehicle which is in this container's space
			if dual_camera.vehicle_container != docked_container:
				dual_camera.vehicle_container = docked_container

func _update_debug_ui() -> void:
	# Update debug label on screen
	var canvas_layer = get_node_or_null("InstructionsUI")
	if not canvas_layer:
		return

	var debug_label = canvas_layer.get_node_or_null("DebugLabel")
	if not debug_label or not is_instance_valid(character):
		return

	# Position at bottom left
	var viewport_size = get_viewport().get_visible_rect().size
	debug_label.position = Vector2(10, viewport_size.y - 250)

	# Build detailed nesting context string
	var world_pos = character.get_world_position()
	var proxy_pos = character.get_proxy_position()

	var detailed_location = "World"

	# Build detailed hierarchy string
	if character.is_in_vehicle and is_instance_valid(vehicle):
		if vehicle.is_docked:
			var docked_container = vehicle._get_docked_container()
			if docked_container:
				# Check if docked container is itself docked
				if docked_container.is_docked:
					var parent_container = docked_container._get_docked_container()
					if parent_container:
						detailed_location = "Vehicle Interior (docked in %s, docked in %s)" % [docked_container.name, parent_container.name]
					else:
						detailed_location = "Vehicle Interior (docked in %s)" % [docked_container.name]
				else:
					detailed_location = "Vehicle Interior (docked in %s)" % [docked_container.name]
		else:
			detailed_location = "Vehicle Interior (undocked)"
	elif character.is_in_container:
		# Find which container player is in
		var player_space = PhysicsServer3D.body_get_space(character.proxy_body)
		for child in get_children():
			if child is VehicleContainer:
				var container = child
				if is_instance_valid(container) and container.get_interior_space() == player_space:
					# Check if this container is docked
					if container.is_docked:
						var parent_container = container._get_docked_container()
						if parent_container:
							detailed_location = "%s Interior (docked in %s)" % [container.name, parent_container.name]
						else:
							detailed_location = "%s Interior (docked)" % [container.name]
					else:
						detailed_location = "%s Interior (undocked)" % [container.name]
					break

	# Only show proxy position when in a proxy space (vehicle or container)
	var proxy_info = ""
	if character.is_in_vehicle or character.is_in_container:
		proxy_info = "Proxy Pos: (%.1f, %.1f, %.1f)\n" % [proxy_pos.x, proxy_pos.y, proxy_pos.z]

	# Count active physics spaces for performance debugging
	var active_spaces = 1  # World space always active
	if is_instance_valid(vehicle) and vehicle.vehicle_interior_space.is_valid():
		if PhysicsServer3D.space_is_active(vehicle.vehicle_interior_space):
			active_spaces += 1
	if is_instance_valid(vehicle_container_small) and vehicle_container_small.container_interior_space.is_valid():
		if PhysicsServer3D.space_is_active(vehicle_container_small.container_interior_space):
			active_spaces += 1
	if is_instance_valid(vehicle_container_large) and vehicle_container_large.container_interior_space.is_valid():
		if PhysicsServer3D.space_is_active(vehicle_container_large.container_interior_space):
			active_spaces += 1

	debug_label.text = """=== DEBUG INFO ===
FPS: %.0f | Spaces: %d
Location: %s
World Pos: (%.1f, %.1f, %.1f)
%s""" % [
		fps_counter,
		active_spaces,
		detailed_location,
		world_pos.x, world_pos.y, world_pos.z,
		proxy_info
	]

func _handle_input() -> void:
	if not is_instance_valid(character) or not is_instance_valid(dual_camera):
		return

	# Character movement input (WASD always works for walking around)
	var move_dir := Vector3.ZERO

	if Input.is_key_pressed(KEY_W):
		var forward = dual_camera.get_forward_direction()
		move_dir += forward
	if Input.is_key_pressed(KEY_S):
		var forward = dual_camera.get_forward_direction()
		move_dir -= forward
	if Input.is_key_pressed(KEY_A):
		var right = dual_camera.get_right_direction()
		move_dir -= right
	if Input.is_key_pressed(KEY_D):
		var right = dual_camera.get_right_direction()
		move_dir += right

	character.set_input_direction(move_dir)
	character.set_jump(Input.is_action_pressed("ui_accept") or Input.is_key_pressed(KEY_SPACE))
	character.set_running(Input.is_key_pressed(KEY_SHIFT))

	# Vehicle controls (only when player is IN the vehicle)
	if is_instance_valid(vehicle) and character.is_in_vehicle:
		_handle_vehicle_controls()

	# Container controls - unified controls for whichever container player is in
	_handle_container_controls()

func _handle_vehicle_controls() -> void:
	# Get vehicle basis for directional movement
	# Use exterior_body basis - this represents the ship's actual orientation
	# The apply_thrust() function handles whether to apply to dock_proxy or exterior
	var vehicle_basis = vehicle.exterior_body.global_transform.basis

	# Vehicle DIRECTIONAL controls (TFGH) - Strong thrust for responsive movement
	if Input.is_key_pressed(KEY_T):
		# Forward (negative Z in vehicle's local space)
		var forward = -vehicle_basis.z
		vehicle.apply_thrust(forward, 40000.0)  # Increased from 15000

	if Input.is_key_pressed(KEY_G):
		# Backward (positive Z in vehicle's local space)
		var backward = vehicle_basis.z
		vehicle.apply_thrust(backward, 40000.0)  # Increased from 15000

	if Input.is_key_pressed(KEY_F):
		# Left (negative X in vehicle's local space)
		var left = -vehicle_basis.x
		vehicle.apply_thrust(left, 40000.0)  # Increased from 15000

	if Input.is_key_pressed(KEY_H):
		# Right (positive X in vehicle's local space)
		var right = vehicle_basis.x
		vehicle.apply_thrust(right, 40000.0)  # Increased from 15000

	# Vehicle VERTICAL controls (R/Y) - Higher thrust to overcome gravity
	if Input.is_key_pressed(KEY_R):
		# Raise (positive Y in vehicle's local space)
		var up = vehicle_basis.y
		vehicle.apply_thrust(up, 35000.0)  # Increased from 15000 to overcome gravity

	if Input.is_key_pressed(KEY_Y):
		# Lower (negative Y in vehicle's local space)
		var down = -vehicle_basis.y
		vehicle.apply_thrust(down, 35000.0)  # Increased from 15000 for consistency

	# Vehicle ROTATION controls (Z/C, X/V, Q/E)
	# Increased torque from 500 to 5000 for visible exterior rotation
	# Pitch (Z/C)
	if Input.is_key_pressed(KEY_Z):
		var local_x = vehicle_basis.x
		vehicle.apply_rotation(local_x, 5000.0)
	elif Input.is_key_pressed(KEY_C):
		var local_x = vehicle_basis.x
		vehicle.apply_rotation(local_x, -5000.0)

	# Yaw (X/V)
	if Input.is_key_pressed(KEY_X):
		var local_y = vehicle_basis.y
		vehicle.apply_rotation(local_y, 5000.0)
	elif Input.is_key_pressed(KEY_V):
		var local_y = vehicle_basis.y
		vehicle.apply_rotation(local_y, -5000.0)

	# Roll (Q/E)
	if Input.is_key_pressed(KEY_Q):
		var local_z = vehicle_basis.z
		vehicle.apply_rotation(local_z, 5000.0)
	elif Input.is_key_pressed(KEY_E):
		var local_z = vehicle_basis.z
		vehicle.apply_rotation(local_z, -5000.0)

	# Toggle magnetism (B key)
	if Input.is_action_just_pressed("ui_text_backspace") or Input.is_key_pressed(KEY_B):
		if vehicle.is_docked:
			vehicle.toggle_magnetism()

func _handle_container_controls() -> void:
	# Player controls the IMMEDIATE container they are in (not the outermost)
	# This allows piloting nested containers independently
	var controllable_container: VehicleContainer = null
	
	# First, find which container the player is in (directly or via docked vehicle)
	var immediate_container: VehicleContainer = null

	# UNIVERSAL: Loop through all children to find which container player is in
	for child in get_children():
		if child is VehicleContainer:
			var container = child
			if is_instance_valid(container) and _is_player_in_container(container):
				immediate_container = container
				break

	# If not in any container, return early
	if not is_instance_valid(immediate_container):
		return

	# CRITICAL: Control the container you're directly in, not the outermost one
	# This allows you to pilot the small container even when it's docked in the large container
	controllable_container = immediate_container

	# Debug: Check if we found a controllable container
	if not is_instance_valid(controllable_container):
		print("[CONTAINER CTRL] ERROR: controllable_container is null")
		return

	# UNIVERSAL: Calculate thrust force based on container size
	# Scale thrust with container size for consistent acceleration across all containers
	# Formula: base_thrust * (size_multiplier / 5.0)
	# This gives 500,000N for size 5, 1,000,000N for size 10, etc.
	var base_thrust = 500000.0
	var thrust_force = base_thrust * (controllable_container.size_multiplier / 5.0)

	# Get container basis for directional movement
	# CRITICAL: Use dock_proxy_body basis if docked, otherwise use recursive world transform
	var container_basis: Basis
	if controllable_container.is_docked and controllable_container.dock_proxy_body.is_valid():
		# Container is docked - use dock_proxy_body's local orientation in parent space
		var dock_transform = PhysicsServer3D.body_get_state(controllable_container.dock_proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM)
		container_basis = dock_transform.basis
	else:
		# Container not docked - use recursive world transform
		var container_world_transform = VehicleContainer.get_world_transform(controllable_container)
		container_basis = container_world_transform.basis

	# Container DIRECTIONAL controls (IJKL) - higher thrust for responsive movement
	if Input.is_key_pressed(KEY_I):
		# Forward (negative Z in container's local space)
		var forward = -container_basis.z
		controllable_container.apply_thrust(forward, thrust_force * 3.0)

	if Input.is_key_pressed(KEY_K):
		# Backward (positive Z in container's local space)
		var backward = container_basis.z
		controllable_container.apply_thrust(backward, thrust_force * 3.0)

	if Input.is_key_pressed(KEY_J):
		# Left (negative X in container's local space)
		var left = -container_basis.x
		controllable_container.apply_thrust(left, thrust_force * 3.0)

	if Input.is_key_pressed(KEY_L):
		# Right (positive X in container's local space)
		var right = container_basis.x
		controllable_container.apply_thrust(right, thrust_force * 3.0)

	# Container VERTICAL controls (U/P) - MUCH higher thrust to overcome gravity when docked
	# When docked, containers experience full gravity (9.8 m/s²) in parent space
	# Need thrust >> mass * 9.8 to overcome gravity and ascend
	# Base thrust gives 2 m/s² horizontal, need 6x for ~12 m/s² vertical to overcome 9.8 gravity + allow ascent
	if Input.is_key_pressed(KEY_U):
		# Raise (positive Y in container's local space)
		var up = container_basis.y
		controllable_container.apply_thrust(up, thrust_force * 6.0)

	if Input.is_key_pressed(KEY_P):
		# Lower (negative Y in container's local space)
		var down = -container_basis.y
		controllable_container.apply_thrust(down, thrust_force * 6.0)

	# Container ROTATION controls (Arrow keys for pitch/yaw, N/M for roll)
	var rotation_torque = 15000.0  # Higher torque for larger container mass

	# Pitch (Up/Down arrows)
	if Input.is_key_pressed(KEY_UP):
		var local_x = container_basis.x
		controllable_container.apply_rotation(local_x, rotation_torque)
	elif Input.is_key_pressed(KEY_DOWN):
		var local_x = container_basis.x
		controllable_container.apply_rotation(local_x, -rotation_torque)

	# Yaw (Left/Right arrows)
	if Input.is_key_pressed(KEY_LEFT):
		var local_y = container_basis.y
		controllable_container.apply_rotation(local_y, rotation_torque)
	elif Input.is_key_pressed(KEY_RIGHT):
		var local_y = container_basis.y
		controllable_container.apply_rotation(local_y, -rotation_torque)

	# Roll (N/M keys)
	if Input.is_key_pressed(KEY_N):
		var local_z = container_basis.z
		controllable_container.apply_rotation(local_z, rotation_torque)
	elif Input.is_key_pressed(KEY_M):
		var local_z = container_basis.z
		controllable_container.apply_rotation(local_z, -rotation_torque)

func _check_transitions() -> void:
	if not is_instance_valid(character):
		return

	# Check vehicle transition zone (entering/exiting ship)
	# Seamless physics-based transitions - character position preserved
	if is_instance_valid(vehicle) and vehicle.transition_zone and vehicle_transition_cooldown <= 0:
		if character.is_in_vehicle:
			# Check if character walked toward the front of the ship
			var proxy_pos = character.get_proxy_position()

			# Proxy floor extends from z=-15 to z=+15 (5.0 * 3 = 15)
			# Exit when past the floor edge
			var exited_front = proxy_pos.z > 15.0

			if exited_front:
				# REMOVED OLD CODE - Ship exit handled by universal container detection below (line ~770)
				# This prevents duplicate logic and allows the universal system to work
				pass
		else:
			# Check if character walked into the vehicle entrance (UNIVERSAL HELPER)
			var char_world_pos = character.get_world_position()
			var vehicle_transform = vehicle.exterior_body.global_transform

			# Define vehicle entry bounds (well before exit threshold of 18.0)
			var entry_bounds = {
				"x_min": -9.0, "x_max": 9.0,
				"y_min": -4.5, "y_max": 4.5,
				"z_min": 10.0, "z_max": 15.0  # Entry 10-15, exit 18+ gives 3+ unit buffer
			}

			# Check entry using universal helper
			var entry_check = _check_interior_entry(
				char_world_pos,
				vehicle_transform,
				entry_bounds,
				1.0,  # velocity_threshold
				-1    # velocity_sign: negative Z to enter
			)

			if entry_check["should_enter"] and not character.is_in_container:
				# Player in world space entering undocked ship

				# Activate and enter interior space (UNIVERSAL HELPER)
				var vehicle_space = vehicle.get_interior_space()
				_activate_and_enter_interior_space(vehicle_space)

				# Check if orientation transition is needed (for UP direction only)
				var ship_basis = vehicle.exterior_body.global_transform.basis
				var ship_up = ship_basis.y
				var world_up = Vector3.UP
				var up_dot = ship_up.dot(world_up)
				var needs_reorientation = up_dot < 0.95

				# Adjust camera yaw to compensate for ship's rotation
				# Get ship's yaw rotation relative to world
				var ship_forward_world = ship_basis.z
				var ship_yaw = atan2(ship_forward_world.x, ship_forward_world.z)

				# Adjust camera's base rotation by ship's yaw
				dual_camera.base_rotation.y -= ship_yaw

				# Construct target basis for reorientation (ship's local UP)
				# When ship is upside down, we want character to reorient to ship's UP
				var target_basis: Basis
				if needs_reorientation:
					# Get camera's forward direction and construct basis with ship's UP
					var camera_forward = dual_camera.get_forward_direction()
					var local_forward = ship_basis.inverse() * camera_forward
					local_forward = local_forward.normalized()

					# Construct basis using ship's local UP (Y-axis in local space)
					var local_up = Vector3.UP
					var local_right = local_forward.cross(local_up).normalized()
					local_forward = local_right.cross(local_up).normalized()
					target_basis = Basis(local_right, local_up, local_forward)
				else:
					target_basis = Basis.IDENTITY

				character.enter_vehicle(needs_reorientation, target_basis)

				# Seamlessly enter - use exact transformed position (no clamping)
				character.set_proxy_position(entry_check["local_pos"], entry_check["local_velocity"])
			elif character.is_in_container and vehicle.is_docked:
				# Player in container space, check if can enter docked ship
				# CRITICAL: First verify player is in the SAME container the ship is docked in
				var ship_docked_container = vehicle._get_docked_container()

				if ship_docked_container:
					# Check if player's physics space matches the container the ship is docked in
					var player_space = PhysicsServer3D.body_get_space(character.proxy_body)
					var ship_container_space = ship_docked_container.get_interior_space()

					if player_space == ship_container_space:
						# Player IS in the same container as the docked ship - check entry
						# Get player position in container space
						var player_container_pos = character.get_proxy_position()

						# Get ship's dock_proxy_body position in container space
						var ship_dock_transform = PhysicsServer3D.body_get_state(vehicle.dock_proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM)

						# Calculate player position relative to ship
						var relative_to_ship = player_container_pos - ship_dock_transform.origin
						var ship_local_pos = ship_dock_transform.basis.inverse() * relative_to_ship

						# Check if at ship entrance zone (match undocked entry zone: 10-15)
						var at_docked_ship_entrance = (
							abs(ship_local_pos.x) < 9.0 and
							abs(ship_local_pos.y) < 4.5 and
							ship_local_pos.z > 10.0 and ship_local_pos.z < 15.0  # Match undocked entry zone
						)

						# Get velocity in container space and transform to ship space
						var container_velocity = character.get_proxy_velocity()
						var ship_local_velocity = ship_dock_transform.basis.inverse() * container_velocity

						# CRITICAL: Only enter if moving INTO interior (negative Z velocity in local space)
						var moving_into_vehicle_from_container = ship_local_velocity.z < -1.0

						if at_docked_ship_entrance and moving_into_vehicle_from_container:
							# Player entering docked ship from container
							# CRITICAL: Exit container state before entering vehicle
							# This ensures clean transition from container -> vehicle
							character.exit_container()

							# Activate and enter vehicle interior space (UNIVERSAL HELPER)
							var vehicle_space = vehicle.get_interior_space()
							_activate_and_enter_interior_space(vehicle_space)

							# Check if orientation transition is needed (for UP direction only)
							# CRITICAL: Use recursive transform in case ship_docked_container is itself nested
							var ship_basis = vehicle.exterior_body.global_transform.basis
							var ship_up = ship_basis.y
							var container_world_transform = VehicleContainer.get_world_transform(ship_docked_container)
							var container_up = container_world_transform.basis.y
							var up_dot = ship_up.dot(container_up)
							var needs_reorientation = up_dot < 0.95

							# Adjust camera yaw to compensate for ship's rotation relative to container
							# Get ship's yaw rotation relative to container
							var container_basis = container_world_transform.basis
							var ship_forward_container = container_basis.inverse() * ship_basis.z
							var ship_yaw_in_container = atan2(ship_forward_container.x, ship_forward_container.z)

							# Adjust camera's base rotation by ship's yaw
							dual_camera.base_rotation.y -= ship_yaw_in_container

							# Construct target basis for reorientation
							var target_basis: Basis
							if needs_reorientation:
								var camera_forward = dual_camera.get_forward_direction()
								var local_forward = ship_basis.inverse() * camera_forward
								local_forward = local_forward.normalized()

								var local_up = Vector3.UP
								var local_right = local_forward.cross(local_up).normalized()
								local_forward = local_right.cross(local_up).normalized()
								target_basis = Basis(local_right, local_up, local_forward)
							else:
								target_basis = Basis.IDENTITY

							character.enter_vehicle(needs_reorientation, target_basis)

							# Seamlessly set position (no clamping)
							character.set_proxy_position(ship_local_pos, ship_local_velocity)

	# UNIVERSAL: Check if player can enter a docked container from another container
	if character.is_in_container:
		# Get player's current container space
		var player_space = PhysicsServer3D.body_get_space(character.proxy_body)
		var player_container_pos = character.get_proxy_position()
		var player_container_velocity = character.get_proxy_velocity()

		# Find which container the player is currently in
		var current_container: VehicleContainer = null
		for child in get_children():
			if child is VehicleContainer:
				var container = child
				if is_instance_valid(container) and container.get_interior_space() == player_space:
					current_container = container
					break

		# If we found the current container, check for docked containers inside it
		if current_container:
			# Loop through all containers to find any docked in current_container
			for child in get_children():
				if child is VehicleContainer:
					var docked_container = child
					# Skip if not docked or not docked in current container
					if not docked_container.is_docked or docked_container._get_docked_container() != current_container:
						continue

					# Get docked container's position in current container space
					var container_dock_transform = PhysicsServer3D.body_get_state(docked_container.dock_proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM)

					# Calculate player position relative to docked container
					var relative_to_container = player_container_pos - container_dock_transform.origin
					var container_local_pos = container_dock_transform.basis.inverse() * relative_to_container

					# Entry zone scaled by container size
					var size_scale = 3.0 * docked_container.size_multiplier
					var half_width = 3.0 * size_scale
					var half_height = 1.5 * size_scale
					var half_length = 5.0 * size_scale
					# UNIVERSAL: Transition when player is INSIDE docked container volume, not at entrance
					# Player physically inside = from back wall to before exit zone
					var entry_z_min = -half_length + 1.0  # Near back wall (1 unit margin)
					var entry_z_max = half_length - 1.0   # Before exit zone (exit is at half_length + 0.1)

					# Check if at docked container entrance zone
					var at_docked_container_entrance = (
						abs(container_local_pos.x) < half_width and
						abs(container_local_pos.y) < half_height and
						container_local_pos.z > entry_z_min and container_local_pos.z < entry_z_max
					)

					# Get velocity in container space and transform to docked container space
					var container_local_velocity = container_dock_transform.basis.inverse() * player_container_velocity

					# CRITICAL: Only enter if moving INTO interior (negative Z velocity in local space)
					var moving_into_container = container_local_velocity.z < -1.0

					if at_docked_container_entrance and moving_into_container:
						# Player entering docked container from outer container
						print("[CONTAINER ENTRY] Entering docked ", docked_container.name, " from ", current_container.name)

						# CRITICAL: Exit current container state before entering docked container
						character.exit_container()

						# Activate and enter docked container interior space
						var docked_space = docked_container.get_interior_space()
						_activate_and_enter_interior_space(docked_space)

						# Check if orientation transition is needed
						# CRITICAL: Use recursive transforms in case containers are nested
						var docked_world_transform = VehicleContainer.get_world_transform(docked_container)
						var docked_basis = docked_world_transform.basis
						var docked_up = docked_basis.y
						var current_world_transform = VehicleContainer.get_world_transform(current_container)
						var current_up = current_world_transform.basis.y
						var up_dot = docked_up.dot(current_up)
						var needs_reorientation = up_dot < 0.95

						# CRITICAL: Camera tracks the IMMEDIATE container player is entering
						if is_instance_valid(dual_camera):
							if dual_camera.vehicle_container != docked_container:
								dual_camera.vehicle_container = docked_container

							# Set camera up direction to immediate container's up (in world space)
							var container_up = docked_world_transform.basis.y
							dual_camera.set_target_up_direction(container_up)

						# Adjust camera yaw to compensate for docked container's rotation
						var current_basis = current_world_transform.basis
						var docked_forward_in_current = current_basis.inverse() * docked_basis.z
						var docked_yaw_in_current = atan2(docked_forward_in_current.x, docked_forward_in_current.z)
						dual_camera.base_rotation.y -= docked_yaw_in_current

						# Construct target basis for reorientation
						var target_basis: Basis
						if needs_reorientation:
							var camera_forward = dual_camera.get_forward_direction()
							var local_forward = docked_basis.inverse() * camera_forward
							local_forward = local_forward.normalized()

							var local_up = Vector3.UP
							var local_right = local_forward.cross(local_up).normalized()
							local_forward = local_right.cross(local_up).normalized()
							target_basis = Basis(local_right, local_up, local_forward)
						else:
							target_basis = Basis.IDENTITY

						# Debug: Check container state and position
						print("[DOCKED CONTAINER ENTRY] Container: ", docked_container.name, " is_docked=", docked_container.is_docked)
						print("[DOCKED CONTAINER ENTRY] Position in container: ", container_local_pos)
						print("[DOCKED CONTAINER ENTRY] Container space active: ", PhysicsServer3D.space_is_active(docked_space))
						print("[DOCKED CONTAINER ENTRY] Character proxy_body space before: ", PhysicsServer3D.body_get_space(character.proxy_body))

						character.enter_container(needs_reorientation, target_basis)

						# UNIVERSAL: No position clamping - seamless physics-based positioning
						character.set_proxy_position(container_local_pos, container_local_velocity)

						print("[DOCKED CONTAINER ENTRY] After: Character proxy_body space: ", PhysicsServer3D.body_get_space(character.proxy_body))
						print("[DOCKED CONTAINER ENTRY] Container space: ", docked_space)

						# Break after entering one container
						break

	# Check container transition zones - seamless entry/exit for ALL containers
	if character.is_in_container:
		# Loop through all containers to find which one player is in
		var containers = [vehicle_container_small, vehicle_container_large]
		
		for container in containers:
			if not is_instance_valid(container) or not container.transition_zone:
				continue
			
			# Check if character is in THIS container's space
			var container_space = container.get_interior_space()
			var player_space = PhysicsServer3D.body_get_space(character.proxy_body)
			if player_space != container_space:
				continue
			
			# Get positions and velocity
			var proxy_pos = character.get_proxy_position()
			var proxy_velocity = character.get_proxy_velocity()

			# Calculate exit threshold based on container size with hysteresis
			var size_scale = 3.0 * container.size_multiplier
			var half_length = 5.0 * size_scale

			# UNIVERSAL: Match tight vehicle hysteresis pattern (5 unit entry depth)
			# Vehicle: entry 10-15 (5 units), exit 15.1 (0.1 past entry)
			# Container: entry (half_length-5) to half_length (5 units), exit half_length+0.1
			var exit_threshold = half_length + 0.1

			# Check exit using universal helper
			var should_exit = _check_interior_exit(
				proxy_pos,
				proxy_velocity,
				exit_threshold,  # exit just past entry zone
				1.0              # velocity_threshold
			)

			if should_exit:

				# CRITICAL: Check if should enter vehicle that's docked inside BEFORE exiting container
				# This prevents teleporting through world space
				var entering_docked_ship = false
				if is_instance_valid(vehicle) and vehicle.is_docked:
					# CRITICAL: Ship is docked in this container, use dock_proxy_body in container space
					# Don't go through world space - stay in container space
					var ship_dock_transform = PhysicsServer3D.body_get_state(vehicle.dock_proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM)

					# Check distance from character to ship (both in container space)
					var dist_to_ship = proxy_pos.distance_to(ship_dock_transform.origin)

					# CRITICAL: Only re-enter ship if VERY close (within ~12 units) AND not at exit threshold
					# This allows exiting container even with docked ship inside
					# Ship is ~9 units tall, so 12 units is close proximity
					if dist_to_ship < 12.0 and proxy_pos.z < exit_threshold:
						entering_docked_ship = true

						# Transform from container space to ship local space
						var relative_pos = proxy_pos - ship_dock_transform.origin
						var vehicle_local_pos = ship_dock_transform.basis.inverse() * relative_pos

						# Transform velocity from container space to ship local space
						var vehicle_local_velocity = ship_dock_transform.basis.inverse() * proxy_velocity

						# Exit container state
						character.exit_container()

						# Activate and enter vehicle interior space (UNIVERSAL HELPER)
						var vehicle_space = vehicle.get_interior_space()
						_activate_and_enter_interior_space(vehicle_space)

						# Check if orientation transition is needed (for UP direction only)
						# CRITICAL: Use recursive transform in case container is itself nested
						var ship_basis = vehicle.exterior_body.global_transform.basis
						var ship_up = ship_basis.y
						var container_world_transform = VehicleContainer.get_world_transform(container)
						var container_up = container_world_transform.basis.y
						var up_dot = ship_up.dot(container_up)
						var needs_reorientation = up_dot < 0.95

						# Adjust camera yaw to compensate for ship's rotation relative to container
						var container_basis = container_world_transform.basis
						var ship_forward_container = container_basis.inverse() * ship_basis.z
						var ship_yaw_in_container = atan2(ship_forward_container.x, ship_forward_container.z)

						# Adjust camera's base rotation by ship's yaw
						dual_camera.base_rotation.y -= ship_yaw_in_container

						# Construct target basis for reorientation
						var target_basis: Basis
						if needs_reorientation:
							var camera_forward = dual_camera.get_forward_direction()
							var local_forward = ship_basis.inverse() * camera_forward
							local_forward = local_forward.normalized()

							var local_up = Vector3.UP
							var local_right = local_forward.cross(local_up).normalized()
							local_forward = local_right.cross(local_up).normalized()
							target_basis = Basis(local_right, local_up, local_forward)
						else:
							target_basis = Basis.IDENTITY

						character.enter_vehicle(needs_reorientation, target_basis)

						# Seamlessly set position (no clamping)
						character.set_proxy_position(vehicle_local_pos, vehicle_local_velocity)

				# Only exit to world if NOT entering docked ship
				if not entering_docked_ship:
					# CRITICAL: Check if this container is docked in a parent container
					# If so, exit to parent container instead of world
					var parent_container = container._get_docked_container()

					if parent_container and container.is_docked:
						# Container is docked in parent - exit to parent container space
						# Get this container's dock position in parent space
						var container_dock_transform = PhysicsServer3D.body_get_state(container.dock_proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM)

						# UNIVERSAL: No position forcing - use player's actual position for seamless transition
						# Transform player's current position in child container to parent container space
						# player position in child = proxy_pos
						# player position in parent = container_dock_transform * proxy_pos
						var parent_proxy_pos = container_dock_transform.origin + container_dock_transform.basis * proxy_pos
						var parent_proxy_velocity = container_dock_transform.basis * proxy_velocity

						# Exit current container
						character.exit_container()

						# Enter parent container
						var parent_space = parent_container.get_interior_space()
						_activate_and_enter_interior_space(parent_space)

						# Check orientation transition
						var container_world_transform = VehicleContainer.get_world_transform(container)
						var parent_world_transform = VehicleContainer.get_world_transform(parent_container)
						var container_up = container_world_transform.basis.y
						var parent_up = parent_world_transform.basis.y
						var up_dot = container_up.dot(parent_up)
						var needs_reorientation = up_dot < 0.95

						# Adjust camera yaw
						var container_basis = container_world_transform.basis
						var parent_basis = parent_world_transform.basis
						var container_forward_in_parent = parent_basis.inverse() * container_basis.z
						var container_yaw_in_parent = atan2(container_forward_in_parent.x, container_forward_in_parent.z)
						dual_camera.base_rotation.y += container_yaw_in_parent

						# Construct target basis
						var target_basis: Basis
						if needs_reorientation:
							var camera_forward = dual_camera.get_forward_direction()
							var local_forward = parent_basis.inverse() * camera_forward
							local_forward = local_forward.normalized()
							var local_up = Vector3.UP
							var local_right = local_forward.cross(local_up).normalized()
							local_forward = local_right.cross(local_up).normalized()
							target_basis = Basis(local_right, local_up, local_forward)
						else:
							target_basis = Basis.IDENTITY

						character.enter_container(needs_reorientation, target_basis)
						character.set_proxy_position(parent_proxy_pos, parent_proxy_velocity)

						# CRITICAL: Camera tracks the IMMEDIATE container player is entering (parent)
						if is_instance_valid(dual_camera):
							if dual_camera.vehicle_container != parent_container:
								dual_camera.vehicle_container = parent_container

							# Set camera target up direction to parent container
							dual_camera.set_target_up_direction(parent_up)
					else:
						# Container not docked - exit to world
						# Calculate world position for exit
						# CRITICAL: Use recursive transform in case container is nested
						var container_world_transform = VehicleContainer.get_world_transform(container)
						var world_velocity = container_world_transform.basis * proxy_velocity

						# Use player's actual position for seamless exit (no teleporting)
						var world_pos = container_world_transform.origin + container_world_transform.basis * proxy_pos

						# Get forward direction in world space (container's +Z is forward)
						var exit_forward = container_world_transform.basis.z

						# CRITICAL: Check if exit position is blocked in exterior world
						if _is_exit_position_blocked(world_pos, Vector3.UP, exit_forward):
							# Stop at the boundary - don't allow forward movement past exit threshold
							# Don't process the exit transition
							break

						# Check if orientation transition is needed (for UP direction only)
						var container_up = container_world_transform.basis.y
						var world_up = Vector3.UP
						var up_dot = container_up.dot(world_up)
						var needs_reorientation = up_dot < 0.95

						# Reverse the camera yaw adjustment we made on entry (same as vehicle)
						# Get container's yaw rotation relative to world
						var container_forward_world = container_world_transform.basis.z
						var container_yaw = atan2(container_forward_world.x, container_forward_world.z)

						# Add back the container's yaw (reverse of subtraction on entry)
						dual_camera.base_rotation.y += container_yaw

						# Construct target basis for reorientation
						var exit_basis: Basis
						if needs_reorientation:
							var camera_forward = dual_camera.get_forward_direction()
							var local_forward = camera_forward
							local_forward = local_forward.normalized()

							var local_up = Vector3.UP
							var local_right = local_forward.cross(local_up).normalized()
							local_forward = local_right.cross(local_up).normalized()
							exit_basis = Basis(local_right, local_up, local_forward)
						else:
							exit_basis = Basis.IDENTITY

						# Exit container state with reorientation
						character.exit_container(needs_reorientation, exit_basis)

						# Transition camera up direction back to world up and clear container tracking
						if is_instance_valid(dual_camera):
							dual_camera.set_target_up_direction(Vector3.UP)
							dual_camera.vehicle_container = null  # Clear container tracking when in world

						# UNIVERSAL: No clamping - player lands on ship exterior collider during transition
						character.set_world_position(world_pos, world_velocity)

				# Try to deactivate container space if no one left inside (UNIVERSAL HELPER)
				_try_deactivate_interior_space(container_space, _is_anyone_in_container(container))

				break


	elif character.is_in_vehicle:
		# Check if character (in ship interior) should exit vehicle
		# Get ship proxy position and velocity
		var ship_proxy_pos = character.get_proxy_position()
		var proxy_velocity = character.get_proxy_velocity()

		# Check exit using universal helper (UNIVERSAL HELPER)
		# Exit zone starts at z > 15.1 (right at floor edge)
		# This creates hysteresis: enter at z=10-15, exit at z=15.1+
		# Floor extends to z=15, exit immediately when past floor boundary
		var should_exit_vehicle = _check_interior_exit(
			ship_proxy_pos,
			proxy_velocity,
			15.1,  # exit_z_threshold (at floor edge to prevent falling through)
			1.0    # velocity_threshold
		)

		# Check if player walked out of vehicle - use velocity-based detection
		if should_exit_vehicle and is_instance_valid(vehicle):
				# Check if ship is docked in ANY container and player exit position is inside it
				# DO THIS BEFORE exit_vehicle() to prevent one-frame gap
				# Loop through all containers (universal system)
				var should_enter_container = false
				var target_container: VehicleContainer = null
				var container_proxy_pos: Vector3
				var world_pos: Vector3
				var world_velocity: Vector3


				if vehicle.is_docked:
					var containers = [vehicle_container_small, vehicle_container_large]

					for container in containers:
						if not is_instance_valid(container) or not container.exterior_body:
							continue

						# Check if ship is docked in THIS container
						var docked_container = vehicle._get_docked_container()
						if docked_container != container:
							continue

						# CRITICAL: When ship is docked, use dock_proxy_body transform (in container space)
						# NOT exterior_body transform (in world space)
						var ship_dock_transform = PhysicsServer3D.body_get_state(vehicle.dock_proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM)

						# Transform ship proxy pos (in ship's interior space) to container space
						container_proxy_pos = ship_dock_transform.origin + ship_dock_transform.basis * ship_proxy_pos


						# Calculate container bounds dynamically based on size
						var size_scale = 3.0 * container.size_multiplier
						var half_width = 3.0 * size_scale
						var half_height = 1.5 * size_scale
						var half_length = 5.0 * size_scale

						# Check each bound individually
						# Add buffer to Y bounds to allow players standing on floor
						# Floor is at -1.5*size_scale + 0.1, so allow 2 units below that for safety
						var y_min = -half_height - 2.0
						var y_max = half_height + 1.0
						# Add buffer to Z bounds to account for ship exit zone extending slightly past container bounds
						var z_buffer = 5.0  # Allow up to 5 units past container front for ship exit

						var x_ok = abs(container_proxy_pos.x) < half_width
						var y_ok = container_proxy_pos.y > y_min and container_proxy_pos.y < y_max
						var z_ok = container_proxy_pos.z > -half_length and container_proxy_pos.z < half_length + z_buffer


						# Check if exit position is actually INSIDE the container interior space
						var inside_container = x_ok and y_ok and z_ok

						if inside_container:
							should_enter_container = true
							target_container = container
							break
				else:
						# Ship NOT docked - calculate world position from exterior body
						var vehicle_transform = vehicle.exterior_body.global_transform
						world_pos = vehicle_transform.origin + vehicle_transform.basis * ship_proxy_pos
						world_velocity = vehicle_transform.basis * proxy_velocity

				# Now exit vehicle (do this AFTER checking container, but BEFORE state change)
				# Check if ship's UP is significantly different from target space UP
				# CRITICAL: If ship is docked, need to use recursive world transform
				var ship_world_transform: Transform3D
				if vehicle.is_docked:
					# Ship is docked - get its world transform by chaining through parent containers
					var ship_dock_transform = PhysicsServer3D.body_get_state(vehicle.dock_proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM)
					var immediate_container = vehicle._get_docked_container()
					if immediate_container:
						var container_world_transform = VehicleContainer.get_world_transform(immediate_container)
						ship_world_transform = container_world_transform * ship_dock_transform
					else:
						ship_world_transform = ship_dock_transform  # Fallback if no container
				else:
					# Ship not docked - use exterior body transform
					ship_world_transform = vehicle.exterior_body.global_transform

				var ship_up = ship_world_transform.basis.y

				# Determine target UP based on whether entering container or world
				# CRITICAL: Use recursive transform in case target_container is nested
				var target_up: Vector3
				var target_basis: Basis
				if should_enter_container and target_container:
					var target_world_transform = VehicleContainer.get_world_transform(target_container)
					target_up = target_world_transform.basis.y
					target_basis = target_world_transform.basis
				else:
					target_up = Vector3.UP
					target_basis = Basis.IDENTITY

				# Check if orientation transition is needed (for UP direction only)
				var up_dot = target_up.dot(ship_up)
				var needs_reorientation = up_dot < 0.95

				# Reverse the camera yaw adjustment we made on entry
				# Get ship's yaw rotation relative to target space
				var ship_basis = ship_world_transform.basis
				var ship_forward_target = target_basis.inverse() * ship_basis.z
				var ship_yaw_in_target = atan2(ship_forward_target.x, ship_forward_target.z)

				# Add back the ship's yaw (reverse of subtraction on entry)
				dual_camera.base_rotation.y += ship_yaw_in_target

				# Construct target basis for reorientation
				var exit_basis: Basis
				if needs_reorientation:
					var camera_forward = dual_camera.get_forward_direction()
					var local_forward = target_basis.inverse() * camera_forward
					local_forward = local_forward.normalized()

					var local_up = Vector3.UP
					var local_right = local_forward.cross(local_up).normalized()
					local_forward = local_right.cross(local_up).normalized()
					exit_basis = Basis(local_right, local_up, local_forward)
				else:
					exit_basis = Basis.IDENTITY

				character.exit_vehicle(needs_reorientation, exit_basis)

				# Try to deactivate vehicle space if no one left inside (UNIVERSAL HELPER)
				var vehicle_space = vehicle.get_interior_space()
				_try_deactivate_interior_space(vehicle_space, _is_anyone_in_vehicle())

				if should_enter_container and target_container:

					# Transform velocity from ship interior space to container space
					# proxy_velocity is in ship's interior space
					# Need to transform through ship's dock_proxy_body basis to get to container space
					var ship_dock_transform = PhysicsServer3D.body_get_state(vehicle.dock_proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM)
					var container_velocity = ship_dock_transform.basis * proxy_velocity


					# CRITICAL: Adjust camera orientation for ship->container transition
					# Camera should track the container player is actually in, not outermost
					if is_instance_valid(dual_camera) and target_container and target_container.exterior_body:
						# CRITICAL: Camera tracks the IMMEDIATE container player is in
						# For PiP to work, it needs to know which container space player is inside
						if dual_camera.vehicle_container != target_container:
							dual_camera.vehicle_container = target_container

						# Set camera up direction to immediate container's up (in world space)
						var container_world_transform = VehicleContainer.get_world_transform(target_container)
						var container_up = container_world_transform.basis.y
						dual_camera.set_target_up_direction(container_up)

					# Activate and enter container interior space (UNIVERSAL HELPER)
					var container_space = target_container.get_interior_space()
					_activate_and_enter_interior_space(container_space)

					# Reuse exit_basis already calculated above for ship->container reorientation
					# needs_reorientation and target_basis were already set correctly above
					# Use natural container position - seamless physics transition
					# Reorient if ship and container have different orientations

					# UNIVERSAL: No position clamping - rely entirely on hysteresis system
					# Hysteresis (position + velocity checks) prevents unwanted transitions
					# Seamless physics-based transitions with no forced positioning

					# Debug: Check container state and position
					print("[SHIP->CONTAINER EXIT] Container: ", target_container.name, " is_docked=", target_container.is_docked)
					print("[SHIP->CONTAINER EXIT] Position in container: ", container_proxy_pos)
					print("[SHIP->CONTAINER EXIT] Container space active: ", PhysicsServer3D.space_is_active(container_space))
					print("[SHIP->CONTAINER EXIT] Character proxy_body space: ", PhysicsServer3D.body_get_space(character.proxy_body))

					character.enter_container(needs_reorientation, exit_basis)
					character.set_proxy_position(container_proxy_pos, container_velocity)

					print("[SHIP->CONTAINER EXIT] After: Character proxy_body space: ", PhysicsServer3D.body_get_space(character.proxy_body))
					print("[SHIP->CONTAINER EXIT] Container space: ", container_space)
				else:
					# Exit position is outside container OR ship not docked - exit to world space

					# Get forward direction in world space (interior's +Z is forward)
					var exit_transform = vehicle.exterior_body.global_transform
					var exit_forward = exit_transform.basis.z

					# CRITICAL: Check if exit position is blocked in exterior world
					if not _is_exit_position_blocked(world_pos, Vector3.UP, exit_forward):
						# Exit is clear - proceed
						if is_instance_valid(dual_camera):
							dual_camera.set_target_up_direction(Vector3.UP)

						# UNIVERSAL: No clamping - player lands on vehicle exterior collider during transition
						character.set_world_position(world_pos, world_velocity)

						# Set character visual orientation to world up

			# End velocity check for ship exit

	else:
		# Character in world space - check if entering ANY container from outside (UNIVERSAL HELPER)
		# Loop through all containers (same pattern as vehicle docking)
		var containers = [vehicle_container_small, vehicle_container_large]

		for container in containers:
			if not is_instance_valid(container) or not container.exterior_body:
				continue

			var char_world_pos = character.get_world_position()
			var container_transform = container.exterior_body.global_transform

			# Calculate entrance detection zone based on container size
			var size_scale = 3.0 * container.size_multiplier
			var half_width = 3.0 * size_scale
			var half_height = 1.5 * size_scale
			var half_length = 5.0 * size_scale
			var floor_top_y = -1.5 * size_scale + 0.1

			# UNIVERSAL: Tight 5 unit entry depth (matches vehicle hysteresis)
			# Vehicle: 15 unit floor, entry at 10-15 (5 units)
			# Container: Scaled floor, entry at (half_length-5) to half_length (5 units)
			var entry_bounds = {
				"x_min": -half_width, "x_max": half_width,
				"y_min": floor_top_y - 1.0, "y_max": half_height + 1.0,
				"z_min": half_length - 5.0, "z_max": half_length  # Tight 5 unit entry zone
			}

			# Check entry using universal helper
			# Container is rotated 180° like ship, so use negative Z to enter
			var entry_check = _check_interior_entry(
				char_world_pos,
				container_transform,
				entry_bounds,
				1.0,  # velocity_threshold
				-1    # velocity_sign: negative Z to enter (rotated 180°)
			)

			# Only trigger if player is in world space AND should enter
			if entry_check["should_enter"] and not character.is_in_container and not character.is_in_vehicle:
				# Activate and enter interior space (UNIVERSAL HELPER)
				var container_space = container.get_interior_space()
				_activate_and_enter_interior_space(container_space)

				# Check if orientation transition is needed (for UP direction only)
				var container_basis = container.exterior_body.global_transform.basis
				var container_up = container_basis.y
				var world_up = Vector3.UP
				var up_dot = container_up.dot(world_up)
				var needs_reorientation = up_dot < 0.95

				# CRITICAL: Camera tracks the container player is entering
				if is_instance_valid(dual_camera):
					if dual_camera.vehicle_container != container:
						dual_camera.vehicle_container = container

					# Set camera up direction to container's up (in world space)
					dual_camera.set_target_up_direction(container_up)

				# Adjust camera yaw to compensate for container's rotation (same as vehicle)
				var container_forward_world = container_basis.z
				var container_yaw = atan2(container_forward_world.x, container_forward_world.z)

				# Adjust camera's base rotation by container's yaw
				dual_camera.base_rotation.y -= container_yaw

				# Construct target basis for reorientation (container's local UP)
				var target_basis: Basis
				if needs_reorientation:
					# Get camera's forward direction and construct basis with container's UP
					var camera_forward = dual_camera.get_forward_direction()
					var local_forward = container_basis.inverse() * camera_forward
					local_forward = local_forward.normalized()

					# Construct basis using container's local UP (Y-axis in local space)
					var local_up = Vector3.UP
					var local_right = local_forward.cross(local_up).normalized()
					local_forward = local_right.cross(local_up).normalized()
					target_basis = Basis(local_right, local_up, local_forward)
				else:
					target_basis = Basis.IDENTITY

				character.enter_container(needs_reorientation, target_basis)
				character.set_proxy_position(entry_check["local_pos"], entry_check["local_velocity"])


				break  # Only enter one container at a time

			# Check vehicle docking in BOTH containers - find which one ship is inside
	if is_instance_valid(vehicle) and vehicle.exterior_body:
		var containers = [vehicle_container_small, vehicle_container_large]

		for container in containers:
			if not is_instance_valid(container) or not container.exterior_body:
				continue

			# Get ship position in container's local space
			# When docked: use proxy position directly (already in container space)
			# When not docked: transform exterior position to container space
			var local_pos: Vector3

			if vehicle.is_docked and vehicle.dock_proxy_body.is_valid():
				# Ship is docked - check if it's docked in THIS container
				var docked_container = vehicle._get_docked_container()
				if docked_container == container:
					# Ship is docked in THIS container - get position from proxy body directly
					var proxy_transform = PhysicsServer3D.body_get_state(vehicle.dock_proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM)
					local_pos = proxy_transform.origin
				else:
					# Ship is docked in a DIFFERENT container - skip this container
					continue
			else:
				# Ship is in world space - transform to container local space
				var vehicle_world_pos = vehicle.exterior_body.global_position
				var container_transform = container.exterior_body.global_transform
				var relative_pos = vehicle_world_pos - container_transform.origin
				local_pos = container_transform.basis.inverse() * relative_pos

			# Docking zone with HYSTERESIS - scaled by container size
			# CRITICAL: Docking bounds must be SMALLER than exterior collision to prevent
			# Container interior bounds (scaled by size_multiplier)
			# Small 1-unit margin to prevent floor/wall clipping physics glitches
			var size_scale = 3.0 * container.size_multiplier
			var half_width = 3.0 * size_scale - 1.0  # 1 unit margin to prevent wall clipping
			var half_height = 1.5 * size_scale - 1.0  # 1 unit margin to prevent floor/ceiling clipping
			var half_length = 5.0 * size_scale - 1.0  # 1 unit margin from back wall

			# UNIVERSAL: Entry when ENTIRE ship is inside
			# Ship collision box is 30 units long (±15 from center)
			# Ship back position = ship_center.z - 15
			# For ship back to be inside: ship_center.z - 15 < half_length
			# Therefore: ship_center.z < half_length + 15
			# No safety margin needed - hysteresis (position + velocity) prevents unwanted transitions
			var ship_half_length = 15.0  # Ship is 30 units long (±15 from center)
			var enter_z = half_length - ship_half_length   # Entire ship just inside, no extra margin

			# CRITICAL: Tight exit hysteresis (0.1 units past entry zone)
			# Exit when ship center reaches opening
			var exit_z = half_length + 0.1  # Exit 0.1 units past opening (tight hysteresis)

			# Check bounds - use interior bounds (already has 1 unit margin from walls/floor)
			var x_inside = abs(local_pos.x) < half_width
			var y_inside_min = local_pos.y > -half_height
			var y_inside_max = local_pos.y < half_height
			var z_inside_front = local_pos.z < enter_z
			var z_inside_back = local_pos.z > -half_length  # CRITICAL: Also check not behind back wall

			var vehicle_inside = x_inside and y_inside_min and y_inside_max and z_inside_front and z_inside_back

			# Exit thresholds - small margin (1 unit) to prevent rapid re-entry oscillation
			# Velocity check provides primary hysteresis, margins prevent physics edge cases
			var x_outside = abs(local_pos.x) > half_width + 1.0
			var y_outside_min = local_pos.y < -half_height - 1.0
			var y_outside_max = local_pos.y > half_height + 1.0
			var z_outside_back = local_pos.z < -half_length - 1.0
			var z_outside_front = local_pos.z > exit_z

			var vehicle_outside = x_outside or y_outside_min or y_outside_max or z_outside_back or z_outside_front

			# CRITICAL: Add velocity-based hysteresis like player transitions
			# Get vehicle velocity in container's local space
			var vehicle_velocity = vehicle.exterior_body.linear_velocity
			var container_basis = container.exterior_body.global_transform.basis
			var local_velocity = container_basis.inverse() * vehicle_velocity

			# Check if moving INTO container (negative Z) or OUT (positive Z)
			var moving_into_container = local_velocity.z < -1.0
			var moving_out_of_container = local_velocity.z > 1.0

			if vehicle_inside and not vehicle.is_docked and moving_into_container:
				# Vehicle entering THIS container - seamless transition at boundary
				var container_name = "Small" if container == vehicle_container_small else "Large"
				_debounced_log("DOCKING", "Vehicle entered " + container_name + " container", {
					"x": local_pos.x,
					"y": local_pos.y,
					"z": local_pos.z
				})
				vehicle.set_docked(true, container)
				break  # Only dock in one container
			elif vehicle_outside and vehicle.is_docked and moving_out_of_container:
				# Check if docked in THIS container before undocking
				var docked_container = vehicle._get_docked_container()
				if docked_container == container:
					# Vehicle leaving THIS container with outward velocity
					_debounced_log("DOCKING", "Vehicle left dock zone", {
						"x": local_pos.x,
						"y": local_pos.y,
						"z": local_pos.z,
						"velocity_z": local_velocity.z
					})
					vehicle.set_docked(false, container)

					# Try to deactivate container space if no one left inside (UNIVERSAL HELPER)
					var container_space = container.get_interior_space()
					_try_deactivate_interior_space(container_space, _is_anyone_in_container(container))

					break

		# UNIVERSAL: Check container-in-container docking for ALL container pairs
	# Loop through all children to find VehicleContainer nodes
	var all_containers: Array[VehicleContainer] = []
	for child in get_children():
		if child is VehicleContainer and is_instance_valid(child) and child.exterior_body:
			all_containers.append(child)

	# Check each pair of containers (potential_child docking in potential_parent)
	for potential_child in all_containers:
		for potential_parent in all_containers:
			# Skip if same container or if potential_parent is smaller/equal size
			if potential_child == potential_parent:
				continue
			if potential_parent.size_multiplier <= potential_child.size_multiplier:
				continue

			# Transform child container's world position to parent container's local space
			# CRITICAL: Use recursive world transforms to handle nested containers
			var child_world_transform = VehicleContainer.get_world_transform(potential_child)
			var parent_world_transform = VehicleContainer.get_world_transform(potential_parent)
			var child_world_pos = child_world_transform.origin
			var relative_pos = child_world_pos - parent_world_transform.origin
			var local_pos = parent_world_transform.basis.inverse() * relative_pos

			# Parent container interior bounds (scaled by size_multiplier)
			# Small 1-unit margin to prevent floor/wall clipping physics glitches
			var parent_size_scale = 3.0 * potential_parent.size_multiplier
			var half_width = 3.0 * parent_size_scale - 1.0  # 1 unit margin to prevent wall clipping
			var half_height = 1.5 * parent_size_scale - 1.0  # 1 unit margin to prevent floor/ceiling clipping
			var half_length = 5.0 * parent_size_scale - 1.0  # 1 unit margin from back wall

			# CRITICAL: Child container dimensions (need to know full size for proper docking)
			# Container length from center to back = half of total length
			var child_size_scale = 3.0 * potential_child.size_multiplier
			var child_half_length = 5.0 * child_size_scale  # Distance from center to back of child container

			# UNIVERSAL: Entry when ENTIRE container is inside
			# Wait for child center to be deep enough that child's back is past parent opening
			# Child back position = child_center.z - child_half_length
			# For child back to be inside: child_center.z - child_half_length < half_length
			# Therefore: child_center.z < half_length + child_half_length
			# No safety margin needed - hysteresis (position + velocity) prevents unwanted transitions
			var enter_z = half_length - child_half_length  # Entire child container just inside, no extra margin
			var exit_z = half_length + 0.1  # UNIVERSAL: Tight exit 0.1 units past opening (matches vehicle hysteresis)

			# Check bounds - use interior bounds (already has 1 unit margin from walls/floor)
			var x_inside = abs(local_pos.x) < half_width
			var y_inside_min = local_pos.y > -half_height
			var y_inside_max = local_pos.y < half_height
			var z_inside_front = local_pos.z < enter_z
			var z_inside_back = local_pos.z > -half_length

			var container_inside = x_inside and y_inside_min and y_inside_max and z_inside_front and z_inside_back

			# Exit thresholds - small margin (1 unit) to prevent rapid re-entry oscillation
			# Velocity check provides primary hysteresis, margins prevent physics edge cases
			var x_outside = abs(local_pos.x) > half_width + 1.0
			var y_outside_min = local_pos.y < -half_height - 1.0
			var y_outside_max = local_pos.y > half_height + 1.0
			var z_outside_back = local_pos.z < -half_length - 1.0
			var z_outside_front = local_pos.z > exit_z

			var container_outside = x_outside or y_outside_min or y_outside_max or z_outside_back or z_outside_front

			# CRITICAL: Add velocity-based hysteresis like ship docking
			# Get container velocity in parent container's local space
			var child_velocity = potential_child.exterior_body.linear_velocity
			var parent_basis = potential_parent.exterior_body.global_transform.basis
			var local_velocity = parent_basis.inverse() * child_velocity

			# Check if moving INTO parent container (negative Z) or OUT (positive Z)
			var moving_into_container = local_velocity.z < -1.0
			var moving_out_of_container = local_velocity.z > 1.0

			if container_inside and not potential_child.is_docked and moving_into_container:
				# Container entering parent container - seamless transition with velocity check
				_debounced_log("CONTAINER DOCK", potential_child.name + " entered " + potential_parent.name, {
					"x": local_pos.x,
					"y": local_pos.y,
					"z": local_pos.z
				})
				potential_child.set_docked(true, potential_parent)
				break  # Only dock in one container
			elif container_outside and potential_child.is_docked and moving_out_of_container:
				# Check if docked in THIS parent container before undocking
				var docked_in = potential_child._get_docked_container()
				if docked_in == potential_parent:
					# Container leaving parent container with outward velocity
					_debounced_log("CONTAINER DOCK", potential_child.name + " left " + potential_parent.name, {
						"x": local_pos.x,
						"y": local_pos.y,
						"z": local_pos.z
					})
					potential_child.set_docked(false, potential_parent)

# Physics space optimization: spaces activate on-demand and deactivate when empty or all bodies are sleeping

## ============================================================================
## UNIVERSAL INTERIOR HELPER FUNCTIONS
## These work for ANY interior type (vehicles, containers, or future additions)
## ============================================================================

## Activate an interior physics space and assign character's proxy body to it
func _activate_and_enter_interior_space(interior_space: RID) -> void:
	if not PhysicsServer3D.space_is_active(interior_space):
		PhysicsServer3D.space_set_active(interior_space, true)
	PhysicsServer3D.body_set_space(character.proxy_body, interior_space)

## Deactivate an interior physics space if no one is inside
func _try_deactivate_interior_space(interior_space: RID, is_anyone_inside: bool) -> void:
	if not is_anyone_inside and PhysicsServer3D.space_is_active(interior_space):
		PhysicsServer3D.space_set_active(interior_space, false)

## Check if character is at an interior entry zone with correct velocity
func _check_interior_entry(
	char_world_pos: Vector3,
	interior_transform: Transform3D,
	entry_bounds: Dictionary,  # {x_min, x_max, y_min, y_max, z_min, z_max}
	velocity_threshold: float,
	velocity_sign: int  # +1 for positive Z, -1 for negative Z
) -> Dictionary:
	"""
	Universal entry detection for any interior.
	Returns: {should_enter: bool, local_pos: Vector3, local_velocity: Vector3}
	"""
	# Transform to interior local space
	var relative_pos = char_world_pos - interior_transform.origin
	var local_pos = interior_transform.basis.inverse() * relative_pos

	# Check bounds
	var at_entrance = (
		local_pos.x > entry_bounds["x_min"] and local_pos.x < entry_bounds["x_max"] and
		local_pos.y > entry_bounds["y_min"] and local_pos.y < entry_bounds["y_max"] and
		local_pos.z > entry_bounds["z_min"] and local_pos.z < entry_bounds["z_max"]
	)

	# Check velocity direction
	var world_velocity = character.get_world_velocity()
	var local_velocity = interior_transform.basis.inverse() * world_velocity
	var moving_into_interior = (local_velocity.z * velocity_sign) > velocity_threshold

	return {
		"should_enter": at_entrance and moving_into_interior,
		"local_pos": local_pos,
		"local_velocity": local_velocity
	}

## Check if character should exit from interior
func _check_interior_exit(
	proxy_pos: Vector3,
	proxy_velocity: Vector3,
	exit_z_threshold: float,
	velocity_threshold: float
) -> bool:
	"""
	Universal exit detection for any interior.
	Returns: true if should exit
	"""
	var at_exit_zone = proxy_pos.z > exit_z_threshold
	var moving_out_of_interior = proxy_velocity.z > velocity_threshold
	return at_exit_zone and moving_out_of_interior

## Construct orientation basis preserving facing direction
func _construct_orientation_basis_preserving_facing(
	current_visual_forward: Vector3,
	target_up: Vector3,
	source_up: Vector3
) -> Dictionary:
	"""
	Constructs target orientation basis preserving horizontal facing direction.
	Only changes the UP direction, maintains the forward facing direction.
	Returns: {basis: Basis, should_transition: bool}
	"""
	# Check if UP directions differ significantly
	var up_dot = target_up.dot(source_up)
	var should_transition = up_dot < 0.95

	# Project current forward onto plane perpendicular to target UP
	# This preserves the horizontal facing direction
	var player_forward = current_visual_forward - target_up * current_visual_forward.dot(target_up)

	if player_forward.length_squared() < 0.001:
		# Player was looking straight up/down - use a default forward
		# Use world forward projected onto target plane
		var default_forward = Vector3(0, 0, 1)
		player_forward = default_forward - target_up * default_forward.dot(target_up)
		if player_forward.length_squared() < 0.001:
			# Target up is aligned with world forward, use world right instead
			player_forward = Vector3(1, 0, 0)
		else:
			player_forward = player_forward.normalized()
	else:
		player_forward = player_forward.normalized()

	# Construct right vector using cross product
	var player_right = player_forward.cross(target_up).normalized()

	# CRITICAL: Recalculate forward from right and up to ensure proper orthogonality
	# This fixes potential orientation issues from the projection
	var corrected_forward = player_right.cross(target_up).normalized()

	var target_basis = Basis(player_right, target_up, corrected_forward).orthonormalized()

	return {
		"basis": target_basis,
		"should_transition": should_transition
	}

func _check_space_sleep_optimization() -> void:
	# Check if physics spaces can be deactivated due to inactivity (sleeping bodies)
	# This runs periodically to optimize performance

	# Check vehicle space
	if is_instance_valid(vehicle) and vehicle.vehicle_interior_space.is_valid():
		var vehicle_space = vehicle.vehicle_interior_space
		if PhysicsServer3D.space_is_active(vehicle_space):
			# Only consider sleeping if no player is inside
			if not _is_anyone_in_vehicle():
				# Check both docked and free-flying cases
				var is_sleeping = false

				if vehicle.is_docked and vehicle.dock_proxy_body.is_valid():
					# Vehicle is docked - check dock_proxy_body velocity
					var vel = PhysicsServer3D.body_get_state(vehicle.dock_proxy_body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
					var angvel = PhysicsServer3D.body_get_state(vehicle.dock_proxy_body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
					is_sleeping = vel.length() < 0.01 and angvel.length() < 0.01
				elif vehicle.exterior_body:
					# Vehicle is free-flying - check exterior_body velocity
					var vel = vehicle.exterior_body.linear_velocity
					var angvel = vehicle.exterior_body.angular_velocity
					is_sleeping = vel.length() < 0.01 and angvel.length() < 0.01

				if is_sleeping:
					PhysicsServer3D.space_set_active(vehicle_space, false)

	# Check small container space
	if is_instance_valid(vehicle_container_small) and vehicle_container_small.container_interior_space.is_valid():
		var container_space = vehicle_container_small.container_interior_space
		if PhysicsServer3D.space_is_active(container_space):
			# Deactivate if no one is inside at all
			if not _is_anyone_in_container(vehicle_container_small):
				# Check if there are ANY docked vehicles
				var has_docked_vehicles = false
				var all_sleeping = true

				# Check if vehicle is docked in this container
				if is_instance_valid(vehicle) and vehicle.is_docked:
					var docked_container = vehicle._get_docked_container()
					if docked_container == vehicle_container_small:
						has_docked_vehicles = true
						if vehicle.dock_proxy_body.is_valid():
							var vel = PhysicsServer3D.body_get_state(vehicle.dock_proxy_body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
							var angvel = PhysicsServer3D.body_get_state(vehicle.dock_proxy_body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
							if vel.length() >= 0.01 or angvel.length() >= 0.01:
								all_sleeping = false

				# Deactivate if empty OR all bodies sleeping
				if not has_docked_vehicles or all_sleeping:
					PhysicsServer3D.space_set_active(container_space, false)

	# Check large container space
	if is_instance_valid(vehicle_container_large) and vehicle_container_large.container_interior_space.is_valid():
		var container_space = vehicle_container_large.container_interior_space
		if PhysicsServer3D.space_is_active(container_space):
			# Deactivate if no one is inside at all
			if not _is_anyone_in_container(vehicle_container_large):
				# Check if there are ANY docked vehicles/containers
				var has_docked_objects = false
				var all_sleeping = true

				# Check if vehicle is docked in this container
				if is_instance_valid(vehicle) and vehicle.is_docked:
					var docked_container = vehicle._get_docked_container()
					if docked_container == vehicle_container_large:
						has_docked_objects = true
						if vehicle.dock_proxy_body.is_valid():
							var vel = PhysicsServer3D.body_get_state(vehicle.dock_proxy_body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
							var angvel = PhysicsServer3D.body_get_state(vehicle.dock_proxy_body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
							if vel.length() >= 0.01 or angvel.length() >= 0.01:
								all_sleeping = false

				# Check if small container is docked in large container
				if is_instance_valid(vehicle_container_small) and vehicle_container_small.is_docked:
					has_docked_objects = true
					if vehicle_container_small.dock_proxy_body.is_valid():
						var vel = PhysicsServer3D.body_get_state(vehicle_container_small.dock_proxy_body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
						var angvel = PhysicsServer3D.body_get_state(vehicle_container_small.dock_proxy_body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
						if vel.length() >= 0.01 or angvel.length() >= 0.01:
							all_sleeping = false

				# Deactivate if empty OR all bodies sleeping
				if not has_docked_objects or all_sleeping:
					PhysicsServer3D.space_set_active(container_space, false)


func _get_outermost_container(start_container: VehicleContainer) -> VehicleContainer:
	# Find the highest level (outermost) container in the nesting hierarchy
	# Traverse up the chain while containers are docked in other containers
	if not is_instance_valid(start_container):
		return null
	
	var outermost = start_container
	while outermost and outermost.is_docked:
		var parent_container = outermost._get_docked_container()
		if parent_container:
			outermost = parent_container
		else:
			break
	
	return outermost

func _is_player_in_container(container: VehicleContainer) -> bool:
	# Check if player is in this SPECIFIC IMMEDIATE container
	# NOT in a parent container that this container is docked in
	# Player is in container if:
	# 1. They're directly in the container (character.is_in_container)
	# 2. They're in a vehicle that's docked in this container

	# Direct container check - player's physics space matches this container's space
	if character.is_in_container:
		# Get the container's interior space RID
		var container_space = container.get_interior_space()
		var player_space = PhysicsServer3D.body_get_space(character.proxy_body)
		# CRITICAL: Only return true if EXACTLY in THIS container's space
		# Not if player is in a nested container that's docked in this one
		if player_space == container_space:
			return true

	# Check if player is in vehicle docked in this container
	# But NOT if that vehicle is in a nested container
	if character.is_in_vehicle and is_instance_valid(vehicle) and vehicle.is_docked:
		var docked_container = vehicle._get_docked_container()
		if docked_container == container:
			return true

	return false

func _is_anyone_in_vehicle() -> bool:
	# Check if any character is in the vehicle
	if not is_instance_valid(vehicle):
		return false

	# Check if player is in vehicle
	if is_instance_valid(character) and character.is_in_vehicle:
		return true

	# Could check for other NPCs/players here in the future
	return false

func _is_anyone_in_container(container: VehicleContainer) -> bool:
	# Check if anyone (player or docked vehicles) is in the container
	if not is_instance_valid(container):
		return false

	# Check if player is directly in container
	if is_instance_valid(character) and character.is_in_container:
		var container_space = container.get_interior_space()
		var player_space = PhysicsServer3D.body_get_space(character.proxy_body)
		if player_space == container_space:
			return true

	# Check if vehicle is docked in this container
	if is_instance_valid(vehicle) and vehicle.is_docked:
		var docked_container = vehicle._get_docked_container()
		if docked_container == container:
			return true

	# Could check for other NPCs/players or nested containers here in the future
	return false

func _is_exit_position_blocked(world_position: Vector3, up_direction: Vector3, forward_direction: Vector3) -> bool:
	# Check if exit position is blocked using capsule shape at the exit opening
	# Returns true if blocked (can't exit safely), false if clear

	var space_state = get_world_3d().direct_space_state

	# Create query parameters for shape cast - use box instead of capsule for better entrance coverage
	var query = PhysicsShapeQueryParameters3D.new()

	# Create a box shape at the entrance opening (like a doorway)
	# This checks the rectangular area the player needs to walk through
	var shape = BoxShape3D.new()
	shape.size = Vector3(2.0, 2.0, 0.5)  # Wide enough for player (width, height, depth)
	query.shape = shape

	# Position the box at the exit opening, oriented with the exit direction
	# The box extends outward from the opening to check if there's clearance
	var box_basis = Basis()
	box_basis.z = forward_direction.normalized()
	box_basis.y = up_direction.normalized()
	box_basis.x = box_basis.y.cross(box_basis.z).normalized()

	# Place box at player head height, extending outward from the opening
	# This checks the space OUTSIDE the opening, not at the player's feet
	var check_pos = world_position + up_direction * 1.5 + forward_direction * 1.5
	query.transform = Transform3D(box_basis, check_pos)

	# Exclude certain collision layers
	query.collision_mask = 1  # Only layer 1

	# Exclude the vehicle and container bodies from collision check
	var exclude_rids = []
	if is_instance_valid(vehicle) and vehicle.exterior_body:
		exclude_rids.append(vehicle.exterior_body.get_rid())
	if is_instance_valid(vehicle_container_small) and vehicle_container_small.exterior_body:
		exclude_rids.append(vehicle_container_small.exterior_body.get_rid())
	if is_instance_valid(vehicle_container_large) and vehicle_container_large.exterior_body:
		exclude_rids.append(vehicle_container_large.exterior_body.get_rid())
	query.exclude = exclude_rids

	# Check if the exit opening overlaps with any collision (terrain, walls, etc.)
	var result = space_state.intersect_shape(query, 10)

	# Filter out the vehicle/container bodies and ground plane
	for hit in result:
		var collider = hit.collider
		# Skip if it's the vehicle or container we're exiting from
		if collider == vehicle or collider == vehicle_container_small or collider == vehicle_container_large:
			continue
		# Skip ground plane - we only care about walls/obstacles blocking the opening
		if collider.name == "Ground":
			continue
		# Found a blocking collision - exit opening is blocked
		return true

	# Exit opening is clear
	return false
