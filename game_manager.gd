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
	# Container floor is at y=-1.4*15.0 = -21.0 relative to center, so y=21.0 puts floor at ground level
	vehicle_container_small = VehicleContainer.new()
	vehicle_container_small.name = "VehicleContainerSmall"
	vehicle_container_small.physics_proxy = physics_proxy
	vehicle_container_small.size_multiplier = 5.0  # 5x ship size (default)
	vehicle_container_small.position = Vector3(0, 21.0, 350)  # Closer container
	vehicle_container_small.rotation_degrees = Vector3(0, 180, 0)  # Rotate 180° so opening faces player
	add_child(vehicle_container_small)

	# Create LARGE vehicle container (10x ship = 2x default size)
	# Container floor is at y=-1.4*30.0 = -42.0 relative to center, so y=42.0 puts floor at ground level
	vehicle_container_large = VehicleContainer.new()
	vehicle_container_large.name = "VehicleContainerLarge"
	vehicle_container_large.physics_proxy = physics_proxy
	vehicle_container_large.size_multiplier = 10.0  # 10x ship size (2x default container)
	vehicle_container_large.position = Vector3(0, 42.0, 750)  # Further back, larger container
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
  Arrow Keys - Pitch/Yaw
  Q/E - Roll
  B - Toggle Docking Magnetism

