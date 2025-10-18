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
	ground_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

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

	# 1. KEY LIGHT - Main light source (brightest, casts shadows)
	var key_light := DirectionalLight3D.new()
	key_light.name = "KeyLight"
	key_light.light_energy = 3.0  # Much brighter
	key_light.light_color = Color(1.0, 1.0, 1.0)  # Pure white
	key_light.rotation_degrees = Vector3(-45, -30, 0)
	key_light.shadow_enabled = true
	key_light.shadow_bias = 0.05
	key_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(key_light)

	# 2. FILL LIGHT - Softens shadows from key light
	var fill_light := DirectionalLight3D.new()
	fill_light.name = "FillLight"
	fill_light.light_energy = 2.0  # Much brighter
	fill_light.light_color = Color(0.9, 0.95, 1.0)  # Slightly cool
	fill_light.rotation_degrees = Vector3(-30, 150, 0)
	fill_light.shadow_enabled = false
	add_child(fill_light)

	# 3. RIM/BACK LIGHT - Creates separation from background
	var rim_light := DirectionalLight3D.new()
	rim_light.name = "RimLight"
	rim_light.light_energy = 1.5  # Brighter
	rim_light.light_color = Color(1.0, 1.0, 1.0)
	rim_light.rotation_degrees = Vector3(-20, 180, 0)
	rim_light.shadow_enabled = false
	add_child(rim_light)

	# AMBIENT - Overall base illumination - MUCH BRIGHTER
	var ambient_env := Environment.new()
	ambient_env.background_mode = Environment.BG_SKY
	ambient_env.sky = Sky.new()
	ambient_env.sky.sky_material = ProceduralSkyMaterial.new()
	ambient_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	ambient_env.ambient_light_energy = 1.5  # Much higher
	ambient_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR  # No tone mapping
	ambient_env.adjustment_enabled = true
	ambient_env.adjustment_brightness = 1.3  # Boost overall brightness

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
	for i in range(1000):
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

SMALL DOCKING STATION CONTROLS:
  I - Forward    | U - Raise
  J - Left       | P - Lower
  K - Backward   |
  L - Right      |

