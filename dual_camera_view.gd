class_name DualCameraView
extends Node

## Triple camera system showing FPS view, exterior view, and docking station interior view

@export var character: CharacterController
@export var vehicle: Vehicle
@export var vehicle_container: VehicleContainer

# Main FPS camera (interior/proxy view)
var main_camera: Camera3D

# External/God view camera (world space view)
var external_camera: Camera3D

# Docking station interior camera (fixed view inside container)
var dock_interior_camera: Camera3D

# Viewports
var external_viewport: SubViewport
var dock_interior_viewport: SubViewport

# Display
var external_rect: TextureRect
var dock_interior_rect: TextureRect
var external_panel: Panel  # Store reference to show/hide
var dock_panel: Panel  # Store reference to show/hide

var mouse_sensitivity: float = 0.002
var base_rotation: Vector3 = Vector3.ZERO  # Yaw and pitch from mouse input
var target_up_vector: Vector3 = Vector3.UP  # Target up direction for smooth gravity transitions
var current_up_vector: Vector3 = Vector3.UP  # Current interpolated up direction
var up_transition_speed: float = 5.0  # How fast to transition up direction
var is_transitioning_up: bool = false  # True during space transitions, false otherwise
var third_person_mode: bool = false
var third_person_distance: float = 10.0

func _ready() -> void:
	_setup_viewports()
	_setup_cameras()
	_setup_display()

	# Capture mouse for FPS controls
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Force update viewport sizes after everything is ready
	await get_tree().process_frame

	# Set viewports to wireframe mode (needs to be after process_frame)
	external_viewport.debug_draw = Viewport.DEBUG_DRAW_WIREFRAME
	dock_interior_viewport.debug_draw = Viewport.DEBUG_DRAW_WIREFRAME

	_update_viewport_sizes()

func _setup_viewports() -> void:
	# External viewport (ship interior proxy space) - picture-in-picture bottom right
	external_viewport = SubViewport.new()
	external_viewport.size = Vector2i(640, 360)
	external_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	external_viewport.transparent_bg = false

	# Create SEPARATE World3D for ship interior proxy space
	var ship_proxy_world = World3D.new()

	# Create environment for ship proxy world
	var ship_env = Environment.new()
	ship_env.background_mode = Environment.BG_COLOR
	ship_env.background_color = Color(0.1, 0.1, 0.1)
	ship_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	ship_env.ambient_light_color = Color(1, 1, 1)
	ship_env.ambient_light_energy = 1.0
	ship_proxy_world.environment = ship_env

	external_viewport.world_3d = ship_proxy_world

	# Create visual geometry for ship interior proxy space
	_create_proxy_interior_scene(external_viewport)

	add_child(external_viewport)

	# Dock interior viewport (station interior proxy space) - picture-in-picture top right
	dock_interior_viewport = SubViewport.new()
	dock_interior_viewport.size = Vector2i(640, 360)
	dock_interior_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	dock_interior_viewport.transparent_bg = false

	# Create SEPARATE World3D for station interior proxy space
	var station_proxy_world = World3D.new()

	# Create environment for station proxy world
	var station_env = Environment.new()
	station_env.background_mode = Environment.BG_COLOR
	station_env.background_color = Color(0.1, 0.1, 0.1)
	station_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	station_env.ambient_light_color = Color(1, 1, 1)
	station_env.ambient_light_energy = 1.0
	station_proxy_world.environment = station_env

	dock_interior_viewport.world_3d = station_proxy_world

	# Create visual geometry for station interior in proxy space
	_create_station_proxy_interior_scene(dock_interior_viewport)

	add_child(dock_interior_viewport)

