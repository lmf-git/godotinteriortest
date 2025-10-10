extends Node3D

## Main game manager - handles all systems and transitions

var physics_proxy: PhysicsProxy
var character: CharacterController
var vehicle: Vehicle
var vehicle_container: VehicleContainer
var dual_camera: DualCameraView

# Transition cooldowns to prevent rapid switching
var vehicle_transition_cooldown: float = 0.0
var container_transition_cooldown: float = 0.0
const TRANSITION_COOLDOWN_TIME: float = 0.5  # Half second cooldown

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

	# Create vehicle container (spawn visible, rotated to face player) - SCALED UP 1.5x
	# Container floor is at y=-20 relative to center, so y=20 puts floor at ground level
	vehicle_container = VehicleContainer.new()
	vehicle_container.physics_proxy = physics_proxy
	vehicle_container.position = Vector3(0, 30, 250)  # Much further ahead
	vehicle_container.scale = Vector3(1.5, 1.5, 1.5)  # Scale up 1.5x
	vehicle_container.rotation_degrees = Vector3(0, 180, 0)  # Rotate 180° so opening faces player
	add_child(vehicle_container)

	# Create dual camera system (it will be current automatically)
	dual_camera = DualCameraView.new()
	dual_camera.character = character
	dual_camera.vehicle = vehicle
	dual_camera.vehicle_container = vehicle_container
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
  Space - Jump
  Mouse - Look around

SHIP CONTROLS (when inside ship):
  T - Forward    | R - Raise
  F - Left       | Y - Lower
  G - Backward   |
  H - Right      |
  Arrow Keys - Pitch/Yaw
  Q/E - Roll
  B - Toggle Docking Magnetism

DOCKING STATION CONTROLS:
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
	debug_label.position = Vector2(10, viewport_size.y - 150)

	# Update debug text
	var space_name = character.current_space
	var world_pos = character.get_world_position()
	var proxy_pos = character.get_proxy_position()

	# Check if vehicle is docked
	var vehicle_docked = false
	if is_instance_valid(vehicle) and is_instance_valid(vehicle_container):
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

	# Vehicle controls (always available)
	if is_instance_valid(vehicle):
		_handle_vehicle_controls()

	# Container controls (always available)
	if is_instance_valid(vehicle_container):
		_handle_container_controls()

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

