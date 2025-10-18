extends Node3D

## Improved lighting and environment setup for space game
## Add this to your main scene as a child of GameManager

func _ready():
	_setup_world_environment()
	_setup_directional_light()

func _setup_world_environment():
	# Create WorldEnvironment with enhanced settings
	var world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"

	var environment = Environment.new()

	# Background - Pure black space
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.0, 0.0, 0.0)  # Pure black

	# Ambient light - subtle blue tint for space
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.1, 0.15, 0.2)
	environment.ambient_light_energy = 0.3

	# SSAO (Screen Space Ambient Occlusion) - HIGH QUALITY
	environment.ssao_enabled = true
	environment.ssao_radius = 2.0
	environment.ssao_intensity = 1.5
	environment.ssao_power = 2.0
	environment.ssao_detail = 0.5
	environment.ssao_horizon = 0.15
	environment.ssao_sharpness = 1.0

	# SSIL (Screen Space Indirect Lighting) - Adds bounce light
	environment.ssil_enabled = true
	environment.ssil_radius = 8.0
	environment.ssil_intensity = 1.0
	environment.ssil_sharpness = 0.98
	environment.ssil_normal_rejection = 1.0

	# Glow/Bloom for ship lights and emissive materials
	environment.glow_enabled = true
	environment.glow_intensity = 0.8
	environment.glow_strength = 1.2
	environment.glow_bloom = 0.15
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	# Adjust exposure for better contrast
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.0
	environment.tonemap_white = 1.0

	# Volumetric fog for atmosphere (subtle)
	environment.volumetric_fog_enabled = false  # Enable if you want atmospheric effects

	world_env.environment = environment
	add_child(world_env)

	print("[Environment] Enhanced lighting setup complete")

func _setup_directional_light():
	# Main directional light (like a sun/star)
	var dir_light = DirectionalLight3D.new()
	dir_light.name = "DirectionalLight"
	dir_light.rotation_degrees = Vector3(-45, 30, 0)

	# Light properties
	dir_light.light_color = Color(1.0, 0.95, 0.9)  # Slightly warm white
	dir_light.light_energy = 1.2

	# Shadow settings - HIGHEST QUALITY
	dir_light.shadow_enabled = true
	dir_light.shadow_bias = 0.01
	dir_light.shadow_normal_bias = 1.0
	dir_light.shadow_blur = 2.0  # Softer shadows
	dir_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	dir_light.directional_shadow_split_1 = 0.1
	dir_light.directional_shadow_split_2 = 0.3
	dir_light.directional_shadow_split_3 = 0.6
	dir_light.directional_shadow_max_distance = 500.0
	dir_light.directional_shadow_fade_start = 0.8

	add_child(dir_light)

	print("[Lighting] Directional light setup complete")