func _create_proxy_interior_scene(viewport: SubViewport) -> void:
	# Create visual geometry for ship interior in proxy space
	# This matches the proxy colliders and is what the PIP camera sees

	var size_scale = 3.0

	# Create container for proxy visuals
	var proxy_interior_visuals = Node3D.new()
	proxy_interior_visuals.name = "ShipProxyInteriorVisuals"
	viewport.add_child(proxy_interior_visuals)

	# Materials
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.4, 0.4, 0.4)
	floor_material.metallic = 0.0
	floor_material.roughness = 0.9

	var wall_material := StandardMaterial3D.new()
	wall_material.albedo_color = Color(0.6, 0.6, 0.6)
	wall_material.metallic = 0.0
	wall_material.roughness = 0.8

	# Floor - MATCHES proxy collider (3.0 * size_scale * 2 = 18 units wide, 5.0 * size_scale * 2 = 30 units long)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = BoxMesh.new()
	floor_mesh.mesh.size = Vector3(3.0 * size_scale * 2, 0.1, 5.0 * size_scale * 2)
	floor_mesh.material_override = floor_material
	floor_mesh.position = Vector3(0, -1.4 * size_scale, 0)
	proxy_interior_visuals.add_child(floor_mesh)

	# Left wall - MATCHES proxy collider length
	var left_wall := MeshInstance3D.new()
	left_wall.mesh = BoxMesh.new()
	left_wall.mesh.size = Vector3(0.1, 2.5 * size_scale, 5.0 * size_scale * 2)
	left_wall.material_override = wall_material
	left_wall.position = Vector3(-3.0 * size_scale, 0, 0)
	proxy_interior_visuals.add_child(left_wall)

	# Right wall - MATCHES proxy collider length
	var right_wall := MeshInstance3D.new()
	right_wall.mesh = BoxMesh.new()
	right_wall.mesh.size = Vector3(0.1, 2.5 * size_scale, 5.0 * size_scale * 2)
	right_wall.material_override = wall_material
	right_wall.position = Vector3(3.0 * size_scale, 0, 0)
	proxy_interior_visuals.add_child(right_wall)

	# Back wall - MATCHES proxy collider position
	var back_wall := MeshInstance3D.new()
	back_wall.mesh = BoxMesh.new()
	back_wall.mesh.size = Vector3(3.0 * size_scale * 2, 2.5 * size_scale, 0.1)
	back_wall.material_override = wall_material
	back_wall.position = Vector3(0, 0, -5.0 * size_scale)
	proxy_interior_visuals.add_child(back_wall)

	# Ceiling - MATCHES proxy collider
	var ceiling := MeshInstance3D.new()
	ceiling.mesh = BoxMesh.new()
	ceiling.mesh.size = Vector3(3.0 * size_scale * 2, 0.1, 5.0 * size_scale * 2)
	ceiling.material_override = wall_material
	ceiling.position = Vector3(0, 1.4 * size_scale, 0)
	proxy_interior_visuals.add_child(ceiling)

	# NO LIGHT - wireframe mode doesn't need lighting

	# Create character proxy visual (will be updated to follow proxy body position)
	var character_proxy_visual = MeshInstance3D.new()
	character_proxy_visual.name = "CharacterProxyVisual"
	var capsule = CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.4
	character_proxy_visual.mesh = capsule

	var char_material = StandardMaterial3D.new()
	char_material.albedo_color = Color(0.2, 1.0, 0.2)
	char_material.emission_enabled = true
	char_material.emission = Color(0.1, 0.5, 0.1)
	char_material.emission_energy_multiplier = 1.0
	character_proxy_visual.material_override = char_material

	proxy_interior_visuals.add_child(character_proxy_visual)

