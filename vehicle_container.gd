class_name VehicleContainer
extends Node3D

## VehicleContainer with exterior physics and proxy interior system
## Similar to vehicle but larger, with docking bay for vehicles

@export var physics_proxy: PhysicsProxy

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
	# Create container as group with opening instead of solid box
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

	# Floor
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = BoxMesh.new()
	floor_mesh.mesh.size = Vector3(60, 2, 80)
	floor_mesh.material_override = material
	floor_mesh.position = Vector3(0, -20, 0)
	floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	exterior_body.add_child(floor_mesh)

	var floor_collision := CollisionShape3D.new()
	floor_collision.shape = BoxShape3D.new()
	floor_collision.shape.size = Vector3(60, 2, 80)
	floor_collision.position = Vector3(0, -20, 0)
	exterior_body.add_child(floor_collision)

	# Ceiling
	var ceiling := MeshInstance3D.new()
	ceiling.mesh = BoxMesh.new()
	ceiling.mesh.size = Vector3(60, 2, 80)
	ceiling.material_override = material
	ceiling.position = Vector3(0, 20, 0)
	exterior_body.add_child(ceiling)

	var ceiling_collision := CollisionShape3D.new()
	ceiling_collision.shape = BoxShape3D.new()
	ceiling_collision.shape.size = Vector3(60, 2, 80)
	ceiling_collision.position = Vector3(0, 20, 0)
	exterior_body.add_child(ceiling_collision)

	# Left wall
	var left_wall := MeshInstance3D.new()
	left_wall.mesh = BoxMesh.new()
	left_wall.mesh.size = Vector3(2, 40, 80)
	left_wall.material_override = material
	left_wall.position = Vector3(-30, 0, 0)
	exterior_body.add_child(left_wall)

	var left_collision := CollisionShape3D.new()
	left_collision.shape = BoxShape3D.new()
	left_collision.shape.size = Vector3(2, 40, 80)
	left_collision.position = Vector3(-30, 0, 0)
	exterior_body.add_child(left_collision)

	# Right wall
	var right_wall := MeshInstance3D.new()
	right_wall.mesh = BoxMesh.new()
	right_wall.mesh.size = Vector3(2, 40, 80)
	right_wall.material_override = material
	right_wall.position = Vector3(30, 0, 0)
	exterior_body.add_child(right_wall)

	var right_collision := CollisionShape3D.new()
	right_collision.shape = BoxShape3D.new()
	right_collision.shape.size = Vector3(2, 40, 80)
	right_collision.position = Vector3(30, 0, 0)
	exterior_body.add_child(right_collision)

	# Back wall
	var back_wall := MeshInstance3D.new()
	back_wall.mesh = BoxMesh.new()
	back_wall.mesh.size = Vector3(60, 40, 2)
	back_wall.material_override = material
	back_wall.position = Vector3(0, 0, -40)
	exterior_body.add_child(back_wall)

	var back_collision := CollisionShape3D.new()
	back_collision.shape = BoxShape3D.new()
	back_collision.shape.size = Vector3(60, 40, 2)
	back_collision.position = Vector3(0, 0, -40)
	exterior_body.add_child(back_collision)

	# Front wall with opening - create pieces with gap in middle
	var front_wall_top := MeshInstance3D.new()
	front_wall_top.mesh = BoxMesh.new()
	front_wall_top.mesh.size = Vector3(60, 15, 2)
	front_wall_top.material_override = material
	front_wall_top.position = Vector3(0, 12.5, 40)
	exterior_body.add_child(front_wall_top)

	var front_wall_left := MeshInstance3D.new()
	front_wall_left.mesh = BoxMesh.new()
	front_wall_left.mesh.size = Vector3(15, 25, 2)
	front_wall_left.material_override = material
	front_wall_left.position = Vector3(-22.5, -7.5, 40)
	exterior_body.add_child(front_wall_left)

	var front_wall_right := MeshInstance3D.new()
	front_wall_right.mesh = BoxMesh.new()
	front_wall_right.mesh.size = Vector3(15, 25, 2)
	front_wall_right.material_override = material
	front_wall_right.position = Vector3(22.5, -7.5, 40)
	exterior_body.add_child(front_wall_right)

	# Front wall collisions (matching the opening pieces)
	var front_top_collision := CollisionShape3D.new()
	front_top_collision.shape = BoxShape3D.new()
	front_top_collision.shape.size = Vector3(60, 15, 2)
	front_top_collision.position = Vector3(0, 12.5, 40)
	exterior_body.add_child(front_top_collision)

	var front_left_collision := CollisionShape3D.new()
	front_left_collision.shape = BoxShape3D.new()
	front_left_collision.shape.size = Vector3(15, 25, 2)
	front_left_collision.position = Vector3(-22.5, -7.5, 40)
	exterior_body.add_child(front_left_collision)

	var front_right_collision := CollisionShape3D.new()
	front_right_collision.shape = BoxShape3D.new()
	front_right_collision.shape.size = Vector3(15, 25, 2)
	front_right_collision.position = Vector3(22.5, -7.5, 40)
	exterior_body.add_child(front_right_collision)

