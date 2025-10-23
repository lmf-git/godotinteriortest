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
	print("[", category, "] ", message, " | ", data)
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

	# Create vehicle (spawn on ground, rotated to face player)
	# Vehicle is now 9 units tall (3*3), so y=4.5 puts bottom at ground level
	vehicle = Vehicle.new()
	vehicle.physics_proxy = physics_proxy
	vehicle.position = Vector3(0, 4.5, 50)  # Spaced further from player
	vehicle.rotation_degrees = Vector3(0, 180, 0)  # Rotate 180° so opening faces player
	add_child(vehicle)

	# Create character OUTSIDE vehicle (starts in world space)
	character = CharacterController.new()
	character.physics_proxy = physics_proxy
	character.position = Vector3(0, 2, -30)  # Spawn further back from origin
	add_child(character)

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
					if dual_camera.vehicle_container != container:
						dual_camera.vehicle_container = container
						print("[CAMERA] Switched camera to container: ", container.name)
					return

	# Check if player is in a vehicle docked in a container
	elif character.is_in_vehicle and is_instance_valid(vehicle) and vehicle.is_docked:
		var docked_container = vehicle._get_docked_container()
		if docked_container and dual_camera.vehicle_container != docked_container:
			dual_camera.vehicle_container = docked_container
			print("[CAMERA] Switched camera to docked container: ", docked_container.name)

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

	# Update debug text
	var space_name = character.current_space
	var world_pos = character.get_world_position()
	var proxy_pos = character.get_proxy_position()

	# Check if vehicle is docked
	var vehicle_docked = false
	if is_instance_valid(vehicle) and is_instance_valid(vehicle_container_small):
		vehicle_docked = vehicle.is_docked

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
Current Space: %s
In Vehicle: %s
In Container: %s
Vehicle Docked: %s
World Pos: (%.1f, %.1f, %.1f)
%s""" % [
		fps_counter,
		active_spaces,
		space_name,
		"YES" if character.is_in_vehicle else "NO",
		"YES" if character.is_in_container else "NO",
		"YES" if vehicle_docked else "NO",
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
		print("[VEHICLE ROTATION] Pitch up - is_docked: ", vehicle.is_docked)
	elif Input.is_key_pressed(KEY_C):
		var local_x = vehicle_basis.x
		vehicle.apply_rotation(local_x, -5000.0)
		print("[VEHICLE ROTATION] Pitch down - is_docked: ", vehicle.is_docked)

	# Yaw (X/V)
	if Input.is_key_pressed(KEY_X):
		var local_y = vehicle_basis.y
		vehicle.apply_rotation(local_y, 5000.0)
		print("[VEHICLE ROTATION] Yaw left - is_docked: ", vehicle.is_docked)
	elif Input.is_key_pressed(KEY_V):
		var local_y = vehicle_basis.y
		vehicle.apply_rotation(local_y, -5000.0)
		print("[VEHICLE ROTATION] Yaw right - is_docked: ", vehicle.is_docked)

	# Roll (Q/E)
	if Input.is_key_pressed(KEY_Q):
		var local_z = vehicle_basis.z
		vehicle.apply_rotation(local_z, 5000.0)
		print("[VEHICLE ROTATION] Roll left - is_docked: ", vehicle.is_docked)
	elif Input.is_key_pressed(KEY_E):
		var local_z = vehicle_basis.z
		vehicle.apply_rotation(local_z, -5000.0)
		print("[VEHICLE ROTATION] Roll right - is_docked: ", vehicle.is_docked)

	# Toggle magnetism (B key)
	if Input.is_action_just_pressed("ui_text_backspace") or Input.is_key_pressed(KEY_B):
		if vehicle.is_docked:
			vehicle.toggle_magnetism()

func _handle_container_controls() -> void:
	# Determine which container the player is in (if any)
	var current_container: VehicleContainer = null
	var thrust_force: float = 0.0

	# Check if player is in small container
	if is_instance_valid(vehicle_container_small) and _is_player_in_container(vehicle_container_small):
		current_container = vehicle_container_small
		thrust_force = 120000.0  # Small container: increased from 80000 for better control
	# Check if player is in large container
	elif is_instance_valid(vehicle_container_large) and _is_player_in_container(vehicle_container_large):
		current_container = vehicle_container_large
		thrust_force = 240000.0  # Large container: increased from 160000 (2x small container)

	# If not in any container, return early
	if not is_instance_valid(current_container):
		return

	# Get container basis for directional movement
	var container_basis = current_container.exterior_body.global_transform.basis

	# Container DIRECTIONAL controls (IJKL) - same for all containers
	if Input.is_key_pressed(KEY_I):
		# Forward (negative Z in container's local space)
		var forward = -container_basis.z
		current_container.apply_thrust(forward, thrust_force)

	if Input.is_key_pressed(KEY_K):
		# Backward (positive Z in container's local space)
		var backward = container_basis.z
		current_container.apply_thrust(backward, thrust_force)

	if Input.is_key_pressed(KEY_J):
		# Left (negative X in container's local space)
		var left = -container_basis.x
		current_container.apply_thrust(left, thrust_force)

	if Input.is_key_pressed(KEY_L):
		# Right (positive X in container's local space)
		var right = container_basis.x
		current_container.apply_thrust(right, thrust_force)

	# Container VERTICAL controls (U/P) - higher thrust to overcome gravity
	if Input.is_key_pressed(KEY_U):
		# Raise (positive Y in container's local space)
		var up = container_basis.y
		current_container.apply_thrust(up, thrust_force * 2.0)

	if Input.is_key_pressed(KEY_P):
		# Lower (negative Y in container's local space)
		var down = -container_basis.y
		current_container.apply_thrust(down, thrust_force * 2.0)

	# Container ROTATION controls (Arrow keys for pitch/yaw, N/M for roll)
	var rotation_torque = 15000.0  # Higher torque for larger container mass

	# Pitch (Up/Down arrows)
	if Input.is_key_pressed(KEY_UP):
		var local_x = container_basis.x
		current_container.apply_rotation(local_x, rotation_torque)
	elif Input.is_key_pressed(KEY_DOWN):
		var local_x = container_basis.x
		current_container.apply_rotation(local_x, -rotation_torque)

	# Yaw (Left/Right arrows)
	if Input.is_key_pressed(KEY_LEFT):
		var local_y = container_basis.y
		current_container.apply_rotation(local_y, rotation_torque)
	elif Input.is_key_pressed(KEY_RIGHT):
		var local_y = container_basis.y
		current_container.apply_rotation(local_y, -rotation_torque)

	# Roll (N/M keys)
	if Input.is_key_pressed(KEY_N):
		var local_z = container_basis.z
		current_container.apply_rotation(local_z, rotation_torque)
	elif Input.is_key_pressed(KEY_M):
		var local_z = container_basis.z
		current_container.apply_rotation(local_z, -rotation_torque)

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
			# Check if character walked into the vehicle entrance
			var char_world_pos = character.get_world_position()
			var vehicle_transform = vehicle.exterior_body.global_transform

			# Get relative position (vector from vehicle to character)
			var relative_pos = char_world_pos - vehicle_transform.origin

			# Transform relative position to vehicle local space
			var local_pos = vehicle_transform.basis.inverse() * relative_pos

			# Check if character is at the entrance (front opening)
			# Ship is rotated 180°, so when approaching from behind (world -Z),
			# the local Z is POSITIVE (ship's local -Z points backward in world +Z)
			# Detect entrance while approaching floor edge (still within floor bounds)
			var at_entrance = (
				abs(local_pos.x) < 9.0 and
				abs(local_pos.y) < 4.5 and
				local_pos.z > 14.0 and local_pos.z < 15.0  # Approaching floor edge from outside
			)

			if at_entrance and not character.is_in_container:
				# Player in world space entering undocked ship
				# Keep world up direction (ship rotates freely in space, gravity is always down)
				# Adjust yaw because ship entrance faces backward (ship rotated 180°)
				if is_instance_valid(dual_camera):
					dual_camera.set_target_up_direction(Vector3.UP)
					# Add PI to yaw to compensate for ship's 180° rotation
					dual_camera.base_rotation.y += PI

				# Get current world velocity and transform to vehicle local space
				var world_velocity = character.get_world_velocity()
				var local_velocity = vehicle_transform.basis.inverse() * world_velocity

				# Activate vehicle interior space if needed
				var vehicle_space = vehicle.get_interior_space()
				if not PhysicsServer3D.space_is_active(vehicle_space):
					PhysicsServer3D.space_set_active(vehicle_space, true)

				# Set proxy_body's space to vehicle's interior space
				PhysicsServer3D.body_set_space(character.proxy_body, vehicle_space)

				# Seamlessly enter - use exact transformed position (no clamping)
				# This matches the exit behavior which is perfectly seamless
				character.enter_vehicle()
				character.set_proxy_position(local_pos, local_velocity)
				# Set character visual orientation to match ship (world basis)
				vehicle_transition_cooldown = TRANSITION_COOLDOWN_TIME
			elif character.is_in_container and vehicle.is_docked:
				# Player in container space, check if can enter docked ship
				# Get player position in container space
				var player_container_pos = character.get_proxy_position()

				# Get ship's dock_proxy_body position in container space
				var ship_dock_transform = PhysicsServer3D.body_get_state(vehicle.dock_proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM)

				# Calculate player position relative to ship
				var relative_to_ship = player_container_pos - ship_dock_transform.origin
				var ship_local_pos = ship_dock_transform.basis.inverse() * relative_to_ship

				# Check if at ship entrance - narrower zone to prevent re-entry after exit
				# Entry only when further inside: 13.0 < z < 14.5 (was 14.0 < z < 15.0)
				# Exit still happens at z > 15.0, creating 0.5 unit buffer
				var at_docked_ship_entrance = (
					abs(ship_local_pos.x) < 9.0 and
					abs(ship_local_pos.y) < 4.5 and
					ship_local_pos.z > 13.0 and ship_local_pos.z < 14.5
				)

				if at_docked_ship_entrance:
					# Player entering docked ship from container
					# Seamless entry - no clamping (same as undocked ship entry)
					# Entry zone: 14.0 < z < 15.0
					# Exit threshold: z > 15.0
					# No overlap, so no clamp needed
					print("ENTERING DOCKED SHIP:")
					print("  Player container pos: ", player_container_pos)
					print("  Ship dock pos: ", ship_dock_transform.origin)
					print("  Ship local pos: ", ship_local_pos)

					# Get velocity in container space and transform to ship space
					var container_velocity = character.get_proxy_velocity()
					var ship_local_velocity = ship_dock_transform.basis.inverse() * container_velocity

					# Find which container the ship is docked in (reuse for both camera and character)
					var docked_container = vehicle._get_docked_container()

					# CRITICAL: Adjust camera orientation for container->ship transition
					# Transition camera up direction to match ship interior
					if is_instance_valid(dual_camera):
						# Ship's Y axis in container space is the ship's "up"
						var ship_up_in_container = ship_dock_transform.basis.y
						if docked_container and docked_container.exterior_body:
							# Transform to world space
							var container_transform = docked_container.exterior_body.global_transform
							var ship_up_world = container_transform.basis * ship_up_in_container
							dual_camera.set_target_up_direction(ship_up_world)
							# Don't adjust yaw - player's look direction maintained
							# Ship and container are both in same coordinate system
							print("ENTERING DOCKED SHIP: Setting up direction to ship's Y axis")

					# CRITICAL: Exit container state before entering vehicle
					# This ensures clean transition from container -> vehicle
					character.exit_container()

					# Activate vehicle interior space if needed
					var vehicle_space = vehicle.get_interior_space()
					if not PhysicsServer3D.space_is_active(vehicle_space):
						PhysicsServer3D.space_set_active(vehicle_space, true)

					# Set proxy_body's space to vehicle's interior space
					PhysicsServer3D.body_set_space(character.proxy_body, vehicle_space)

					character.enter_vehicle()
					character.set_proxy_position(ship_local_pos, ship_local_velocity)

					# Set character visual orientation to match docked ship
					# Ship's orientation in world space (reuse docked_container from above)
					if docked_container and docked_container.exterior_body:
						var container_transform = docked_container.exterior_body.global_transform
						var ship_world_basis = container_transform.basis * ship_dock_transform.basis

					# Set BOTH cooldowns to prevent immediate exit
					vehicle_transition_cooldown = TRANSITION_COOLDOWN_TIME
					container_transition_cooldown = TRANSITION_COOLDOWN_TIME

					print("  Entered ship at position: ", ship_local_pos)

	# Check container transition zones - seamless entry/exit for ALL containers
	if character.is_in_container and container_transition_cooldown <= 0:
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
			
			# Check if character walked outside container proxy bounds
			var proxy_pos = character.get_proxy_position()
			
			# Calculate exit threshold based on container size
			var size_scale = 3.0 * container.size_multiplier
			var half_length = 5.0 * size_scale
			var exited_container = proxy_pos.z > half_length
			
			if exited_container:
				# Get current proxy velocity
				var proxy_velocity = character.get_proxy_velocity()

				# CRITICAL: Check if should enter vehicle that's docked inside BEFORE exiting container
				# This prevents teleporting through world space
				var entering_docked_ship = false
				if is_instance_valid(vehicle) and vehicle.is_docked:
					# CRITICAL: Ship is docked in this container, use dock_proxy_body in container space
					# Don't go through world space - stay in container space
					var ship_dock_transform = PhysicsServer3D.body_get_state(vehicle.dock_proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM)

					# Check distance from character to ship (both in container space)
					var dist_to_ship = proxy_pos.distance_to(ship_dock_transform.origin)

					# If close to ship (within ~30 units), enter ship interior
					if dist_to_ship < 30.0:
						entering_docked_ship = true

						# Transform from container space to ship local space
						var relative_pos = proxy_pos - ship_dock_transform.origin
						var vehicle_local_pos = ship_dock_transform.basis.inverse() * relative_pos

						# Transform velocity from container space to ship local space
						var vehicle_local_velocity = ship_dock_transform.basis.inverse() * proxy_velocity

						# Exit container state
						character.exit_container()

						# Activate vehicle interior space if needed
						var vehicle_space = vehicle.get_interior_space()
						if not PhysicsServer3D.space_is_active(vehicle_space):
							PhysicsServer3D.space_set_active(vehicle_space, true)

						# Set proxy_body's space to vehicle's interior space
						PhysicsServer3D.body_set_space(character.proxy_body, vehicle_space)

						character.enter_vehicle()
						character.set_proxy_position(vehicle_local_pos, vehicle_local_velocity)

				# Only exit to world if NOT entering docked ship
				if not entering_docked_ship:
					# Calculate world position for exit
					var container_transform = container.exterior_body.global_transform
					var world_velocity = container_transform.basis * proxy_velocity
					var world_pos = container_transform.origin + container_transform.basis * proxy_pos

					# Get forward direction in world space (container's +Z is forward)
					var exit_forward = container_transform.basis.z

					# CRITICAL: Check if exit position is blocked in exterior world
					if _is_exit_position_blocked(world_pos, Vector3.UP, exit_forward):
						print("[CONTAINER EXIT] Exit blocked - stopping at boundary")
						# Stop at the boundary - don't allow forward movement past exit threshold
						# Don't process the exit transition
						break

					# Exit container state
					character.exit_container()

					# Set character visual orientation to world up

					# Transition camera up direction back to world up
					if is_instance_valid(dual_camera):
						dual_camera.set_target_up_direction(Vector3.UP)
						dual_camera.base_rotation.y -= PI  # Reverse the entrance rotation

					character.set_world_position(world_pos, world_velocity)

				# Check if container space can be deactivated (no one left inside)
				if not _is_anyone_in_container(container):
					if PhysicsServer3D.space_is_active(container_space):
						PhysicsServer3D.space_set_active(container_space, false)
				
				container_transition_cooldown = TRANSITION_COOLDOWN_TIME
				break


	elif character.is_in_vehicle and container_transition_cooldown <= 0:
		# Check if character (in ship interior) entered station/container zone
		# This happens when ship is docked and player walks from ship into station
		# Get ship proxy position
		var ship_proxy_pos = character.get_proxy_position()

		# Check if player walked OUT of the ship's front opening
		# Ship interior extends from z=-15 to z=+15
		# Only transition when player walks PAST the ship's front edge
		var exited_ship_front = ship_proxy_pos.z > 15.0

		# Debug logging - debounced (only when ship is docked)
		if is_instance_valid(vehicle) and vehicle.is_docked and exited_ship_front:
			_debounced_log("SHIP->STATION", "Player exited ship front", {
				"ship_proxy_x": ship_proxy_pos.x,
				"ship_proxy_y": ship_proxy_pos.y,
				"ship_proxy_z": ship_proxy_pos.z
			})

		# Check if player walked out of docked ship - use spatial detection
		if exited_ship_front and is_instance_valid(vehicle):
			# Get current proxy velocity
			var proxy_velocity = character.get_proxy_velocity()

			# Check if ship is docked in ANY container and player exit position is inside it
			# DO THIS BEFORE exit_vehicle() to prevent one-frame gap
			# Loop through all containers (universal system)
			var should_enter_container = false
			var target_container: VehicleContainer = null
			var container_proxy_pos: Vector3
			var world_pos: Vector3
			var world_velocity: Vector3

			print("[SHIP EXIT DEBUG] Ship is_docked: ", vehicle.is_docked)
			print("[SHIP EXIT DEBUG] Ship proxy pos: ", ship_proxy_pos)

			if vehicle.is_docked:
				var actual_docked = vehicle._get_docked_container()
				print("[SHIP EXIT DEBUG] Ship actually docked in: ", actual_docked.name if actual_docked else "null")
				var containers = [vehicle_container_small, vehicle_container_large]

				for container in containers:
					if not is_instance_valid(container) or not container.exterior_body:
						continue

					# Check if ship is docked in THIS container
					var docked_container = vehicle._get_docked_container()
					print("[SHIP EXIT DEBUG] Checking container: ", container.name)
					print("[SHIP EXIT DEBUG] Docked container: ", docked_container.name if docked_container else "null")
					if docked_container != container:
						continue

					# CRITICAL: When ship is docked, use dock_proxy_body transform (in container space)
					# NOT exterior_body transform (in world space)
					var ship_dock_transform = PhysicsServer3D.body_get_state(vehicle.dock_proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM)

					# Transform ship proxy pos (in ship's interior space) to container space
					container_proxy_pos = ship_dock_transform.origin + ship_dock_transform.basis * ship_proxy_pos

					print("[SHIP EXIT DEBUG] Ship dock transform origin: ", ship_dock_transform.origin)
					print("[SHIP EXIT DEBUG] Container proxy pos: ", container_proxy_pos)

					# Calculate container bounds dynamically based on size
					var size_scale = 3.0 * container.size_multiplier
					var half_width = 3.0 * size_scale
					var half_height = 1.5 * size_scale
					var half_length = 5.0 * size_scale

					print("[SHIP EXIT DEBUG] Container bounds: ±", half_width, " x ±", half_height, " x ±", half_length)

					# Calculate actual floor position for comparison
					var floor_y = -1.5 * size_scale + 0.1
					print("[SHIP EXIT DEBUG] Container floor Y: ", floor_y)
					print("[SHIP EXIT DEBUG] Player Y: ", container_proxy_pos.y)

					# Check each bound individually for debugging
					# Add buffer to Y bounds to allow players standing on floor
					# Floor is at -1.5*size_scale + 0.1, so allow 2 units below that for safety
					var y_min = -half_height - 2.0
					var y_max = half_height + 1.0

					var x_ok = abs(container_proxy_pos.x) < half_width
					var y_ok = container_proxy_pos.y > y_min and container_proxy_pos.y < y_max
					var z_ok = container_proxy_pos.z > -half_length and container_proxy_pos.z < half_length

					print("[SHIP EXIT DEBUG] X check: ", x_ok, " (", container_proxy_pos.x, " vs ±", half_width, ")")
					print("[SHIP EXIT DEBUG] Y check: ", y_ok, " (", container_proxy_pos.y, " vs ", y_min, " to ", y_max, ")")
					print("[SHIP EXIT DEBUG] Z check: ", z_ok, " (", container_proxy_pos.z, " vs ", -half_length, " to ", half_length, ")")

					# Check if exit position is actually INSIDE the container interior space
					var inside_container = x_ok and y_ok and z_ok

					print("[SHIP EXIT DEBUG] Inside container: ", inside_container)

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
			character.exit_vehicle()

			# Check if vehicle space can be deactivated (no one left inside)
			if not _is_anyone_in_vehicle():
				var vehicle_space = vehicle.get_interior_space()
				if PhysicsServer3D.space_is_active(vehicle_space):
					PhysicsServer3D.space_set_active(vehicle_space, false)

			print("[SHIP EXIT] should_enter_container: ", should_enter_container)
			if target_container:
				print("[SHIP EXIT] target_container: ", target_container.name)
			else:
				print("[SHIP EXIT] target_container: null")

			if should_enter_container and target_container:
				print("[SHIP EXIT] Exiting ship into container: ", target_container.name)
				print("[SHIP EXIT] Container proxy pos: ", container_proxy_pos)

				# Transform velocity from ship interior space to container space
				# proxy_velocity is in ship's interior space
				# Need to transform through ship's dock_proxy_body basis to get to container space
				var ship_dock_transform = PhysicsServer3D.body_get_state(vehicle.dock_proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM)
				var container_velocity = ship_dock_transform.basis * proxy_velocity

				print("[SHIP EXIT] Proxy velocity (ship space): ", proxy_velocity)
				print("[SHIP EXIT] Container velocity: ", container_velocity)

				# CRITICAL: Adjust camera orientation for ship->container transition
				# Transition camera up direction from ship to container
				if is_instance_valid(dual_camera) and target_container and target_container.exterior_body:
					# Container's Y axis is the container's "up"
					var container_up = target_container.exterior_body.global_transform.basis.y
					dual_camera.set_target_up_direction(container_up)
					# Don't adjust yaw - the orientation transition handles it
					# (We subtracted PI when entering ship, so adding PI here would cancel out)
					print("[SHIP EXIT] Transitioning up direction to container's Y axis")

				# Activate container space if needed
				var container_space = target_container.get_interior_space()
				if not PhysicsServer3D.space_is_active(container_space):
					PhysicsServer3D.space_set_active(container_space, true)

				# Set proxy_body's space to container's interior space
				PhysicsServer3D.body_set_space(character.proxy_body, container_space)

				# Use natural container position - seamless physics transition
				# Don't push player, let them exit naturally with their momentum
				character.enter_container()
				character.set_proxy_position(container_proxy_pos, container_velocity)
				print("[SHIP EXIT] Character is_in_container: ", character.is_in_container)
				print("[SHIP EXIT] Container position: ", container_proxy_pos, " velocity: ", container_velocity)

				# Set character visual orientation to match container
				if target_container and target_container.exterior_body:
					var container_basis = target_container.exterior_body.global_transform.basis

				# Set BOTH cooldowns to prevent immediate re-entry
				vehicle_transition_cooldown = TRANSITION_COOLDOWN_TIME
				container_transition_cooldown = TRANSITION_COOLDOWN_TIME
			else:
				# Exit position is outside container OR ship not docked - exit to world space

				# Get forward direction in world space (ship's +Z is forward)
				var vehicle_transform = vehicle.exterior_body.global_transform
				var exit_forward = vehicle_transform.basis.z

				# CRITICAL: Check if exit position is blocked in exterior world
				if _is_exit_position_blocked(world_pos, Vector3.UP, exit_forward):
					print("[SHIP EXIT] Exit blocked - stopping at boundary")
					# Stop at the boundary - don't allow exit transition
					# Don't process the exit
				else:
					# Exit is clear - proceed
					# Transition camera up direction back to world up
					# Subtract PI from yaw to reverse the entrance rotation
					if is_instance_valid(dual_camera):
						dual_camera.set_target_up_direction(Vector3.UP)
						# Subtract PI to reverse the entrance yaw adjustment
						dual_camera.base_rotation.y -= PI

					character.set_world_position(world_pos, world_velocity)

					# Set character visual orientation to world up

					# Set vehicle cooldown for ship→world exit
					vehicle_transition_cooldown = TRANSITION_COOLDOWN_TIME

	else:
		# Character in world space - check if entering ANY container from outside
		# Loop through all containers (same pattern as vehicle docking)
		var containers = [vehicle_container_small, vehicle_container_large]

		for container in containers:
			if not is_instance_valid(container) or not container.exterior_body:
				continue

			var char_world_pos = character.get_world_position()
			var container_transform = container.exterior_body.global_transform

			# Get relative position (vector from container to character)
			var relative_pos = char_world_pos - container_transform.origin

			# Transform relative position to container local space
			var local_pos = container_transform.basis.inverse() * relative_pos

			# Calculate entrance detection zone based on container size
			# Ship detection: 14-15 out of 15 (1 unit inside)
			# Container detection: proportional (1-2 units inside)
			var size_scale = 3.0 * container.size_multiplier
			var half_width = 3.0 * size_scale  # Width is 6 * size_scale
			var half_height = 1.5 * size_scale  # Height is 3 * size_scale
			var half_length = 5.0 * size_scale  # Length is 10 * size_scale
			# Calculate floor level for entrance detection - must be at/above floor
			# Floor top is at -1.5 * size_scale + 0.1 (interior proxy collider top surface)
			var floor_top_y = -1.5 * size_scale + 0.1


			var at_container_entrance = (
			abs(local_pos.x) < half_width and
			local_pos.y > floor_top_y - 1.0 and local_pos.y < (half_height + 1.0) and  # Must be at/above floor level
			local_pos.z > (half_length - 2.0) and local_pos.z < (half_length - 1.0)  # 1-2 units inside
			)

			# Debug: show when near container entrance
			if abs(local_pos.z - half_length) < 5.0 and abs(local_pos.x) < half_width:
				print("[CONTAINER ENTRANCE DEBUG] ", container.name)
				print("  local_pos: ", local_pos)
				print("  half_length: ", half_length, " z range: ", half_length - 2.0, " to ", half_length - 1.0)
				print("  floor_top_y: ", floor_top_y, " y range: ", floor_top_y - 1.0, " to ", half_height + 1.0)
				print("  at_entrance: ", at_container_entrance)
				print("  in_world: ", not character.is_in_container and not character.is_in_vehicle)


			# CRITICAL: Only trigger if player is in world space (not in vehicle or container)
			# When player is inside docked ship, they stay in vehicle interior until they walk out
			if at_container_entrance and not character.is_in_container and not character.is_in_vehicle:
				# Transition camera up direction to match container
				if is_instance_valid(dual_camera):
					var container_up = container_transform.basis.y
					dual_camera.set_target_up_direction(container_up)
					dual_camera.base_rotation.y += PI  # Flip yaw for 180° entrance

				# Get current world velocity and transform to container local space
				var world_velocity = character.get_world_velocity()
				var local_velocity = container_transform.basis.inverse() * world_velocity

				# Activate container space if needed
				var container_space = container.get_interior_space()
				if not PhysicsServer3D.space_is_active(container_space):
					PhysicsServer3D.space_set_active(container_space, true)

				# Set proxy_body's space to container's interior space
				PhysicsServer3D.body_set_space(character.proxy_body, container_space)

				# Seamlessly enter - use exact transformed position with safety Y minimum
				# Prevent falling through floor while keeping seamless horizontal transition
				var container_floor_y = -1.5 * size_scale + 0.1  # Floor flush with walls
				var player_min_y = container_floor_y + 0.7  # Player capsule center minimum (on floor)

				var safe_pos = Vector3(
					local_pos.x,
					max(local_pos.y, player_min_y),  # Only clamp if below floor
					local_pos.z
				)

				character.enter_container()
				character.set_proxy_position(safe_pos, local_velocity)

				# Set character visual orientation to match container
				var container_basis = container.exterior_body.global_transform.basis

				container_transition_cooldown = TRANSITION_COOLDOWN_TIME
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
			# ship from docking while still outside/above the container
			# Exterior bounds: ±(3.0*scale) width, ±(1.5*scale) height, ±(5.0*scale) length
			# Docking bounds: Reduce by 3 units on each side for safety margin
			var size_scale = 3.0 * container.size_multiplier
			var half_width = 3.0 * size_scale - 3.0  # 3 unit margin from walls
			var half_height = 1.5 * size_scale - 3.0  # 3 unit margin from floor/ceiling
			var half_length = 5.0 * size_scale - 3.0  # 3 unit margin from back wall

			# Seamless entry/exit at boundary - like player transitions
			# Ship collision box is 30 units long (±15 from center)
			# Enter when ship's ENTIRE collision box is inside container
			# Container front is at z=half_length (75 for small, 150 for large)
			var ship_half_length = 15.0  # Ship collision box half-length
			var enter_z = half_length - ship_half_length - 5.0   # Enter when fully inside (ship front < container front)

			# CRITICAL: Exit EARLY while ship is still mostly inside
			# This allows ship to transition to world physics before leaving container exterior
			# Exit when ship center reaches near the opening (not when fully outside)
			var exit_z = enter_z + 10.0  # Exit just 10 units past entry point (still well inside)

			# Check each condition individually for debugging
			var x_inside = abs(local_pos.x) < half_width - 5.0
			var y_inside_min = local_pos.y > -half_height - 5.0
			var y_inside_max = local_pos.y < half_height + 5.0
			var z_inside_front = local_pos.z < enter_z
			var z_inside_back = local_pos.z > -half_length + 5.0  # CRITICAL: Also check not behind back wall

			var vehicle_inside = x_inside and y_inside_min and y_inside_max and z_inside_front and z_inside_back

			var x_outside = abs(local_pos.x) > half_width + 5.0
			var y_outside_min = local_pos.y < -half_height - 10.0
			var y_outside_max = local_pos.y > half_height + 10.0
			var z_outside_back = local_pos.z < -half_length - 10.0
			var z_outside_front = local_pos.z > exit_z

			var vehicle_outside = x_outside or y_outside_min or y_outside_max or z_outside_back or z_outside_front

			# Debug output only when actually docking/undocking
			if vehicle_inside and not vehicle.is_docked:
				print("[DOCK DEBUG ENTERING] ", container.name, " local_pos: ", local_pos)
				print("  enter_z: ", enter_z, " exit_z: ", exit_z, " half_length: ", half_length)
				print("  x_inside: ", x_inside, " y_inside: ", y_inside_min and y_inside_max)
				print("  z_inside_front: ", z_inside_front, " z_inside_back: ", z_inside_back)
			elif vehicle_outside and vehicle.is_docked:
				var docked_container = vehicle._get_docked_container()
				if docked_container == container:
					print("[DOCK DEBUG EXITING] ", container.name, " local_pos: ", local_pos)
					print("  enter_z: ", enter_z, " exit_z: ", exit_z)
					print("  x_outside: ", x_outside, " y_out_min: ", y_outside_min, " y_out_max: ", y_outside_max)
					print("  z_out_back: ", z_outside_back, " z_out_front: ", z_outside_front)

			if vehicle_inside and not vehicle.is_docked:
				# Vehicle entering THIS container - seamless transition at boundary
				var container_name = "Small" if container == vehicle_container_small else "Large"
				_debounced_log("DOCKING", "Vehicle entered " + container_name + " container", {
					"x": local_pos.x,
					"y": local_pos.y,
					"z": local_pos.z
				})
				vehicle.set_docked(true, container)
				break  # Only dock in one container
			elif vehicle_outside and vehicle.is_docked:
				# Check if docked in THIS container before undocking
				var docked_container = vehicle._get_docked_container()
				if docked_container == container:
					# Vehicle leaving THIS container
					_debounced_log("DOCKING", "Vehicle left dock zone", {
						"x": local_pos.x,
						"y": local_pos.y,
						"z": local_pos.z
					})
					vehicle.set_docked(false, container)

					# Check if container space can be deactivated (no one left inside after undocking)
					if not _is_anyone_in_container(container):
						var container_space = container.get_interior_space()
						if PhysicsServer3D.space_is_active(container_space):
							PhysicsServer3D.space_set_active(container_space, false)

					break

		# Check container-in-container docking (small container docking in large container)
	if is_instance_valid(vehicle_container_small) and vehicle_container_small.exterior_body and is_instance_valid(vehicle_container_large) and vehicle_container_large.exterior_body:
		# Transform small container's world position to large container's local space
		var small_world_pos = vehicle_container_small.exterior_body.global_position
		var large_transform = vehicle_container_large.exterior_body.global_transform
		var relative_pos = small_world_pos - large_transform.origin
		var local_pos = large_transform.basis.inverse() * relative_pos

		# Docking zone with HYSTERESIS for containers
		# Large container is 10x ship: 180 wide (±90), 90 tall (±45), 300 long (±150)
		# Small container is 5x ship: 90 wide (±45), 45 tall (±22.5), 150 long (±75)
		# Opening is at z=+150 for large container
		# ENTER zone: z < 110 (container must be well inside)
		# EXIT zone: z > 130 (container must move significantly out)
		var small_fully_inside = (
		abs(local_pos.x) < 60.0 and
		local_pos.y > -45.0 and local_pos.y < 45.0 and
		local_pos.z > -120.0 and local_pos.z < 110.0  # Enter threshold
		)

		var small_outside = (
		abs(local_pos.x) > 70.0 or  # Wider exit threshold
		local_pos.y < -50.0 or local_pos.y > 50.0 or
		local_pos.z < -130.0 or local_pos.z > 130.0  # Exit threshold (20 units more permissive)
		)

		if small_fully_inside and not vehicle_container_small.is_docked:
			# Small container entering large container dock
			vehicle_container_small.set_docked(true, vehicle_container_large)
		elif small_outside and vehicle_container_small.is_docked:
			# Small container leaving large container dock (requires moving further out)
			vehicle_container_small.set_docked(false, vehicle_container_large)

# Physics space optimization: spaces activate on-demand and deactivate when empty or all bodies are sleeping

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
					print("[SLEEP OPT] Deactivated vehicle space (sleeping)")

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
					print("[SLEEP OPT] Deactivated small container space (empty or sleeping)")

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
					print("[SLEEP OPT] Deactivated large container space (empty or sleeping)")

func _is_player_in_container(container: VehicleContainer) -> bool:
	# Check if player is in this specific container
	# Player is in container if:
	# 1. They're directly in the container (character.is_in_container)
	# 2. They're in a vehicle that's docked in this container

	# Direct container check
	if character.is_in_container:
		# Get the container's interior space RID
		var container_space = container.get_interior_space()
		var player_space = PhysicsServer3D.body_get_space(character.proxy_body)
		if player_space == container_space:
			return true

	# Check if player is in vehicle docked in this container
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
	# The box should be right at the entrance, checking if it's blocked
	var box_basis = Basis()
	box_basis.z = forward_direction.normalized()
	box_basis.y = up_direction.normalized()
	box_basis.x = box_basis.y.cross(box_basis.z).normalized()

	# Place box right at the exit position
	var check_pos = world_position + forward_direction * 0.25  # Slightly forward into the opening
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

	# Filter out the vehicle/container bodies
	for hit in result:
		var collider = hit.collider
		# Skip if it's the vehicle or container we're exiting from
		if collider == vehicle or collider == vehicle_container_small or collider == vehicle_container_large:
			continue
		# Found a blocking collision - exit opening is blocked
		print("[EXIT CHECK] Exit opening blocked by: ", collider.name if collider else "unknown")
		return true

	# Exit opening is clear
	print("[EXIT CHECK] Exit opening clear")
	return false