func _create_station_proxy_interior_scene(viewport: SubViewport) -> void:
	# Create visual geometry for station interior in proxy space
	# Container is 5x ship size (size_scale = 15.0)
	# With recursive nesting, container uses relative coordinates (no Y offset)

	var size_scale = 15.0  # 5x the ship's 3x scale

	# Create container for proxy visuals
	var proxy_interior_visuals = Node3D.new()
	proxy_interior_visuals.name = "StationProxyInteriorVisuals"
	viewport.add_child(proxy_interior_visuals)

	# Materials
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.5, 0.5, 0.5)
	floor_material.metallic = 0.1
	floor_material.roughness = 0.8

	var wall_material := StandardMaterial3D.new()
	wall_material.albedo_color = Color(0.7, 0.7, 0.7)
	wall_material.metallic = 0.1
	wall_material.roughness = 0.7

	# Floor - match container collider position (relative coordinates)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = BoxMesh.new()
	floor_mesh.mesh.size = Vector3(3.0 * size_scale * 2, 0.1, 5.0 * size_scale * 2)
	floor_mesh.material_override = floor_material
	floor_mesh.position = Vector3(0, -1.4 * size_scale, 0)
	proxy_interior_visuals.add_child(floor_mesh)

	# Left wall - match container collider position
	var left_wall := MeshInstance3D.new()
	left_wall.mesh = BoxMesh.new()
	left_wall.mesh.size = Vector3(0.1, 2.5 * size_scale, 5.0 * size_scale * 2)
	left_wall.material_override = wall_material
	left_wall.position = Vector3(-3.0 * size_scale, 0, 0)
	proxy_interior_visuals.add_child(left_wall)

	# Right wall - match container collider position
	var right_wall := MeshInstance3D.new()
	right_wall.mesh = BoxMesh.new()
	right_wall.mesh.size = Vector3(0.1, 2.5 * size_scale, 5.0 * size_scale * 2)
	right_wall.material_override = wall_material
	right_wall.position = Vector3(3.0 * size_scale, 0, 0)
	proxy_interior_visuals.add_child(right_wall)

	# Back wall - match container collider position
	var back_wall := MeshInstance3D.new()
	back_wall.mesh = BoxMesh.new()
	back_wall.mesh.size = Vector3(3.0 * size_scale * 2, 2.5 * size_scale, 0.1)
	back_wall.material_override = wall_material
	back_wall.position = Vector3(0, 0, -5.0 * size_scale)
	proxy_interior_visuals.add_child(back_wall)

	# Ceiling - match container collider position
	var ceiling := MeshInstance3D.new()
	ceiling.mesh = BoxMesh.new()
	ceiling.mesh.size = Vector3(3.0 * size_scale * 2, 0.1, 5.0 * size_scale * 2)
	ceiling.material_override = wall_material
	ceiling.position = Vector3(0, 1.4 * size_scale, 0)
	proxy_interior_visuals.add_child(ceiling)

	# NO LIGHT - wireframe mode doesn't need lighting

	# Create character proxy visual (will be updated to follow proxy body position)
	var character_proxy_visual = MeshInstance3D.new()
	character_proxy_visual.name = "CharacterProxyVisual"
	var capsule = CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.4
	character_proxy_visual.mesh = capsule

	var char_material = StandardMaterial3D.new()
	char_material.albedo_color = Color(0.2, 1.0, 0.2)
	char_material.emission_enabled = true
	char_material.emission = Color(0.1, 0.5, 0.1)
	char_material.emission_energy_multiplier = 1.0
	character_proxy_visual.material_override = char_material

	proxy_interior_visuals.add_child(character_proxy_visual)

	# Create vehicle proxy visual (will be updated to follow docked vehicle position)
	var vehicle_proxy_visual = MeshInstance3D.new()
	vehicle_proxy_visual.name = "VehicleProxyVisual"
	var vehicle_mesh = BoxMesh.new()
	# Ship size: 3x scale (18 wide, 9 tall, 30 long)
	vehicle_mesh.size = Vector3(18, 9, 30)
	vehicle_proxy_visual.mesh = vehicle_mesh

	var vehicle_material = StandardMaterial3D.new()
	vehicle_material.albedo_color = Color(0.2, 0.2, 1.0)
	vehicle_material.emission_enabled = true
	vehicle_material.emission = Color(0.1, 0.1, 0.5)
	vehicle_material.emission_energy_multiplier = 1.0
	vehicle_proxy_visual.material_override = vehicle_material

	proxy_interior_visuals.add_child(vehicle_proxy_visual)

