class_name FPSCamera
extends Camera3D

## FPS Camera that handles rotation in local space (ship/station interior)
## Properly composes rotations for mouse look inside rotating vehicles

@export var character: CharacterController
@export var vehicle: Vehicle
@export var vehicle_container: VehicleContainer
@export var mouse_sensitivity: float = 0.002
@export var head_height: float = 1.5

# Base camera rotation (mouse look)
var base_rotation: Vector3 = Vector3.ZERO

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Mouse look
		base_rotation.y -= event.relative.x * mouse_sensitivity
		base_rotation.x -= event.relative.y * mouse_sensitivity
		base_rotation.x = clamp(base_rotation.x, -PI/2, PI/2)

	# Toggle mouse capture
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _process(_delta: float) -> void:
	_update_camera_position()

func _update_camera_position() -> void:
	if not is_instance_valid(character):
		return

	if character.is_in_container and is_instance_valid(vehicle_container) and vehicle_container.exterior_body:
		_update_container_camera()
	elif character.is_in_vehicle and is_instance_valid(vehicle) and vehicle.exterior_body:
		_update_vehicle_camera()
	elif not character.is_in_vehicle:
		_update_world_camera()

func _update_container_camera() -> void:
	# Camera in container interior
	var proxy_pos = character.get_proxy_position()
	var container_pos = vehicle_container.exterior_body.global_position
	var container_basis = vehicle_container.exterior_body.global_transform.basis

	# Camera position in proxy space (head height above character)
	var proxy_camera_pos = Vector3(proxy_pos.x, proxy_pos.y + head_height, proxy_pos.z + 0.1)

	# Transform camera position to container interior coordinate system
	var world_camera_pos = container_pos + container_basis * proxy_camera_pos

	# Position camera in world space
	global_position = world_camera_pos

	# Apply container rotation with proper local mouse look
	# Create mouse look rotation in container's local coordinate system
	var local_mouse_rotation = Basis.from_euler(Vector3(base_rotation.x, base_rotation.y, 0))

	# Compose rotations: container orientation * local mouse look
	global_transform.basis = container_basis * local_mouse_rotation

func _update_vehicle_camera() -> void:
	# Camera in vehicle interior
	var proxy_pos = character.get_proxy_position()
	var vehicle_pos = vehicle.exterior_body.global_position
	var vehicle_basis = vehicle.exterior_body.global_transform.basis

	# Camera position in proxy space (head height above character)
	var proxy_camera_pos = Vector3(proxy_pos.x, proxy_pos.y + head_height, proxy_pos.z + 0.1)

	# Transform camera position to vehicle interior coordinate system
	var world_camera_pos = vehicle_pos + vehicle_basis * proxy_camera_pos

	# Position camera in world space
	global_position = world_camera_pos

	# Apply vehicle rotation with proper local mouse look
	var local_mouse_rotation = Basis.from_euler(Vector3(base_rotation.x, base_rotation.y, 0))

	# Compose rotations: vehicle orientation * local mouse look
	global_transform.basis = vehicle_basis * local_mouse_rotation

func _update_world_camera() -> void:
	# Camera in world space
	var world_pos = character.get_world_position()
	global_position = world_pos + Vector3(0, head_height, 0)

	# Use base rotation directly when not in vehicle
	global_transform.basis = Basis.from_euler(base_rotation)

func get_forward_direction() -> Vector3:
	## Returns forward direction for character movement
	if not is_instance_valid(character):
		return -global_transform.basis.z.normalized()

	if character.is_in_vehicle or character.is_in_container:
		# In proxy interior: use base rotation only (mouse look, no vehicle/container rotation)
		var forward = Vector3(0, 0, -1)
		var rotation_basis = Basis.from_euler(base_rotation)
		forward = rotation_basis * forward
		forward.y = 0
		return forward.normalized()
	else:
		# In world space: use full camera direction
		var forward = -global_transform.basis.z
		forward.y = 0
		return forward.normalized()

func get_right_direction() -> Vector3:
	## Returns right direction for character movement
	if not is_instance_valid(character):
		return global_transform.basis.x.normalized()

	if character.is_in_vehicle or character.is_in_container:
		# In proxy interior: use base rotation only
		var right = Vector3(1, 0, 0)
		var rotation_basis = Basis.from_euler(base_rotation)
		right = rotation_basis * right
		right.y = 0
		return right.normalized()
	else:
		# In world space: use full camera direction
		var right = global_transform.basis.x
		right.y = 0
		return right.normalized()
