extends Node2D

const TERRAIN_SHADER_PATH := "res://shaders/terrain/terrain_binary_mask.gdshader"
const SURFACE_SIZE := Vector2(768.0, 256.0)
const TRANSITION_WIDTH := 220.0
const HEIGHT_BLEND_INFLUENCE := 1.5
const HEIGHT_BLEND_CONTRAST := 3.0
const TEXTURE_REPEAT_WORLD_SIZE := 256.0
const PREVIEW_SIZE := 192.0

const MATERIAL_A_DIFFUSE_PATH := "res://assets/Textures/mud.png"
const MATERIAL_A_HEIGHT_PATH := "res://assets/Textures/mud_height.png"
const MATERIAL_B_DIFFUSE_PATH := "res://assets/Textures/rocky_grass.png"
const MATERIAL_B_HEIGHT_PATH := "res://assets/Textures/rocky_grass_height.png"


func _ready() -> void:
	_create_camera()
	_create_demo_row(
		"Regular mask blend",
		Vector2(96.0, 96.0),
		0.0,
		1.0
	)
	_create_demo_row(
		"Height-aware blend with authored height maps",
		Vector2(96.0, 432.0),
		HEIGHT_BLEND_INFLUENCE,
		HEIGHT_BLEND_CONTRAST
	)
	_create_height_preview("Mud height map", Vector2(1080.0, 150.0), MATERIAL_A_HEIGHT_PATH)
	_create_height_preview("Rocky grass height map", Vector2(1080.0, 470.0), MATERIAL_B_HEIGHT_PATH)


func _create_camera() -> void:
	var camera := Camera2D.new()
	camera.name = "DemoCamera"
	camera.position = Vector2(610.0, 380.0)
	camera.zoom = Vector2(1.85, 1.85)
	camera.enabled = true
	add_child(camera)
	camera.make_current()


func _create_demo_row(label_text: String, position: Vector2, height_influence: float, height_contrast: float) -> void:
	_create_label(label_text, position + Vector2(0.0, -34.0), 22)

	var surface := Polygon2D.new()
	surface.name = label_text.replace(" ", "")
	surface.position = position
	surface.color = Color.WHITE
	surface.texture = _load_texture_from_image(MATERIAL_A_DIFFUSE_PATH)
	surface.polygon = PackedVector2Array([
		Vector2.ZERO,
		Vector2(SURFACE_SIZE.x, 0.0),
		SURFACE_SIZE,
		Vector2(0.0, SURFACE_SIZE.y),
	])
	surface.uv = PackedVector2Array([
		Vector2.ZERO,
		Vector2(SURFACE_SIZE.x, 0.0),
		SURFACE_SIZE,
		Vector2(0.0, SURFACE_SIZE.y),
	])
	surface.material = _build_demo_material(height_influence, height_contrast)
	add_child(surface)

	_create_tile_boundary_marks(position)


func _build_demo_material(height_influence: float, height_contrast: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(TERRAIN_SHADER_PATH) as Shader
	material.set_shader_parameter("terrain_type_1_texture", _load_texture_from_image(MATERIAL_A_DIFFUSE_PATH))
	material.set_shader_parameter("terrain_type_2_texture", _load_texture_from_image(MATERIAL_B_DIFFUSE_PATH))
	material.set_shader_parameter("terrain_mask", _build_demo_mask())
	material.set_shader_parameter("terrain_type_1_height", _load_texture_from_image(MATERIAL_A_HEIGHT_PATH))
	material.set_shader_parameter("terrain_type_2_height", _load_texture_from_image(MATERIAL_B_HEIGHT_PATH))
	material.set_shader_parameter("terrain_world_origin", Vector2.ZERO)
	material.set_shader_parameter("terrain_world_size", SURFACE_SIZE)
	material.set_shader_parameter("texture_repeat_world_size", TEXTURE_REPEAT_WORLD_SIZE)
	material.set_shader_parameter("height_blend_influence", height_influence)
	material.set_shader_parameter("height_blend_contrast", height_contrast)
	return material


func _load_texture_from_image(path: String) -> Texture2D:
	var image := Image.new()
	var load_result := image.load(path)
	if load_result != OK:
		push_error("HeightBlendDemo failed to load texture '%s': %s" % [path, error_string(load_result)])
		return null
	return ImageTexture.create_from_image(image)


func _build_demo_mask() -> Texture2D:
	var image := Image.create(int(SURFACE_SIZE.x), int(SURFACE_SIZE.y), false, Image.FORMAT_RGBA8)
	var transition_start := SURFACE_SIZE.x * 0.5 - TRANSITION_WIDTH * 0.5
	var transition_end := SURFACE_SIZE.x * 0.5 + TRANSITION_WIDTH * 0.5
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var mask_value := smoothstep(transition_start, transition_end, float(x))
			image.set_pixel(x, y, Color(mask_value, mask_value, mask_value, 1.0))
	return ImageTexture.create_from_image(image)


func _create_height_preview(label_text: String, position: Vector2, height_texture_path: String) -> void:
	_create_label(label_text, position + Vector2(-96.0, -140.0), 18)
	var preview := Sprite2D.new()
	preview.name = label_text.replace(" ", "").replace(":", "")
	preview.position = position
	preview.texture = _load_texture_from_image(height_texture_path)
	if preview.texture != null:
		preview.scale = Vector2(PREVIEW_SIZE / float(preview.texture.get_width()), PREVIEW_SIZE / float(preview.texture.get_height()))
	add_child(preview)


func _create_tile_boundary_marks(position: Vector2) -> void:
	var left_label_position := position + Vector2(80.0, SURFACE_SIZE.y + 12.0)
	var right_label_position := position + Vector2(SURFACE_SIZE.x - 190.0, SURFACE_SIZE.y + 12.0)
	_create_label("Mud texture", left_label_position, 16)
	_create_label("Rocky grass texture", right_label_position, 16)


func _create_label(text: String, position: Vector2, font_size: int) -> void:
	var label := Label.new()
	label.text = text
	label.position = position
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(label)