func _setup_cameras() -> void:
	# Main FPS camera (interior proxy view) - uses default viewport
	main_camera = Camera3D.new()
	main_camera.name = "MainCamera"
	main_camera.fov = 75
	main_camera.near = 0.1
	main_camera.far = 5000
	main_camera.current = true
	# Set initial position so we can see something
	main_camera.position = Vector3(0, 1.5, 0)
	add_child(main_camera)

	# External world camera (god view) - uses external viewport - WIREFRAME
	external_camera = Camera3D.new()
	external_camera.name = "ExternalCamera"
	external_camera.fov = 60
	external_camera.near = 0.1
	external_camera.far = 5000
	external_camera.cull_mask = 0xFFFFF  # See everything including layer 2 (character)
	# Set initial position for external view
	external_camera.position = Vector3(0, 15, 20)
	external_viewport.add_child(external_camera)
	# Look at must be called after adding to tree
	await get_tree().process_frame
	external_camera.look_at(Vector3.ZERO, Vector3.UP)

	# Dock interior camera (fixed view inside container) - WIREFRAME
	dock_interior_camera = Camera3D.new()
	dock_interior_camera.name = "DockInteriorCamera"
	dock_interior_camera.fov = 60
	dock_interior_camera.near = 0.1
	dock_interior_camera.far = 5000
	dock_interior_camera.cull_mask = 0xFFFFF  # See everything including layer 2 (character)
	# Position inside the container looking at the dock area
	dock_interior_camera.position = Vector3(0, 10, 20)
	dock_interior_viewport.add_child(dock_interior_camera)
	await get_tree().process_frame
	dock_interior_camera.look_at(Vector3(0, 0, 0), Vector3.UP)

func _setup_display() -> void:
	# Create a CanvasLayer to display all viewports
	var canvas_layer := CanvasLayer.new()
	canvas_layer.layer = 100
	add_child(canvas_layer)

	# External view (picture-in-picture bottom right - wireframe)
	external_rect = TextureRect.new()
	external_rect.name = "ExternalView"
	external_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	external_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED

	var external_style = StyleBoxFlat.new()
	external_style.bg_color = Color(0, 0, 0, 0.5)
	external_style.border_color = Color(0, 1, 1, 1)  # Cyan border
	external_style.border_width_left = 3
	external_style.border_width_right = 3
	external_style.border_width_top = 3
	external_style.border_width_bottom = 3

	external_panel = Panel.new()
	external_panel.name = "ExternalPIPPanel"
	external_panel.add_theme_stylebox_override("panel", external_style)
	canvas_layer.add_child(external_panel)
	external_panel.add_child(external_rect)

	# Dock interior view (picture-in-picture top right - wireframe)
	dock_interior_rect = TextureRect.new()
	dock_interior_rect.name = "DockInteriorView"
	dock_interior_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dock_interior_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED

	var dock_style = StyleBoxFlat.new()
	dock_style.bg_color = Color(0, 0, 0, 0.5)
	dock_style.border_color = Color(1, 0.5, 0, 1)  # Orange border
	dock_style.border_width_left = 3
	dock_style.border_width_right = 3
	dock_style.border_width_top = 3
	dock_style.border_width_bottom = 3

	dock_panel = Panel.new()
	dock_panel.name = "DockInteriorPIPPanel"
	dock_panel.add_theme_stylebox_override("panel", dock_style)
	canvas_layer.add_child(dock_panel)
	dock_panel.add_child(dock_interior_rect)

	# Update sizes on ready
	_update_viewport_sizes()

	# Connect to viewport size changes
	get_viewport().size_changed.connect(_update_viewport_sizes)