func _handle_container_controls() -> void:
	# Get container basis for directional movement
	var container_basis = vehicle_container.exterior_body.global_transform.basis

	# Container DIRECTIONAL controls (IJKL)
	if Input.is_key_pressed(KEY_I):
		# Forward (negative Z in container's local space)
		var forward = -container_basis.z
		vehicle_container.apply_thrust(forward, 10000.0)

	if Input.is_key_pressed(KEY_K):
		# Backward (positive Z in container's local space)
		var backward = container_basis.z
		vehicle_container.apply_thrust(backward, 10000.0)

	if Input.is_key_pressed(KEY_J):
		# Left (negative X in container's local space)
		var left = -container_basis.x
		vehicle_container.apply_thrust(left, 10000.0)

	if Input.is_key_pressed(KEY_L):
		# Right (positive X in container's local space)
		var right = container_basis.x
		vehicle_container.apply_thrust(right, 10000.0)

	# Container VERTICAL controls (U/P)
	if Input.is_key_pressed(KEY_U):
		# Raise (positive Y in container's local space)
		var up = container_basis.y
		vehicle_container.apply_thrust(up, 10000.0)

	if Input.is_key_pressed(KEY_P):
		# Lower (negative Y in container's local space)
		var down = -container_basis.y
		vehicle_container.apply_thrust(down, 10000.0)

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

				# Check if ship is docked in container - if so, enter container instead of world
				if is_instance_valid(vehicle_container) and vehicle.is_docked:
					# Don't adjust camera - we're staying in proxy space (ship -> container)

					# Transform world position to container local space
					var container_transform = vehicle_container.exterior_body.global_transform
					var relative_pos = world_pos - container_transform.origin
					var local_pos = container_transform.basis.inverse() * relative_pos

					# Divide by scale to get unscaled local coordinates
					local_pos = local_pos / vehicle_container.scale.x

					# Transform velocity to container local space
					var local_velocity = container_transform.basis.inverse() * world_velocity

					# Convert to container proxy coordinates (no Y offset needed - floors match)
					var container_proxy_pos = local_pos

					character.enter_container()
					character.set_proxy_position(container_proxy_pos, local_velocity)
				else:
					# Not docked - exit to world space
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

				# Seamlessly enter - use exact transformed position (no clamping)
				# This matches the exit behavior which is perfectly seamless
				character.enter_vehicle()
				character.set_proxy_position(local_pos, local_velocity)
				vehicle_transition_cooldown = TRANSITION_COOLDOWN_TIME

	if not is_instance_valid(vehicle_container):
		return

	# Check container transition zone - seamless entry/exit
	if vehicle_container.transition_zone and container_transition_cooldown <= 0:
		if character.is_in_container:
			# Check if character walked outside container proxy bounds
			var proxy_pos = character.get_proxy_position()

			# Container proxy floor extends from z=-40 to z=+35
			# Exit when past the floor edge
			var exited_container = proxy_pos.z > 35.0

			# Debug logging
			print("[STATION EXIT] Proxy pos: ", proxy_pos, " | Exited: ", exited_container)

			if exited_container:
				print("[STATION EXIT] Exiting container!")

				# Adjust camera for 180° container rotation - subtract PI from yaw
				if is_instance_valid(dual_camera):
					dual_camera.base_rotation.y -= PI

				# Get current proxy velocity and transform to world space
				var proxy_velocity = character.get_proxy_velocity()
				var container_transform = vehicle_container.exterior_body.global_transform
				var world_velocity = container_transform.basis * proxy_velocity

				# Convert from proxy coordinates to container local coordinates
				# Container proxy floor is at y=-20, exterior floor is at y=-20
				# No Y offset needed - they match!
				var local_pos = proxy_pos

				# Transform local position to world position
				var world_pos = container_transform.origin + container_transform.basis * local_pos

				character.exit_container()

				# Check if should enter vehicle that's docked inside
				if is_instance_valid(vehicle) and vehicle.is_docked:
					# Check distance from character to ship
					var vehicle_world_pos = vehicle.exterior_body.global_position
					var dist_to_ship = world_pos.distance_to(vehicle_world_pos)

					print("[STATION EXIT] Docked ship detected. Distance: ", dist_to_ship)

					# If close to ship (within ~30 units), enter ship interior
					if dist_to_ship < 30.0:
						print("[STATION EXIT] Entering docked ship!")

						# Transform world pos to vehicle local space
						var vehicle_transform = vehicle.exterior_body.global_transform
						var relative_pos = world_pos - vehicle_transform.origin
						var vehicle_local_pos = vehicle_transform.basis.inverse() * relative_pos

						# Transform world velocity to vehicle local space
						var vehicle_local_velocity = vehicle_transform.basis.inverse() * world_velocity

						print("[STATION->SHIP] Ship local pos: ", vehicle_local_pos)

						character.enter_vehicle()
						character.set_proxy_position(vehicle_local_pos, vehicle_local_velocity)
					else:
						# Too far from ship - go to world space
						print("[STATION EXIT] Too far from ship, going to world")
						character.set_world_position(world_pos, world_velocity)
				else:
					# No docked ship - go to world space
					print("[STATION EXIT] No docked ship, going to world")
					character.set_world_position(world_pos, world_velocity)

				container_transition_cooldown = TRANSITION_COOLDOWN_TIME

		elif character.is_in_vehicle:
			# Check if character (in ship interior) entered station/container zone
			# This happens when ship is docked and player walks from ship into station
			# Character world position comes from vehicle transform + proxy position
			var char_world_pos = character.character_visual.global_position
			var container_transform = vehicle_container.exterior_body.global_transform

			# Get relative position (vector from container to character)
			var relative_pos = char_world_pos - container_transform.origin

			# Transform relative position to container local space
			var local_pos = container_transform.basis.inverse() * relative_pos

			# Divide by scale to get unscaled local coordinates
			local_pos = local_pos / vehicle_container.scale.x

			# Get ship proxy position for debugging
			var ship_proxy_pos = character.get_proxy_position()

			# Check if player walked OUT of the ship's front opening
			# Ship interior extends from z=-15 to z=+15
			# Only transition when player walks PAST the ship's front edge
			var exited_ship_front = ship_proxy_pos.z > 15.0

			# Also check we're still inside the container (not outside)
			var inside_container_bounds = (
				abs(local_pos.x) < 31.0 and  # Floor width is ±30 units
				abs(local_pos.y) < 22.0 and  # Floor (-20) to ceiling (+20)
				local_pos.z > -35.0 and local_pos.z < 40.0  # Inside container
			)

			# Debug logging
			if is_instance_valid(vehicle) and vehicle.is_docked:
				print("[SHIP->STATION] Ship proxy pos: ", ship_proxy_pos,
					  " | Container local pos: ", local_pos,
					  " | Exited ship front: ", exited_ship_front,
					  " | Inside container: ", inside_container_bounds)

			# Only transition if ship is docked AND player walked out the ship front AND still inside container
			if exited_ship_front and inside_container_bounds and is_instance_valid(vehicle) and vehicle.is_docked:
				print("[SHIP->STATION] Transitioning to station!")

				# Get current proxy velocity (transform from ship proxy to container proxy)
				var proxy_velocity = character.get_proxy_velocity()

				# Transform velocity from vehicle local space to container local space
				var vehicle_transform = vehicle.exterior_body.global_transform
				var world_velocity = vehicle_transform.basis * proxy_velocity
				var local_velocity = container_transform.basis.inverse() * world_velocity

				# Convert from container local coordinates to proxy coordinates
				# Container exterior floor is at y=-20, proxy floor is at y=-20
				# No Y offset needed - they match!
				var proxy_pos = local_pos

				print("[SHIP->STATION] Setting station proxy pos: ", proxy_pos)

				character.exit_vehicle()  # Leave ship
				character.enter_container()  # Enter station
				character.set_proxy_position(proxy_pos, local_velocity)
				container_transition_cooldown = TRANSITION_COOLDOWN_TIME

		else:
			# Character in world space - check if entering station from outside
			var char_world_pos = character.get_world_position()
			var container_transform = vehicle_container.exterior_body.global_transform

			# Get relative position (vector from container to character)
			var relative_pos = char_world_pos - container_transform.origin

			# Transform relative position to container local space
			# Note: Container is scaled 1.5x, so we need to account for that
			var local_pos = container_transform.basis.inverse() * relative_pos
			# Divide by scale to get actual local coordinates
			local_pos = local_pos / vehicle_container.scale.x

			# Container is rotated 180° like the ship
			# Opening dimensions (unscaled): X: ±30, Y: -20 to +20, Z: at 40
			# Account for player approaching from ground level (y around -18 to -20 in local space)
			# Detect entrance while approaching floor edge (still within floor bounds)
			var at_container_entrance = (
				abs(local_pos.x) < 31.0 and  # Floor width is ±30 units
				local_pos.y > -22.0 and local_pos.y < 22.0 and  # Opening from floor (-20) to ceiling (+20)
				local_pos.z > 30.0 and local_pos.z < 35.0  # Approaching floor edge from outside
			)

			if at_container_entrance and not character.is_in_container:
				# Adjust camera for 180° container rotation
				if is_instance_valid(dual_camera):
					dual_camera.base_rotation.y += PI

				# Get current world velocity and transform to container local space
				var world_velocity = character.get_world_velocity()
				var local_velocity = container_transform.basis.inverse() * world_velocity

				# Convert from container local coordinates to proxy coordinates
				# Container exterior floor is at y=-20, proxy floor is at y=-20
				# No Y offset needed - they match!
				var proxy_pos = local_pos

				# Seamlessly enter - use transformed position
				character.enter_container()
				character.set_proxy_position(proxy_pos, local_velocity)
				container_transition_cooldown = TRANSITION_COOLDOWN_TIME

	# Check vehicle docking - use local space coordinates like player detection
	if is_instance_valid(vehicle) and vehicle.exterior_body and is_instance_valid(vehicle_container) and vehicle_container.exterior_body:
		var vehicle_world_pos = vehicle.exterior_body.global_position
		var container_transform = vehicle_container.exterior_body.global_transform

		# Transform vehicle position to container local space
		var relative_pos = vehicle_world_pos - container_transform.origin
		var local_pos = container_transform.basis.inverse() * relative_pos

		# Divide by scale to get unscaled local coordinates
		local_pos = local_pos / vehicle_container.scale.x

		# Docking zone (unscaled): centered at (0, 0, 0), with generous bounds
		# Container interior is 60 wide (±30), 40 tall (±20), 80 long (±40)
		# Opening is at z=+40, so dock zone is near center with some depth
		var vehicle_in_dock_zone = (
			abs(local_pos.x) < 25.0 and  # Narrower than container (±30)
			abs(local_pos.y) < 15.0 and  # Centered vertically
			local_pos.z > -30.0 and local_pos.z < 30.0  # Deep inside container
		)

		if vehicle_in_dock_zone and not vehicle.is_docked:
			# Vehicle entering dock
			print("[DOCKING] Vehicle entered dock zone at local pos: ", local_pos)
			vehicle.set_docked(true)
		elif not vehicle_in_dock_zone and vehicle.is_docked:
			# Vehicle leaving dock
			print("[DOCKING] Vehicle left dock zone at local pos: ", local_pos)
			vehicle.set_docked(false)