CONTAINER CONTROLS (when in active container):
  I - Forward    | U - Raise
  J - Left       | P - Lower
  K - Backward   |
  L - Right      |
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

	_update_debug_ui()
	_handle_input()
	_check_transitions()

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

	# Character movement input
	var move_dir := Vector3.ZERO

	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		var forward = dual_camera.get_forward_direction()
		move_dir += forward
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		var forward = dual_camera.get_forward_direction()
		move_dir -= forward
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		var right = dual_camera.get_right_direction()
		move_dir -= right
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
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

	# Vehicle ROTATION controls (Arrow keys and Q/E)
	# Pitch (Up/Down arrows)
	if Input.is_key_pressed(KEY_UP):
		var local_x = vehicle_basis.x
		vehicle.apply_rotation(local_x, 500.0)
	elif Input.is_key_pressed(KEY_DOWN):
		var local_x = vehicle_basis.x
		vehicle.apply_rotation(local_x, -500.0)

	# Yaw (Left/Right arrows)
	if Input.is_key_pressed(KEY_LEFT):
		var local_y = vehicle_basis.y
		vehicle.apply_rotation(local_y, 500.0)
	elif Input.is_key_pressed(KEY_RIGHT):
		var local_y = vehicle_basis.y
		vehicle.apply_rotation(local_y, -500.0)

	# Roll (Q/E)
	if Input.is_key_pressed(KEY_Q):
		var local_z = vehicle_basis.z
		vehicle.apply_rotation(local_z, 500.0)
	elif Input.is_key_pressed(KEY_E):
		var local_z = vehicle_basis.z
		vehicle.apply_rotation(local_z, -500.0)

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
		thrust_force = 15000.0
	# Check if player is in large container
	elif is_instance_valid(vehicle_container_large) and _is_player_in_container(vehicle_container_large):
		current_container = vehicle_container_large
		thrust_force = 25000.0  # Larger container needs more thrust

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
				# Get current proxy velocity and transform to world space
				var proxy_velocity = character.get_proxy_velocity()
				var vehicle_transform = vehicle.exterior_body.global_transform
				var world_velocity = vehicle_transform.basis * proxy_velocity

				# Transform current proxy position to world position
				var world_pos = vehicle_transform.origin + vehicle_transform.basis * proxy_pos

				character.exit_vehicle()

				# Check if ship is docked and player exit position is inside container bounds
				var should_enter_container = false
				var container_transform: Transform3D
				var container_proxy_pos: Vector3

				if is_instance_valid(vehicle_container_small) and vehicle.is_docked:
					container_transform = vehicle_container_small.exterior_body.global_transform

					# Calculate where player will be in container space
					var ship_dock_transform = PhysicsServer3D.body_get_state(vehicle.dock_proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM)
					container_proxy_pos = ship_dock_transform.origin + ship_dock_transform.basis * proxy_pos

					# Container is 5x ship: 90 wide (±45), 45 tall (floor -21 to ceiling +21), 150 long (±75)
					# Check if exit position is actually INSIDE the container interior space
					var inside_container = (
						abs(container_proxy_pos.x) < 45.0 and
						container_proxy_pos.y > -21.0 and container_proxy_pos.y < 21.0 and
						container_proxy_pos.z > -75.0 and container_proxy_pos.z < 75.0
					)

					should_enter_container = inside_container

				if should_enter_container:
					# Exit position is inside container - enter container proxy space
					# Don't adjust camera - we're staying in proxy space (ship -> container)
					var local_velocity = container_transform.basis.inverse() * world_velocity

					# Set proxy_body's space to container's interior space
					PhysicsServer3D.body_set_space(character.proxy_body, vehicle_container_small.get_interior_space())

					character.enter_container()
					character.set_proxy_position(container_proxy_pos, local_velocity)
				else:
					# Exit position is outside container OR ship not docked - exit to world space
					# Adjust camera for 180° ship rotation - subtract PI from yaw
					if is_instance_valid(dual_camera):
						dual_camera.base_rotation.y -= PI

					character.set_world_position(world_pos, world_velocity)

				vehicle_transition_cooldown = TRANSITION_COOLDOWN_TIME
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
				# Player in world space entering ship
				# Adjust camera for 180° ship rotation - add PI to yaw
				if is_instance_valid(dual_camera):
					dual_camera.base_rotation.y += PI

				# Get current world velocity and transform to vehicle local space
				var world_velocity = character.get_world_velocity()
				var local_velocity = vehicle_transform.basis.inverse() * world_velocity

				# Set proxy_body's space to vehicle's interior space
				PhysicsServer3D.body_set_space(character.proxy_body, vehicle.get_interior_space())

				# Seamlessly enter - use exact transformed position (no clamping)
				# This matches the exit behavior which is perfectly seamless
				character.enter_vehicle()
				character.set_proxy_position(local_pos, local_velocity)
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

				# Check if at ship entrance (same bounds as world entry)
				var at_docked_ship_entrance = (
					abs(ship_local_pos.x) < 9.0 and
					abs(ship_local_pos.y) < 4.5 and
					ship_local_pos.z > 14.0 and ship_local_pos.z < 15.0
				)

				if at_docked_ship_entrance:
					# Player entering docked ship from container
					print("ENTERING DOCKED SHIP:")
					print("  Player container pos: ", player_container_pos)
					print("  Ship dock pos: ", ship_dock_transform.origin)
					print("  Ship local pos (setting): ", ship_local_pos)

					# Get velocity in container space and transform to ship space
					var container_velocity = character.get_proxy_velocity()
					var ship_local_velocity = ship_dock_transform.basis.inverse() * container_velocity

					# CRITICAL: Exit container state before entering vehicle
					# This ensures clean transition from container -> vehicle
					character.exit_container()

					# Set proxy_body's space to vehicle's interior space
					PhysicsServer3D.body_set_space(character.proxy_body, vehicle.get_interior_space())

					character.enter_vehicle()
					character.set_proxy_position(ship_local_pos, ship_local_velocity)
					vehicle_transition_cooldown = TRANSITION_COOLDOWN_TIME

					print("  Entered ship at position: ", ship_local_pos)

	if not is_instance_valid(vehicle_container_small):
		return

	# Check container transition zone - seamless entry/exit
	if vehicle_container_small.transition_zone and container_transition_cooldown <= 0:
		if character.is_in_container:
			# Check if character walked outside container proxy bounds
			var proxy_pos = character.get_proxy_position()

			# Container proxy floor extends from z=-75 to z=+75 (5.0 * 15.0 = 75)
			# Exit when past the floor edge
			var exited_container = proxy_pos.z > 75.0

			if exited_container:
				# Adjust camera for 180° container rotation - subtract PI from yaw
				if is_instance_valid(dual_camera):
					dual_camera.base_rotation.y -= PI

				# Get current proxy velocity and transform to world space
				var proxy_velocity = character.get_proxy_velocity()
				var container_transform = vehicle_container_small.exterior_body.global_transform
				var world_velocity = container_transform.basis * proxy_velocity

				# With recursive nesting, proxy_pos is already in container's local coordinates
				# Just transform directly to world space
				var local_pos = proxy_pos
				var world_pos = container_transform.origin + container_transform.basis * local_pos

				character.exit_container()

				# Check if should enter vehicle that's docked inside
				if is_instance_valid(vehicle) and vehicle.is_docked:
					# Check distance from character to ship
					var vehicle_world_pos = vehicle.exterior_body.global_position
					var dist_to_ship = world_pos.distance_to(vehicle_world_pos)

					# If close to ship (within ~30 units), enter ship interior
					if dist_to_ship < 30.0:
						# Transform world pos to vehicle local space
						var vehicle_transform = vehicle.exterior_body.global_transform
						var relative_pos = world_pos - vehicle_transform.origin
						var vehicle_local_pos = vehicle_transform.basis.inverse() * relative_pos

						# Transform world velocity to vehicle local space
						var vehicle_local_velocity = vehicle_transform.basis.inverse() * world_velocity

						# Set proxy_body's space to vehicle's interior space
						PhysicsServer3D.body_set_space(character.proxy_body, vehicle.get_interior_space())

						character.enter_vehicle()
						character.set_proxy_position(vehicle_local_pos, vehicle_local_velocity)
					else:
						# Too far from ship - go to world space
						character.set_world_position(world_pos, world_velocity)
				else:
					# No docked ship - go to world space
					character.set_world_position(world_pos, world_velocity)

				container_transition_cooldown = TRANSITION_COOLDOWN_TIME

		elif character.is_in_vehicle:
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
				# Get current proxy velocity and transform to world space
				var proxy_velocity = character.get_proxy_velocity()
				var vehicle_transform = vehicle.exterior_body.global_transform
				var world_velocity = vehicle_transform.basis * proxy_velocity

				# Transform current proxy position to world position
				var world_pos = vehicle_transform.origin + vehicle_transform.basis * ship_proxy_pos

				character.exit_vehicle()

				# Check if ship is docked and player exit position is inside container bounds
				var should_enter_container = false
				var container_transform: Transform3D
				var container_proxy_pos: Vector3

				if is_instance_valid(vehicle_container_small) and vehicle.is_docked:
					# Transform world position to container local space
					container_transform = vehicle_container_small.exterior_body.global_transform
					var relative_pos = world_pos - container_transform.origin
					var local_pos = container_transform.basis.inverse() * relative_pos

					# Container is 5x ship: 90 wide (±45), 45 tall (floor -21 to ceiling +21), 150 long (±75)
					# Check if exit position is actually INSIDE the container
					var inside_container = (
						abs(local_pos.x) < 45.0 and
						local_pos.y > -21.0 and local_pos.y < 21.0 and
						local_pos.z > -75.0 and local_pos.z < 75.0
					)

					should_enter_container = inside_container
					container_proxy_pos = ship_proxy_pos  # Use ship proxy pos as container proxy pos

				if should_enter_container:
					# Exit position is inside container - enter container proxy space
					var local_velocity = container_transform.basis.inverse() * world_velocity

					# Set proxy_body's space to container's interior space
					PhysicsServer3D.body_set_space(character.proxy_body, vehicle_container_small.get_interior_space())

					character.enter_container()
					character.set_proxy_position(container_proxy_pos, local_velocity)
				else:
					# Exit position is outside container OR ship not docked - exit to world space
					# Adjust camera for 180° ship rotation - subtract PI from yaw
					if is_instance_valid(dual_camera):
						dual_camera.base_rotation.y -= PI

					character.set_world_position(world_pos, world_velocity)

				container_transition_cooldown = TRANSITION_COOLDOWN_TIME

		else:
			# Character in world space - check if entering station from outside
			var char_world_pos = character.get_world_position()
			var container_transform = vehicle_container_small.exterior_body.global_transform

			# Get relative position (vector from container to character)
			var relative_pos = char_world_pos - container_transform.origin

			# Transform relative position to container local space
			var local_pos = container_transform.basis.inverse() * relative_pos

			# Container is rotated 180° like the ship, 5x ship size
			# Container size_scale = 15.0: floor at y=-21.0, entrance at z=+75
			# Opening dimensions: X: ±45, Y: -21 to +21 (height 42 units)
			# Ship Y range: abs(y) < 4.5 (±4.5 from center, 9 units total)
			# Container Y range: ±22.5 from center (45 units total, proportional to ship)
			# Allow detection from ground level (y≈-22) to ceiling
			var at_container_entrance = (
				abs(local_pos.x) < 45.0 and
				local_pos.y > -23.0 and local_pos.y < 23.0 and  # Full opening height
				local_pos.z > 74.0 and local_pos.z < 75.0
			)

			# CRITICAL: Only trigger if player is in world space (not in vehicle or container)
			# When player is inside docked ship, they stay in vehicle interior until they walk out
			if at_container_entrance and not character.is_in_container and not character.is_in_vehicle:
				# Adjust camera for 180° container rotation
				if is_instance_valid(dual_camera):
					dual_camera.base_rotation.y += PI

				# Get current world velocity and transform to container local space
				var world_velocity = character.get_world_velocity()
				var local_velocity = container_transform.basis.inverse() * world_velocity

				# With recursive nesting, local_pos is already in container's coordinate system
				# Container's interior space uses the same coordinate system as the exterior
				# CRITICAL: Ensure player is placed AT floor level, not below it
				# Container floor is at y=-21.0, player capsule height is 1.4, so center should be at y=-20.3
				var size_scale = 3.0 * vehicle_container_small.size_multiplier
				var container_floor_y = -1.4 * size_scale  # -21.0
				var player_center_y = container_floor_y + 0.7  # Player capsule center at floor level

				var proxy_pos = Vector3(
					local_pos.x,
					max(local_pos.y, player_center_y),  # Don't spawn below floor
					local_pos.z
				)

				# Set proxy_body's space to container's interior space
				PhysicsServer3D.body_set_space(character.proxy_body, vehicle_container_small.get_interior_space())


				# Seamlessly enter - use transformed position
				character.enter_container()
				character.set_proxy_position(proxy_pos, local_velocity)
				container_transition_cooldown = TRANSITION_COOLDOWN_TIME

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
			# Small container (5x ship): 90 wide (±45), 45 tall (±22.5), 150 long (±75)
			# Large container (10x ship): 180 wide (±90), 90 tall (±45), 300 long (±150)
			var size_scale = 3.0 * container.size_multiplier
			var half_width = 3.0 * size_scale
			var half_height = 1.5 * size_scale
			var half_length = 5.0 * size_scale

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

			var vehicle_inside = (
				abs(local_pos.x) < half_width - 5.0 and
				local_pos.y > -half_height - 5.0 and local_pos.y < half_height + 5.0 and
				local_pos.z < enter_z  # Inside front boundary
			)

			var vehicle_outside = (
				abs(local_pos.x) > half_width + 5.0 or
				local_pos.y < -half_height - 10.0 or local_pos.y > half_height + 10.0 or
				local_pos.z < -half_length - 10.0 or local_pos.z > exit_z  # Exit EARLY while still inside
			)

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

# Space activation/deactivation functions removed - spaces are now always active to avoid initialization issues

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
