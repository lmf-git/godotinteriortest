# Interior Physics Proxy System - Godot 4.5

Port of JavaScript/Three.js interior physics proxy system to Godot 4.5 with GDScript.

## Overview

This system allows players to move inside vehicles and vehicle containers with stable physics while the exterior rotates and moves. It uses separate physics spaces:

- **World Physics**: Main space physics (vehicles, containers moving/rotating in space)
- **Proxy Interior Physics**: Stable interior physics with gravity (player movement inside)
- **Dock Proxy Physics**: Separate space for vehicles docked inside containers

## Architecture

### Core Components

1. **PhysicsProxy** (`physics_proxy.gd`)
   - Manages three separate physics spaces
   - Handles gravity toggling for artificial gravity/magnetism

2. **Vehicle** (`vehicle.gd`)
   - Exterior RigidBody3D in world/dock space
   - Interior visual geometry (kinematic, visual only)
   - Static colliders in proxy interior space for player physics
   - Dock proxy body for when docked inside container

3. **VehicleContainer** (`vehicle_container.gd`)
   - Large structure with docking bay
   - Exterior physics body in world
   - Proxy interior colliders for player
   - Dock proxy colliders for vehicle physics when docked

4. **CharacterController** (`character_controller.gd`)
   - Dual physics bodies (world + proxy)
   - Switches between physics spaces seamlessly
   - Handles movement in both spaces

5. **FPSCamera** (`fps_camera.gd`)
   - First-person camera with mouse look
   - Properly composes rotations (vehicle rotation + mouse look)
   - Transforms proxy positions to world space

6. **GameManager** (`game_manager.gd`)
   - Main controller
   - Handles input, transitions, and state management

## Key Concepts

### Proxy Interior Physics

The player never collides with the actual vehicle/container interior. Instead:

1. Vehicle/container interiors are **visual only** (kinematic)
2. **Static colliders** exist in a separate "proxy" physics space
3. Player physics body exists in this proxy space
4. Player position is transformed from proxy space to world space for rendering

This means:
- Player experiences stable gravity and physics
- Vehicle/container can rotate freely without affecting player physics
- No jittering or instability from rotating collision shapes

### Nested Proxy System

Vehicles inside containers use a **nested proxy**:

1. Container exterior in world physics
2. Vehicle exterior can be in:
   - World physics (when flying free)
   - Dock proxy physics (when docked inside container)
3. Player is always in proxy interior physics
4. Positions are transformed through multiple spaces as needed

## Controls

- **WASD**: Character movement
- **Space**: Jump
- **Mouse**: Look around
- **Arrow Keys**: Vehicle pitch/yaw
- **Q/E**: Vehicle roll
- **M**: Vehicle thrust forward
- **N**: Vehicle thrust backward
- **U/J**: Container thrust (when docked or inside)
- **H/K**: Container yaw (when docked or inside)
- **B**: Toggle magnetism/artificial gravity (when docked)
- **ESC**: Toggle mouse capture

## Setup

1. Create a new 3D scene in Godot 4.5
2. Add a Node3D as root
3. Attach `game_manager.gd` to root
4. Run the scene

The system will automatically create:
- Physics proxy manager
- Vehicle at origin
- VehicleContainer at (100, 0, 0)
- Character inside vehicle
- FPS camera
- Starfield and lighting

## Physics Spaces

### World Space
- Default Godot physics space
- No gravity (space)
- Contains vehicle and container exterior bodies

### Proxy Interior Space
- Created via PhysicsServer3D
- Has gravity (-9.81 Y) by default
- Can be toggled for magnetism
- Contains static floor/wall colliders
- Contains character physics body

### Dock Proxy Space
- Created via PhysicsServer3D
- No gravity (space-like)
- Contains dock bay colliders
- Contains vehicle body when docked

## Transitions

### Entering Container
- Character walks through transition zone at container entrance
- Switches from `vehicle_interior` to `container_interior`
- Stays in proxy physics space
- Camera transforms update to use container rotation

### Docking Vehicle
- Vehicle enters container transition zone
- Vehicle physics transfers from world to dock proxy
- Vehicle can now collide with dock bay walls/floor
- Player can toggle magnetism (artificial gravity)

### Exiting
- Walking out of transition zones reverses the process
- Physics bodies seamlessly switch spaces
- State is preserved during transitions

## Implementation Notes

### Physics Server Usage

This implementation uses `PhysicsServer3D` directly for:
- Creating custom physics spaces
- Manual rigid body creation in custom spaces
- Low-level control over gravity per space

This is necessary because Godot's high-level physics nodes (RigidBody3D, etc.) are tied to the default world space.

### Transform Composition

Camera rotation in interiors uses proper composition:
```gdscript
# Vehicle/Container basis * Local mouse look basis
global_transform.basis = vehicle_basis * mouse_look_basis
```

This ensures:
- Mouse look works in local coordinates
- Yaw rotates around the vehicle's "up" direction
- No gimbal lock or unexpected behavior

### Visual Updates

Character visual position is updated in `_process`:
```gdscript
# Transform from proxy space to world space
world_pos = vehicle_pos + vehicle_basis * proxy_pos
```

## Differences from JavaScript Version

1. **Physics Engine**: RAPIER → Godot Physics (PhysicsServer3D)
2. **Scene Graph**: THREE.js → Godot Node tree
3. **Rendering**: WebGL → Godot renderer
4. **State Management**: Svelte runes → GDScript class variables
5. **Input**: DOM events → Godot Input system

## Future Enhancements

- [ ] Add smooth state transfer during docking
- [ ] Implement proper collision layers/masks
- [ ] Add EVA (spacewalk) mechanics
- [ ] Multiple vehicles and containers
- [ ] Networking/multiplayer support
- [ ] Save/load system for physics state
- [ ] Performance optimizations for large scales

## References

- Original JavaScript implementation: `Game.svelte`
- Godot Physics Server docs: https://docs.godotengine.org/en/stable/classes/class_physicsserver3d.html