func _update_viewport_sizes() -> void:
	if not external_rect or not external_viewport or not dock_interior_rect or not dock_interior_viewport:
		return

	var window_size = get_viewport().get_visible_rect().size

	# PIP dimensions
	var pip_width = window_size.x / 4.0
	var pip_height = window_size.y / 4.0

	# External view (bottom right corner) - Ship interior wireframe
	var external_pos = Vector2(window_size.x - pip_width - 10, window_size.y - pip_height - 10)
	external_viewport.size = Vector2i(pip_width, pip_height)
	external_rect.texture = external_viewport.get_texture()
	external_rect.size = Vector2(pip_width, pip_height)
	external_rect.position = Vector2.ZERO

	if external_panel:
		external_panel.position = external_pos
		external_panel.size = Vector2(pip_width, pip_height)

	# Dock interior view (top right corner) - Docking station interior wireframe
	var dock_pos = Vector2(window_size.x - pip_width - 10, 10)
	dock_interior_viewport.size = Vector2i(pip_width, pip_height)
	dock_interior_rect.texture = dock_interior_viewport.get_texture()
	dock_interior_rect.size = Vector2(pip_width, pip_height)
	dock_interior_rect.position = Vector2.ZERO

	if dock_panel:
		dock_panel.position = dock_pos
		dock_panel.size = Vector2(pip_width, pip_height)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Update base rotation for mouse look (yaw and pitch only)
		base_rotation.y -= event.relative.x * mouse_sensitivity
		base_rotation.x -= event.relative.y * mouse_sensitivity
		base_rotation.x = clamp(base_rotation.x, -PI/2, PI/2)

	# Toggle mouse capture
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Toggle third person mode with 'O' key
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_O:
			third_person_mode = !third_person_mode

func _process(delta: float) -> void:
	# Smoothly interpolate camera up direction to match gravity
	_update_up_direction_transition(delta)

	_update_main_camera()
	_update_external_camera()
	_update_dock_interior_camera()
	_update_proxy_character_visuals()
	_update_pip_visibility()

func _update_up_direction_transition(delta: float) -> void:
	# During space transitions, smoothly interpolate toward target
	# During normal movement within a space, instantly match the space orientation
	if is_transitioning_up and current_up_vector.distance_to(target_up_vector) > 0.01:
		current_up_vector = current_up_vector.slerp(target_up_vector, up_transition_speed * delta).normalized()
		# Check if transition is complete
		if current_up_vector.distance_to(target_up_vector) <= 0.01:
			is_transitioning_up = false
	else:
		# Not transitioning - instantly match the target (which tracks current space)
		current_up_vector = target_up_vector

func set_target_up_direction(new_up: Vector3) -> void:
	# Set the target up direction for smooth gravity transition
	# Used when entering/exiting spaces with different orientations
	var normalized_new_up = new_up.normalized()

	# Don't adjust yaw - the character orientation handles this automatically
	# The camera uses character's actual up direction which is already correct
	target_up_vector = normalized_new_up
	is_transitioning_up = true  # Start smooth up direction transition

func _get_camera_basis_from_look_and_up(forward: Vector3, up: Vector3) -> Basis:
	# Construct a camera basis from a forward direction and up vector
	# This maintains look direction while adjusting to new gravity orientation
	var right = forward.cross(up).normalized()
	var actual_up = right.cross(forward).normalized()
	var actual_forward = -forward.normalized()  # Camera looks down -Z

	# Construct basis from orthonormal vectors
	return Basis(right, actual_up, actual_forward)

func _update_main_camera() -> void:
	if not is_instance_valid(character):
		return

	if character.is_in_container and is_instance_valid(vehicle_container) and vehicle_container.exterior_body:
		_update_container_camera()
	elif character.is_in_vehicle and is_instance_valid(vehicle) and vehicle.exterior_body:
		_update_vehicle_camera()
	else:
		_update_world_camera()

	# Update character visibility
	# In first person: hide from main camera but show in PIP
	# In third person: show everywhere
	if character and character.character_visual:
		character.character_visual.visible = true  # Always visible in world
		if third_person_mode:
			# Show to all cameras
			main_camera.cull_mask = 0xFFFFF  # See everything
			character.character_visual.layers = 1  # Layer 1 (default)
		else:
			# Hide character from main camera, but show in PIP cameras
			# Main camera doesn't see layer 2, but PIP cameras see all layers
			main_camera.cull_mask = 0xFFFFFFFD  # All layers except layer 2 (binary: ...11111101)
			character.character_visual.layers = 2  # Put character on layer 2 (binary: 00000010)