func _create_container_proxy_interior() -> void:
	# Create static proxy interior colliders for container
	# These are in the same proxy physics world as vehicle interior
	if not physics_proxy:
		push_warning("PhysicsProxy not assigned to VehicleContainer")
		return

	var proxy_space = physics_proxy.get_proxy_interior_space()
	interior_proxy_colliders = []

	# Container floor collider in proxy space
	var floor_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(floor_shape, Vector3(25, 0.1, 35))

	var floor_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(floor_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(floor_body, proxy_space)
	PhysicsServer3D.body_add_shape(floor_body, floor_shape)
	PhysicsServer3D.body_set_state(floor_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(0, -5, 0)))
	interior_proxy_colliders.append(floor_body)

	# Left wall
	var left_wall_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(left_wall_shape, Vector3(0.1, 15, 35))

	var left_wall_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(left_wall_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(left_wall_body, proxy_space)
	PhysicsServer3D.body_add_shape(left_wall_body, left_wall_shape)
	PhysicsServer3D.body_set_state(left_wall_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(-25, 10, 0)))
	interior_proxy_colliders.append(left_wall_body)

	# Right wall
	var right_wall_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(right_wall_shape, Vector3(0.1, 15, 35))

	var right_wall_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(right_wall_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(right_wall_body, proxy_space)
	PhysicsServer3D.body_add_shape(right_wall_body, right_wall_shape)
	PhysicsServer3D.body_set_state(right_wall_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(25, 10, 0)))
	interior_proxy_colliders.append(right_wall_body)

	# Back wall
	var back_wall_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(back_wall_shape, Vector3(25, 15, 0.1))

	var back_wall_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(back_wall_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(back_wall_body, proxy_space)
	PhysicsServer3D.body_add_shape(back_wall_body, back_wall_shape)
	PhysicsServer3D.body_set_state(back_wall_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(0, 10, -35)))
	interior_proxy_colliders.append(back_wall_body)

	# Note: No front wall collider - this is the opening where vehicles can enter

func _create_dock_proxy_colliders() -> void:
	# Create static colliders in dock proxy space for vehicle to interact with
	# These represent the dock bay interior boundaries
	if not physics_proxy:
		return

	var dock_space = physics_proxy.get_dock_proxy_space()
	dock_proxy_colliders = []

	# Dock floor
	var floor_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(floor_shape, Vector3(25, 0.5, 35))

	var floor_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(floor_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(floor_body, dock_space)
	PhysicsServer3D.body_add_shape(floor_body, floor_shape)
	PhysicsServer3D.body_set_state(floor_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(0, -15, 0)))
	dock_proxy_colliders.append(floor_body)

	# Left wall
	var left_wall_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(left_wall_shape, Vector3(0.5, 15, 35))

	var left_wall_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(left_wall_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(left_wall_body, dock_space)
	PhysicsServer3D.body_add_shape(left_wall_body, left_wall_shape)
	PhysicsServer3D.body_set_state(left_wall_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(-25, 0, 0)))
	dock_proxy_colliders.append(left_wall_body)

	# Right wall
	var right_wall_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(right_wall_shape, Vector3(0.5, 15, 35))

	var right_wall_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(right_wall_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(right_wall_body, dock_space)
	PhysicsServer3D.body_add_shape(right_wall_body, right_wall_shape)
	PhysicsServer3D.body_set_state(right_wall_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(25, 0, 0)))
	dock_proxy_colliders.append(right_wall_body)

	# Back wall
	var back_wall_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(back_wall_shape, Vector3(25, 15, 0.5))

	var back_wall_body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(back_wall_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(back_wall_body, dock_space)
	PhysicsServer3D.body_add_shape(back_wall_body, back_wall_shape)
	PhysicsServer3D.body_set_state(back_wall_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(0, 0, -35)))
	dock_proxy_colliders.append(back_wall_body)

	# Note: No front wall - this is the dock opening

func _create_transition_zone() -> void:
	# Create invisible trigger zone at container entrance
	transition_zone = Area3D.new()
	transition_zone.name = "TransitionZone"
	add_child(transition_zone)

	var zone_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(30, 25, 10)
	zone_shape.shape = box_shape
	transition_zone.add_child(zone_shape)

	transition_zone.position = Vector3(0, 0, 35)  # At container entrance
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
		if collider and collider != RID():
			PhysicsServer3D.free_rid(collider)

	for collider in dock_proxy_colliders:
		if collider and collider != RID():
			PhysicsServer3D.free_rid(collider)
