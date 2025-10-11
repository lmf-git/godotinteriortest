class_name VehicleContainer
extends Node3D

## VehicleContainer with exterior physics and proxy interior system
## Similar to vehicle but larger, with docking bay for vehicles

@export var physics_proxy: PhysicsProxy

# Station proxy Y offset in proxy space - MUST be different from ship to avoid overlap!
# Ship floor: y=-4.2, Station floor: y=50
const STATION_PROXY_Y_OFFSET: float = 50.0

# VehicleContainer components
var exterior_body: RigidBody3D  # VehicleContainer exterior in world
var interior_proxy_colliders: Array[RID]  # Static colliders in proxy space
var dock_proxy_colliders: Array[RID]  # Dock bay colliders for vehicle physics
var transition_zone: Area3D  # Zone where vehicles/players can transition to interior

func _ready() -> void:
	_create_container_exterior()
	_create_container_proxy_interior()
	_create_dock_proxy_colliders()
	_create_transition_zone()

func _create_container_exterior() -> void:
	# Create container as SCALED UP VERSION OF SHIP (exactly like ship but bigger)
	exterior_body = RigidBody3D.new()
	exterior_body.name = "ExteriorBody"
	exterior_body.mass = 50000.0
	exterior_body.gravity_scale = 1.0  # Enable gravity so it sits on ground
	exterior_body.linear_damp = 5.0  # Heavy damping - it's a station
	exterior_body.angular_damp = 5.0
	add_child(exterior_body)

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.85, 0.85, 0.85)
	material.metallic = 0.2
	material.roughness = 0.7

	# Container is 5x ship size (ship is already 3x base, so container is effectively 15x base)
	# Ship dimensions: 18 wide, 9 tall, 30 long
	# Container dimensions: 90 wide, 45 tall, 150 long
	var size_scale = 15.0  # 5x the ship's 3x scale

	# Floor (same proportions as ship)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = BoxMesh.new()
	floor_mesh.mesh.size = Vector3(6 * size_scale, 0.2, 10 * size_scale)
	floor_mesh.material_override = material
	floor_mesh.position = Vector3(0, -1.4 * size_scale, 0)
	floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	exterior_body.add_child(floor_mesh)

	var floor_collision := CollisionShape3D.new()
	floor_collision.shape = BoxShape3D.new()
	floor_collision.shape.size = Vector3(6 * size_scale, 0.2, 10 * size_scale)
	floor_collision.position = Vector3(0, -1.4 * size_scale, 0)
	exterior_body.add_child(floor_collision)

	# Left wall (same proportions as ship)
	var left_wall := MeshInstance3D.new()
	left_wall.mesh = BoxMesh.new()
	left_wall.mesh.size = Vector3(0.2, 3 * size_scale, 10 * size_scale)
	left_wall.material_override = material
	left_wall.position = Vector3(-3 * size_scale, 0, 0)
	exterior_body.add_child(left_wall)

	var left_collision := CollisionShape3D.new()
	left_collision.shape = BoxShape3D.new()
	left_collision.shape.size = Vector3(0.2, 3 * size_scale, 10 * size_scale)
	left_collision.position = Vector3(-3 * size_scale, 0, 0)
	exterior_body.add_child(left_collision)

	# Right wall (same proportions as ship)
	var right_wall := MeshInstance3D.new()
	right_wall.mesh = BoxMesh.new()
	right_wall.mesh.size = Vector3(0.2, 3 * size_scale, 10 * size_scale)
	right_wall.material_override = material
	right_wall.position = Vector3(3 * size_scale, 0, 0)
	exterior_body.add_child(right_wall)

	var right_collision := CollisionShape3D.new()
	right_collision.shape = BoxShape3D.new()
	right_collision.shape.size = Vector3(0.2, 3 * size_scale, 10 * size_scale)
	right_collision.position = Vector3(3 * size_scale, 0, 0)
	exterior_body.add_child(right_collision)

	# Back wall (same proportions as ship)
	var back_wall := MeshInstance3D.new()
	back_wall.mesh = BoxMesh.new()
	back_wall.mesh.size = Vector3(6 * size_scale, 3 * size_scale, 0.2)
	back_wall.material_override = material
	back_wall.position = Vector3(0, 0, -5 * size_scale)
	exterior_body.add_child(back_wall)

	var back_collision := CollisionShape3D.new()
	back_collision.shape = BoxShape3D.new()
	back_collision.shape.size = Vector3(6 * size_scale, 3 * size_scale, 0.2)
	back_collision.position = Vector3(0, 0, -5 * size_scale)
	exterior_body.add_child(back_collision)

	# Front wall - OPENING (completely open entrance, no obstruction)
	# No front wall mesh or collision - fully open for entry/exit

	# Ceiling (same proportions as ship)
	var ceiling := MeshInstance3D.new()
	ceiling.mesh = BoxMesh.new()
	ceiling.mesh.size = Vector3(6 * size_scale, 0.2, 10 * size_scale)
	ceiling.material_override = material
	ceiling.position = Vector3(0, 1.4 * size_scale, 0)
	exterior_body.add_child(ceiling)

	var ceiling_collision := CollisionShape3D.new()
	ceiling_collision.shape = BoxShape3D.new()
	ceiling_collision.shape.size = Vector3(6 * size_scale, 0.2, 10 * size_scale)
	ceiling_collision.position = Vector3(0, 1.4 * size_scale, 0)
	exterior_body.add_child(ceiling_collision)