LARGE DOCKING STATION CONTROLS:
  Numpad 8 - Forward    | Numpad 7 - Raise
  Numpad 4 - Left       | Numpad 9 - Lower
  Numpad 5 - Backward   |
  Numpad 6 - Right      |
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

	debug_label.text = """=== DEBUG INFO ===
Current Space: %s
In Vehicle: %s
In Container: %s
Vehicle Docked: %s
World Pos: (%.1f, %.1f, %.1f)
Proxy Pos: (%.1f, %.1f, %.1f)
""" % [
		space_name,
		"YES" if character.is_in_vehicle else "NO",
		"YES" if character.is_in_container else "NO",
		"YES" if vehicle_docked else "NO",
		world_pos.x, world_pos.y, world_pos.z,
		proxy_pos.x, proxy_pos.y, proxy_pos.z
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

	# Vehicle controls (always available)
	if is_instance_valid(vehicle):
		_handle_vehicle_controls()

	# Container controls (always available)
	if is_instance_valid(vehicle_container_small):
		_handle_container_controls_small()
	if is_instance_valid(vehicle_container_large):
		_handle_container_controls_large()

func _handle_vehicle_controls() -> void:
	# Get vehicle basis for directional movement
	var vehicle_basis = vehicle.exterior_body.global_transform.basis

	# Vehicle DIRECTIONAL controls (TFGH)
	if Input.is_key_pressed(KEY_T):
		# Forward (negative Z in vehicle's local space)
		var forward = -vehicle_basis.z
		vehicle.apply_thrust(forward, 15000.0)

	if Input.is_key_pressed(KEY_G):
		# Backward (positive Z in vehicle's local space)
		var backward = vehicle_basis.z
		vehicle.apply_thrust(backward, 15000.0)

	if Input.is_key_pressed(KEY_F):
		# Left (negative X in vehicle's local space)
		var left = -vehicle_basis.x
		vehicle.apply_thrust(left, 15000.0)

	if Input.is_key_pressed(KEY_H):
		# Right (positive X in vehicle's local space)
		var right = vehicle_basis.x
		vehicle.apply_thrust(right, 15000.0)

	# Vehicle VERTICAL controls (R/Y)
	if Input.is_key_pressed(KEY_R):
		# Raise (positive Y in vehicle's local space)
		var up = vehicle_basis.y
		vehicle.apply_thrust(up, 15000.0)

	if Input.is_key_pressed(KEY_Y):
		# Lower (negative Y in vehicle's local space)
		var down = -vehicle_basis.y
		vehicle.apply_thrust(down, 15000.0)

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

func _handle_container_controls_small() -> void:
	# Get container basis for directional movement
	var container_basis = vehicle_container_small.exterior_body.global_transform.basis

	# Container DIRECTIONAL controls (IJKL)
	if Input.is_key_pressed(KEY_I):
		# Forward (negative Z in container's local space)
		var forward = -container_basis.z
		vehicle_container_small.apply_thrust(forward, 10000.0)

	if Input.is_key_pressed(KEY_K):
		# Backward (positive Z in container's local space)
		var backward = container_basis.z
		vehicle_container_small.apply_thrust(backward, 10000.0)

	if Input.is_key_pressed(KEY_J):
		# Left (negative X in container's local space)
		var left = -container_basis.x
		vehicle_container_small.apply_thrust(left, 10000.0)

	if Input.is_key_pressed(KEY_L):
		# Right (positive X in container's local space)
		var right = container_basis.x
		vehicle_container_small.apply_thrust(right, 10000.0)

	# Container VERTICAL controls (U/P)
	if Input.is_key_pressed(KEY_U):
		# Raise (positive Y in container's local space)
		var up = container_basis.y
		vehicle_container_small.apply_thrust(up, 10000.0)

	if Input.is_key_pressed(KEY_P):
		# Lower (negative Y in container's local space)
		var down = -container_basis.y
		vehicle_container_small.apply_thrust(down, 10000.0)

func _handle_container_controls_large() -> void:
	# Get container basis for directional movement
	var container_basis = vehicle_container_large.exterior_body.global_transform.basis

	# Container DIRECTIONAL controls (Numpad 8/5/4/6)
	if Input.is_key_pressed(KEY_KP_8):
		# Forward
		var forward = -container_basis.z
		vehicle_container_large.apply_thrust(forward, 20000.0)

	if Input.is_key_pressed(KEY_KP_5):
		# Backward
		var backward = container_basis.z
		vehicle_container_large.apply_thrust(backward, 20000.0)

	if Input.is_key_pressed(KEY_KP_4):
		# Left
		var left = -container_basis.x
		vehicle_container_large.apply_thrust(left, 20000.0)

	if Input.is_key_pressed(KEY_KP_6):
		# Right
		var right = container_basis.x
		vehicle_container_large.apply_thrust(right, 20000.0)

	# Container VERTICAL controls (Numpad 7/9)
	if Input.is_key_pressed(KEY_KP_7):
		# Raise
		var up = container_basis.y
		vehicle_container_large.apply_thrust(up, 20000.0)

	if Input.is_key_pressed(KEY_KP_9):
		# Lower
		var down = -container_basis.y
		vehicle_container_large.apply_thrust(down, 20000.0)

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
				var container_transform: Transform3D  # Declare outside if block so it's in scope for later use

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

				if should_enter_container:
					# Exit position is inside container - enter container proxy space
					# Don't adjust camera - we're staying in proxy space (ship -> container)
					var local_velocity = container_transform.basis.inverse() * world_velocity

					# CRITICAL: With recursive nesting, ship and container have separate interior spaces
					# Need to transfer player from ship's space to container's space
					# Player position is already in ship's local coordinates (relative to ship center)
					# Just use the same relative position in container's space
					var container_proxy_pos = proxy_pos

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

			# Only transition if ship is docked AND player walked out the ship front
			if exited_ship_front and is_instance_valid(vehicle) and vehicle.is_docked:
				# Get current proxy velocity (velocity stays the same in proxy space)
				var proxy_velocity = character.get_proxy_velocity()

				# CRITICAL: When ship is docked, both ship and station share proxy_interior_space
				# Ship's dock_proxy_body moves around, and floor moves with it
				# Need to calculate where ship floor actually is based on dock_proxy_body position

				# Get ship's dock_proxy_body position
				# With recursive nesting, each space has its own coordinates
				# Player position in ship's interior space is relative to ship center
				# Just use the same relative position in container's space
				var container_proxy_pos = ship_proxy_pos

				print("[TRANSITION] Player exiting ship to container")
				print("  Ship proxy pos: ", ship_proxy_pos)
				print("  Container proxy pos: ", container_proxy_pos)

				# Set proxy_body's space to container's interior space
				PhysicsServer3D.body_set_space(character.proxy_body, vehicle_container_small.get_interior_space())

				character.exit_vehicle()  # Leave ship
				character.enter_container()  # Enter container
				character.set_proxy_position(container_proxy_pos, proxy_velocity)
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
			# Container size_scale = 15.0: floor at y=-21, entrance at z=+75
			# Opening dimensions: X: ±45, Y: -21 to +21
			# Detect entrance ONLY when player is actually on the floor, not at the edge
			# Container proxy floor extends from z=-75 to z=+75 in proxy space
			# Pull back detection to z=70 so player has stepped onto floor before transition
			var at_container_entrance = (
				abs(local_pos.x) < 45.0 and
				local_pos.y > -23.0 and local_pos.y < 23.0 and
				local_pos.z > 65.0 and local_pos.z < 70.0  # Only detect when well inside, not at edge
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
				var proxy_pos = local_pos

				print("[TRANSITION] Player entering container from world")
				print("  Container local pos: ", local_pos)
				print("  Proxy pos: ", proxy_pos)

				# Set proxy_body's space to container's interior space
				PhysicsServer3D.body_set_space(character.proxy_body, vehicle_container_small.get_interior_space())

				# Seamlessly enter - use transformed position
				character.enter_container()
				character.set_proxy_position(proxy_pos, local_velocity)
				container_transition_cooldown = TRANSITION_COOLDOWN_TIME

	# Check vehicle docking - use local space coordinates like player detection
	if is_instance_valid(vehicle) and vehicle.exterior_body and is_instance_valid(vehicle_container_small) and vehicle_container_small.exterior_body:
		# ALWAYS use exterior_body position transformed to container local space
		# This avoids issues with dock_proxy_body being reset when undocking
		var vehicle_world_pos = vehicle.exterior_body.global_position
		var container_transform = vehicle_container_small.exterior_body.global_transform
		var relative_pos = vehicle_world_pos - container_transform.origin
		var local_pos = container_transform.basis.inverse() * relative_pos

		# Docking zone: ship must be well inside before docking triggers
		# Container is 5x ship: 90 wide (±45), 45 tall (±22.5), 150 long (±75)
		# Dock floor at Y=-21, ship half-height 1.5, so ship center at ~-19.5 when on floor
		# Opening is at z=+75, pull back detection similar to player entrance
		# Ship length is 30 units, so requiring z < 55 ensures ship is mostly inside
		var vehicle_in_dock_zone = (
			abs(local_pos.x) < 30.0 and  # Narrower than container (±45)
			local_pos.y > -22.5 and local_pos.y < 22.5 and  # Tall enough for ship on floor (full container height)
			local_pos.z > -60.0 and local_pos.z < 55.0  # Well inside container, not at entrance edge
		)

		if vehicle_in_dock_zone and not vehicle.is_docked:
			# Vehicle entering dock
			_debounced_log("DOCKING", "Vehicle entered dock zone", {
				"x": local_pos.x,
				"y": local_pos.y,
				"z": local_pos.z
			})
			vehicle.set_docked(true)
		elif not vehicle_in_dock_zone and vehicle.is_docked:
			# Vehicle leaving dock
			_debounced_log("DOCKING", "Vehicle left dock zone", {
				"x": local_pos.x,
				"y": local_pos.y,
				"z": local_pos.z
			})
			vehicle.set_docked(false)

	# Check container-in-container docking (small container docking in large container)
	if is_instance_valid(vehicle_container_small) and vehicle_container_small.exterior_body and is_instance_valid(vehicle_container_large) and vehicle_container_large.exterior_body:
		# Transform small container's world position to large container's local space
		var small_world_pos = vehicle_container_small.exterior_body.global_position
		var large_transform = vehicle_container_large.exterior_body.global_transform
		var relative_pos = small_world_pos - large_transform.origin
		var local_pos = large_transform.basis.inverse() * relative_pos

		# Docking zone: small container must be well inside large container
		# Large container is 10x ship: 180 wide (±90), 90 tall (±45), 300 long (±150)
		# Small container is 5x ship: 90 wide (±45), 45 tall (±22.5), 150 long (±75)
		# Opening is at z=+150 for large container
		var small_in_large_dock_zone = (
			abs(local_pos.x) < 60.0 and  # Narrower than large container
			local_pos.y > -45.0 and local_pos.y < 45.0 and  # Full height of large container
			local_pos.z > -120.0 and local_pos.z < 110.0  # Well inside, not at entrance edge
		)

		if small_in_large_dock_zone and not vehicle_container_small.is_docked:
			# Small container entering large container dock
			print("[CONTAINER DOCKING] Small container entered large container dock zone")
			vehicle_container_small.set_docked(true, vehicle_container_large)
		elif not small_in_large_dock_zone and vehicle_container_small.is_docked:
			# Small container leaving large container dock
			print("[CONTAINER DOCKING] Small container left large container dock zone")
			vehicle_container_small.set_docked(false, vehicle_container_large)