func _update_container_camera() -> void:
	var proxy_pos = character.get_proxy_position()
	var container_pos = vehicle_container.exterior_body.global_position
	var container_basis = vehicle_container.exterior_body.global_transform.basis

	# Always use character's actual up direction for instant tracking
	# This keeps camera locked to the character's orientation
	var character_up = character.character_visual.global_transform.basis.y
	var effective_up = character_up

	# Get look direction from base_rotation (yaw and pitch)
	var rotation_basis = Basis.from_euler(base_rotation)
	var local_forward = -rotation_basis.z

	if third_person_mode:
		# Third person: camera behind and above character
		# Calculate proxy position in world space first
		var world_proxy_pos = container_pos + container_basis * proxy_pos
		
		# Calculate back offset in world space (along look direction)
		var world_forward = container_basis * local_forward
		var back_offset = -world_forward * third_person_distance
		
		# Add offsets in world space using effective up (handles upside down correctly)
		var world_camera_pos = world_proxy_pos + effective_up * 3.0 + back_offset
		main_camera.global_position = world_camera_pos

		# Construct basis with effective up
		var camera_basis = _get_camera_basis_from_look_and_up(world_forward, effective_up)
		main_camera.global_transform.basis = camera_basis
	else:
		# First person: camera at head height
		# Calculate proxy position in world space first
		var world_proxy_pos = container_pos + container_basis * proxy_pos
		
		# Then add head offset in world space using effective up
		# This correctly handles upside down orientation
		var world_camera_pos = world_proxy_pos + effective_up * 1.5

		main_camera.global_position = world_camera_pos

		# Transform local forward to world space, then construct basis with effective up
		var world_forward = container_basis * local_forward
		var camera_basis = _get_camera_basis_from_look_and_up(world_forward, effective_up)
		main_camera.global_transform.basis = camera_basis

func _update_vehicle_camera() -> void:
	if not is_instance_valid(vehicle) or not vehicle.exterior_body:
		return

	var proxy_pos = character.get_proxy_position()
	var vehicle_pos = vehicle.exterior_body.global_position
	var vehicle_basis = vehicle.exterior_body.global_transform.basis

	# Always use character's actual up direction for instant tracking
	# This keeps camera locked to the character's orientation
	var character_up = character.character_visual.global_transform.basis.y
	var effective_up = character_up

	# Get look direction from base_rotation (yaw and pitch)
	var rotation_basis = Basis.from_euler(base_rotation)
	var local_forward = -rotation_basis.z

	if third_person_mode:
		# Third person: camera behind and above character
		# Calculate proxy position in world space first
		var world_proxy_pos = vehicle_pos + vehicle_basis * proxy_pos
		
		# Calculate back offset in world space (along look direction)
		var world_forward = vehicle_basis * local_forward
		var back_offset = -world_forward * third_person_distance
		
		# Add offsets in world space using effective up (handles upside down correctly)
		var world_camera_pos = world_proxy_pos + effective_up * 3.0 + back_offset
		main_camera.global_position = world_camera_pos

		# Construct basis with effective up
		var camera_basis = _get_camera_basis_from_look_and_up(world_forward, effective_up)
		main_camera.global_transform.basis = camera_basis
	else:
		# First person: camera at head height
		# Calculate proxy position in world space first
		var world_proxy_pos = vehicle_pos + vehicle_basis * proxy_pos
		
		# Then add head offset in world space using effective up
		# This correctly handles upside down orientation
		var world_camera_pos = world_proxy_pos + effective_up * 1.5

		main_camera.global_position = world_camera_pos

		# Transform local forward to world space, then construct basis with effective up
		var world_forward = vehicle_basis * local_forward
		var camera_basis = _get_camera_basis_from_look_and_up(world_forward, effective_up)
		main_camera.global_transform.basis = camera_basis