func _create_container_proxy_interior() -> void:
	# Create static proxy interior colliders for container
	# CRITICAL: Station proxy must be at DIFFERENT Y position than ship proxy to avoid overlap!
	# Ship floor is at y=-1.4*3 = -4.2 in proxy space
	# Station floor should be at y=50 in proxy space (well separated from ship)
	if not physics_proxy:
		push_warning("PhysicsProxy not assigned to VehicleContainer")
		return

	var proxy_space = physics_proxy.get_proxy_interior_space()
	interior_proxy_colliders = []

	var size_scale = 15.0  # 5x the ship's 3x scale

	# Floor collider - at different Y than ship!
	var floor_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(floor_shape, Vector3(3.0 * size_scale, 0.05, 5.0 * size_scale))

	var floor_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(floor_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(floor_body, proxy_space)
	PhysicsServer3D.body_add_shape(floor_body, floor_shape)
	PhysicsServer3D.body_set_state(floor_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(0, STATION_PROXY_Y_OFFSET, 0)))
	interior_proxy_colliders.append(floor_body)

	# Left wall - at station proxy Y offset
	var left_wall_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(left_wall_shape, Vector3(0.05, 1.25 * size_scale, 5.0 * size_scale))

	var left_wall_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(left_wall_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(left_wall_body, proxy_space)
	PhysicsServer3D.body_add_shape(left_wall_body, left_wall_shape)
	PhysicsServer3D.body_set_state(left_wall_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(-3.0 * size_scale, STATION_PROXY_Y_OFFSET, 0)))
	interior_proxy_colliders.append(left_wall_body)

	# Right wall - at station proxy Y offset
	var right_wall_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(right_wall_shape, Vector3(0.05, 1.25 * size_scale, 5.0 * size_scale))

	var right_wall_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(right_wall_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(right_wall_body, proxy_space)
	PhysicsServer3D.body_add_shape(right_wall_body, right_wall_shape)
	PhysicsServer3D.body_set_state(right_wall_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(3.0 * size_scale, STATION_PROXY_Y_OFFSET, 0)))
	interior_proxy_colliders.append(right_wall_body)

	# Back wall - at station proxy Y offset
	var back_wall_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(back_wall_shape, Vector3(3.0 * size_scale, 1.25 * size_scale, 0.05))

	var back_wall_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(back_wall_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(back_wall_body, proxy_space)
	PhysicsServer3D.body_add_shape(back_wall_body, back_wall_shape)
	PhysicsServer3D.body_set_state(back_wall_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(0, STATION_PROXY_Y_OFFSET, -5.0 * size_scale)))
	interior_proxy_colliders.append(back_wall_body)

	# Ceiling - at station proxy Y offset + ceiling height
	var ceiling_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(ceiling_shape, Vector3(3.0 * size_scale, 0.05, 5.0 * size_scale))

	var ceiling_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(ceiling_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(ceiling_body, proxy_space)
	PhysicsServer3D.body_add_shape(ceiling_body, ceiling_shape)
	# Ceiling is at STATION_PROXY_Y_OFFSET + 2.8*size_scale (total height of station interior)
	PhysicsServer3D.body_set_state(ceiling_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(0, STATION_PROXY_Y_OFFSET + 2.8 * size_scale, 0)))
	interior_proxy_colliders.append(ceiling_body)

	# Note: No front wall collider - this is the opening where players can enter

