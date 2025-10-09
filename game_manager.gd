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

	# Debug markers removed - no longer needed

	# Create physics proxy
	print("Creating physics proxy...")
	physics_proxy = PhysicsProxy.new()
	add_child(physics_proxy)
	print("Physics proxy added to tree")

	# Wait for physics proxy to initialize (it needs 2 frames)
	print("Waiting for physics proxy to initialize...")
	await get_tree().process_frame
	await get_tree().process_frame
	print("Physics proxy ready!")

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

	print("FPS camera active")

	# Create stars
	_create_stars()

	# Debug print positions
	print("=== Scene Setup ===")
	print("Character position: ", character.global_position)
	print("Vehicle position: ", vehicle.global_position)
	print("Container position: ", vehicle_container.global_position)
	print("Ground plane created at y=0")
	print("Character is_in_vehicle: ", character.is_in_vehicle)
	print("===================")

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

	print("Ground plane created: 10000x10000")

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

func _create_debug_markers() -> void:
	# Create bright markers at key positions for debugging visibility
	var markers = [
		{"pos": Vector3(0, 1, 0), "color": Color(1, 0, 0), "name": "Origin"},
		{"pos": Vector3(0, 1, -10), "color": Color(0, 1, 0), "name": "CharSpawn"},
		{"pos": Vector3(10, 1, 0), "color": Color(0, 0, 1), "name": "Side"},
		{"pos": Vector3(0, 1, 10), "color": Color(1, 1, 0), "name": "Behind"},
	]

	for marker in markers:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = marker["name"] + "Marker"
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		mesh_instance.mesh = sphere

		var mat := StandardMaterial3D.new()
		mat.albedo_color = marker["color"]
		mat.emission_enabled = true
		mat.emission = marker["color"]
		mat.emission_energy_multiplier = 2.0
		mesh_instance.material_override = mat

		mesh_instance.position = marker["pos"]
		add_child(mesh_instance)
		print("Created marker: ", marker["name"], " at ", marker["pos"])

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

	debug_label.text = """=== DEBUG INFO ===
Current Space: %s
In Vehicle: %s
In Container: %s
World Pos: (%.1f, %.1f, %.1f)
Proxy Pos: (%.1f, %.1f, %.1f)
""" % [
		space_name,
		"YES" if character.is_in_vehicle else "NO",
		"YES" if character.is_in_container else "NO",
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

			# Proxy floor extends from z=-14.7 to z=+14.7 (4.9 * 3 = 14.7)
			# Exit trigger with margin before the edge for safe exit
			# Exit when approaching the front (z > 14.5)
			var exited_front = proxy_pos.z > 14.5  # 0.2 unit margin before entrance zone at 14.7

			if exited_front:
				print("Exiting vehicle seamlessly - proxy pos: ", proxy_pos)
				# Adjust camera for 180° ship rotation - subtract PI from yaw
				if is_instance_valid(dual_camera):
					dual_camera.base_rotation.y -= PI

				# Transform current proxy position to world position for seamless exit
				var vehicle_transform = vehicle.exterior_body.global_transform
				var world_pos = vehicle_transform.origin + vehicle_transform.basis * proxy_pos

				character.exit_vehicle()
				character.set_world_position(world_pos)
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
			# Entrance zone is the narrow gap between proxy floor and exterior
			var at_entrance = (
				abs(local_pos.x) < 9.0 and
				abs(local_pos.y) < 4.5 and
				local_pos.z > 14.7 and local_pos.z < 15.0  # Narrow 0.3 unit gap
			)

			if at_entrance and not character.is_in_container:
				print("Entering vehicle seamlessly - world: ", char_world_pos, " local: ", local_pos)
				# Adjust camera for 180° ship rotation - add PI to yaw
				if is_instance_valid(dual_camera):
					dual_camera.base_rotation.y += PI

				# Seamlessly enter - spawn safely inside, away from exit trigger
				# Exit trigger is at z > 14.5, so clamp to 14.4 maximum (0.1 unit margin)
				var safe_local_pos = Vector3(local_pos.x, local_pos.y, min(local_pos.z, 14.4))
				character.enter_vehicle()
				character.set_proxy_position(safe_local_pos)
				vehicle_transition_cooldown = TRANSITION_COOLDOWN_TIME

	if not is_instance_valid(vehicle_container):
		return

	# Check container transition zone - seamless entry/exit
	if vehicle_container.transition_zone and container_transition_cooldown <= 0:
		if character.is_in_container:
			# Check if character walked outside container proxy bounds
			var proxy_pos = character.get_proxy_position()

			# Container proxy floor extends from z=-35 to z=+35
			# Exit when walked PAST the front edge of proxy floor
			var exited_container = proxy_pos.z > 35.0  # Beyond the front edge of proxy floor

			if exited_container:
				print("Exiting container (station) seamlessly - proxy pos: ", proxy_pos)
				# Don't adjust camera - let it naturally transition

				# Transform proxy position to world position
				var container_transform = vehicle_container.exterior_body.global_transform
				var world_pos = container_transform.origin + container_transform.basis * proxy_pos

				character.exit_container()

				# Check if should enter vehicle that's docked inside
				if is_instance_valid(vehicle) and vehicle.is_docked:
					# Check distance from character to ship
					var vehicle_world_pos = vehicle.exterior_body.global_position
					var dist_to_ship = world_pos.distance_to(vehicle_world_pos)

					print("Distance to docked ship: ", dist_to_ship)

					# If close to ship (within ~30 units), enter ship interior
					if dist_to_ship < 30.0:
						print("Entering ship interior from station")
						# Transform world pos to vehicle local space
						var vehicle_transform = vehicle.exterior_body.global_transform
						var relative_pos = world_pos - vehicle_transform.origin
						var vehicle_local_pos = vehicle_transform.basis.inverse() * relative_pos

						character.enter_vehicle()
						character.set_proxy_position(vehicle_local_pos)
					else:
						# Too far from ship - go to world space
						print("Exiting to world space")
						character.set_world_position(world_pos)
				else:
					# No docked ship - go to world space
					print("Exiting to world space (no ship docked)")
					character.set_world_position(world_pos)

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

			# Container entrance at z=40, entrance zone from z=42 to z=50 (outside container)
			# But when in ship, check if we're INSIDE the station bounds
			var inside_station_bounds = (
				abs(local_pos.x) < 25.0 and
				abs(local_pos.y) < 15.0 and
				local_pos.z > -35.0 and local_pos.z < 40.0
			)

			# Only transition if ship is docked and character is inside station
			if inside_station_bounds and is_instance_valid(vehicle) and vehicle.is_docked:
				print("Entering station from ship interior - local pos: ", local_pos)
				character.exit_vehicle()  # Leave ship
				character.enter_container()  # Enter station
				character.set_proxy_position(local_pos)
				container_transition_cooldown = TRANSITION_COOLDOWN_TIME

		else:
			# Character in world space - check if entering station from outside
			var char_world_pos = character.get_world_position()
			var container_transform = vehicle_container.exterior_body.global_transform

			# Get relative position (vector from container to character)
			var relative_pos = char_world_pos - container_transform.origin

			# Transform relative position to container local space
			var local_pos = container_transform.basis.inverse() * relative_pos

			# Container entrance at z=40 (exterior front wall), entrance zone OUTSIDE
			var at_container_entrance = (
				abs(local_pos.x) < 15.0 and
				abs(local_pos.y) < 12.5 and
				local_pos.z > 35.0 and local_pos.z < 42.0  # Narrow zone outside container
			)

			if at_container_entrance:
				print("Entering container from world space - world: ", char_world_pos, " local: ", local_pos)
				# Place player JUST INSIDE the container to avoid immediate exit
				# Clamp Z to be inside the valid proxy bounds (< 35.0)
				var safe_local_pos = Vector3(local_pos.x, local_pos.y, min(local_pos.z, 34.5))
				character.enter_container()
				character.set_proxy_position(safe_local_pos)
				container_transition_cooldown = TRANSITION_COOLDOWN_TIME

	# Check vehicle docking
	if is_instance_valid(vehicle) and vehicle.exterior_body and is_instance_valid(vehicle_container) and vehicle_container.transition_zone:
		var vehicle_pos = vehicle.exterior_body.global_position
		var zone_pos = vehicle_container.transition_zone.global_position

		var vehicle_in_dock_zone = (
			abs(vehicle_pos.x - zone_pos.x) < 20 and
			abs(vehicle_pos.y - zone_pos.y) < 15 and
			abs(vehicle_pos.z - zone_pos.z) < 10
		)

		if vehicle_in_dock_zone and not vehicle.is_docked:
			# Vehicle entering dock
			print("Vehicle entering dock")
			vehicle.set_docked(true)
			# TODO: Transfer vehicle state to dock proxy
		elif not vehicle_in_dock_zone and vehicle.is_docked:
			# Vehicle leaving dock
			print("Vehicle leaving dock")
			vehicle.set_docked(false)
			# TODO: Transfer vehicle state back to world