func _update_world_camera() -> void:
	var world_pos = character.get_world_position()

	# Always use world up in world space
	var effective_up = Vector3.UP

	# Get look direction from base_rotation
	var rotation_basis = Basis.from_euler(base_rotation)
	var forward = -rotation_basis.z

	if third_person_mode:
		# Third person camera - position behind and above character
		var offset = -forward * third_person_distance + Vector3(0, 3, 0)
		main_camera.global_position = world_pos + offset
		# Use effective_up for instant orientation or smooth transition
		var camera_basis = _get_camera_basis_from_look_and_up(forward, effective_up)
		main_camera.global_transform.basis = camera_basis
	else:
		# First person camera - at head height
		var cam_pos = world_pos + Vector3(0, 1.5, 0)
		main_camera.global_position = cam_pos
		# In world space, up is always Vector3.UP (no transition needed)
		var camera_basis = _get_camera_basis_from_look_and_up(forward, Vector3.UP)
		main_camera.global_transform.basis = camera_basis

func _update_external_camera() -> void:
	# External camera shows ship PROXY interior (stable, non-moving space)
	if not is_instance_valid(external_camera):
		return

	# Camera is in the proxy interior space (stable coordinates)
	# Position camera at back of ship interior, elevated
	var size_scale = 3.0
	var cam_pos = Vector3(0, 3, -12 * size_scale / 3.0)  # Back of interior, elevated

	external_camera.position = cam_pos

	# Look toward the front opening
	var look_target = Vector3(0, 0, 12 * size_scale / 3.0)  # Front entrance
	external_camera.look_at(look_target, Vector3.UP)


func _get_outermost_container() -> VehicleContainer:
	# Find the highest level (outermost) container in the nesting hierarchy
	# Start with the container the player/vehicle is in, then check if that container is docked
	var current_container: VehicleContainer = null
	
	# Determine which container the player is currently in
	if character.is_in_container:
		# Player is directly in a container - find which one
		var player_space = PhysicsServer3D.body_get_space(character.proxy_body)
		if is_instance_valid(vehicle_container) and vehicle_container.get_interior_space() == player_space:
			current_container = vehicle_container
	elif character.is_in_vehicle and is_instance_valid(vehicle) and vehicle.is_docked:
		# Player is in a docked vehicle - get the container it's docked in
		current_container = vehicle._get_docked_container()
	
	# If no container found, return null
	if not current_container:
		return null
	
	# Now traverse up the nesting hierarchy to find the outermost container
	# Keep checking if the current container is itself docked in another container
	var outermost = current_container
	while outermost and outermost.is_docked:
		var parent_container = outermost._get_docked_container()
		if parent_container:
			outermost = parent_container
		else:
			break
	
	return outermost

func _update_dock_interior_camera() -> void:
	# Dock interior camera shows the OUTERMOST container interior (highest level nesting)
	if not is_instance_valid(dock_interior_camera):
		return

	# Get the outermost container in the nesting hierarchy
	var outermost_container = _get_outermost_container()
	if not outermost_container:
		return

	# Use the outermost container's size for camera positioning
	var size_scale = 3.0 * outermost_container.size_multiplier
	
	# Position camera at back of container interior, elevated to see contents
	# Floor is at y = -1.5 * size_scale + 0.1
	var floor_y = -1.5 * size_scale + 0.1
	var cam_y = floor_y + 4.0 * size_scale  # Camera elevated above floor
	var cam_z = -3.5 * size_scale  # Camera at back of container
	var cam_pos = Vector3(0, cam_y, cam_z)

	dock_interior_camera.position = cam_pos

	# Look at the center of the docking area
	var look_target = Vector3(0, floor_y + 1.5 * size_scale, 0)  # Center height
	dock_interior_camera.look_at(look_target, Vector3.UP)

func get_forward_direction() -> Vector3:
	if not is_instance_valid(character):
		return -main_camera.global_transform.basis.z.normalized()

	if character.is_in_vehicle or character.is_in_container:
		var forward = Vector3(0, 0, -1)
		var rotation_basis = Basis.from_euler(base_rotation)
		forward = rotation_basis * forward
		forward.y = 0
		return forward.normalized()
	else:
		var forward = -main_camera.global_transform.basis.z
		forward.y = 0
		return forward.normalized()