func _create_dock_proxy_colliders() -> void:
	# Create static colliders in dock proxy space for vehicle to interact with
	# Match ship proportions exactly - container is 5x ship size
	if not physics_proxy:
		return

	var dock_space = physics_proxy.get_dock_proxy_space()
	dock_proxy_colliders = []

	var size_scale = 15.0  # 5x the ship's 3x scale

	# Floor - Match container proportions
	var floor_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(floor_shape, Vector3(3.0 * size_scale, 0.05, 5.0 * size_scale))

	var floor_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(floor_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(floor_body, dock_space)
	PhysicsServer3D.body_add_shape(floor_body, floor_shape)
	PhysicsServer3D.body_set_state(floor_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(0, -1.4 * size_scale, 0)))
	dock_proxy_colliders.append(floor_body)

	# Left wall - Match container proportions
	var left_wall_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(left_wall_shape, Vector3(0.05, 1.25 * size_scale, 5.0 * size_scale))

	var left_wall_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(left_wall_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(left_wall_body, dock_space)
	PhysicsServer3D.body_add_shape(left_wall_body, left_wall_shape)
	PhysicsServer3D.body_set_state(left_wall_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(-3.0 * size_scale, 0, 0)))
	dock_proxy_colliders.append(left_wall_body)

	# Right wall - Match container proportions
	var right_wall_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(right_wall_shape, Vector3(0.05, 1.25 * size_scale, 5.0 * size_scale))

	var right_wall_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(right_wall_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(right_wall_body, dock_space)
	PhysicsServer3D.body_add_shape(right_wall_body, right_wall_shape)
	PhysicsServer3D.body_set_state(right_wall_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(3.0 * size_scale, 0, 0)))
	dock_proxy_colliders.append(right_wall_body)

	# Back wall - Match container proportions
	var back_wall_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(back_wall_shape, Vector3(3.0 * size_scale, 1.25 * size_scale, 0.05))

	var back_wall_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(back_wall_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(back_wall_body, dock_space)
	PhysicsServer3D.body_add_shape(back_wall_body, back_wall_shape)
	PhysicsServer3D.body_set_state(back_wall_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(0, 0, -5.0 * size_scale)))
	dock_proxy_colliders.append(back_wall_body)

	# Ceiling - Match container proportions
	var ceiling_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(ceiling_shape, Vector3(3.0 * size_scale, 0.05, 5.0 * size_scale))

	var ceiling_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(ceiling_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(ceiling_body, dock_space)
	PhysicsServer3D.body_add_shape(ceiling_body, ceiling_shape)
	PhysicsServer3D.body_set_state(ceiling_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(0, 1.4 * size_scale, 0)))
	dock_proxy_colliders.append(ceiling_body)

	# Note: No front wall - this is the dock opening

func _create_transition_zone() -> void:
	# Create invisible trigger zone at container entrance
	# Match ship entrance zone proportions (5x larger)
	transition_zone = Area3D.new()
	transition_zone.name = "TransitionZone"
	add_child(transition_zone)

	var zone_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	# Ship entrance zone: Vector3(10, 8, 3) at z=16.5
	# Container entrance zone: 5x larger
	box_shape.size = Vector3(50, 40, 15)
	zone_shape.shape = box_shape
	transition_zone.add_child(zone_shape)

	transition_zone.position = Vector3(0, 0, 82.5)  # At container entrance (16.5 * 5)
	transition_zone.monitoring = true
	transition_zone.monitorable = true

func apply_rotation(axis: Vector3, torque: float) -> void:
	if exterior_body:
		exterior_body.apply_torque(axis * torque)

func apply_thrust(direction: Vector3, force: float) -> void:
	if exterior_body:
		exterior_body.apply_central_force(direction * force)

func _exit_tree() -> void:
	# Clean up proxy colliders
	for collider in interior_proxy_colliders:
		if collider.is_valid():
			PhysicsServer3D.free_rid(collider)

	for collider in dock_proxy_colliders:
		if collider.is_valid():
			PhysicsServer3D.free_rid(collider)