func get_right_direction() -> Vector3:
	if not is_instance_valid(character):
		return main_camera.global_transform.basis.x.normalized()

	if character.is_in_vehicle or character.is_in_container:
		var right = Vector3(1, 0, 0)
		var rotation_basis = Basis.from_euler(base_rotation)
		right = rotation_basis * right
		right.y = 0
		return right.normalized()
	else:
		var right = main_camera.global_transform.basis.x
		right.y = 0
		return right.normalized()

func _update_proxy_character_visuals() -> void:
	# Update character visual in proxy interior viewports
	if not is_instance_valid(character):
		return

	# Get proxy position from character controller
	var proxy_pos = character.get_proxy_position()

	# Update character visual in ship interior viewport
	if is_instance_valid(external_viewport):
		var ship_char_visual = external_viewport.get_node_or_null("ShipProxyInteriorVisuals/CharacterProxyVisual")
		if ship_char_visual:
			# Only show if character is in vehicle
			ship_char_visual.visible = character.is_in_vehicle
			if character.is_in_vehicle:
				ship_char_visual.position = proxy_pos

	# Update character visual in station interior viewport
	if is_instance_valid(dock_interior_viewport):
		var station_char_visual = dock_interior_viewport.get_node_or_null("StationProxyInteriorVisuals/CharacterProxyVisual")
		if station_char_visual:
			# Show character if in container OR if in docked vehicle
			var show_character = character.is_in_container or (character.is_in_vehicle and is_instance_valid(vehicle) and vehicle.is_docked)
			station_char_visual.visible = show_character

			if character.is_in_container:
				station_char_visual.position = proxy_pos
			elif character.is_in_vehicle and is_instance_valid(vehicle) and vehicle.is_docked:
				# Character is in docked vehicle - show in vehicle's dock position
				# Transform proxy pos through vehicle to station space
				if vehicle.exterior_body:
					var vehicle_world_pos = vehicle.exterior_body.global_position
					var vehicle_basis = vehicle.exterior_body.global_transform.basis
					var container_pos = vehicle_container.exterior_body.global_position
					var container_basis = vehicle_container.exterior_body.global_transform.basis

					# Character world position
					var char_world_pos = vehicle_world_pos + vehicle_basis * proxy_pos

					# Transform to container local space
					var relative_pos = char_world_pos - container_pos
					var container_local_pos = container_basis.inverse() * relative_pos

					station_char_visual.position = container_local_pos

		# Update vehicle visual in station interior viewport
		var station_vehicle_visual = dock_interior_viewport.get_node_or_null("StationProxyInteriorVisuals/VehicleProxyVisual")
		if station_vehicle_visual:
			# Show vehicle if it's docked
			station_vehicle_visual.visible = is_instance_valid(vehicle) and vehicle.is_docked
			if is_instance_valid(vehicle) and vehicle.is_docked and vehicle.dock_proxy_body.is_valid():
				# Get position directly from dock proxy body (in container local space)
				var dock_transform: Transform3D = PhysicsServer3D.body_get_state(vehicle.dock_proxy_body, PhysicsServer3D.BODY_STATE_TRANSFORM)

				# With recursive nesting, dock_transform is already in container's interior space
				# which uses the same coordinate system as the visual geometry
				# No Y offset needed
				var station_proxy_pos = dock_transform.origin

				station_vehicle_visual.position = station_proxy_pos
				station_vehicle_visual.transform.basis = dock_transform.basis

func _update_pip_visibility() -> void:
	# Context-aware PIP camera visibility
	if not is_instance_valid(character):
		return

	# Show/hide external PIP (ship exterior) based on player location
	if external_panel:
		# Show ship exterior when player is IN the ship
		external_panel.visible = character.is_in_vehicle

	# Show/hide dock PIP (container exterior) based on player/ship location
	if dock_panel:
		# Show container exterior when:
		# 1. Player is IN container, OR
		# 2. Ship is docked in container (even if player not in container/ship)
		var show_container = character.is_in_container
		if not show_container and is_instance_valid(vehicle):
			show_container = vehicle.is_docked
		dock_panel.visible = show_container
