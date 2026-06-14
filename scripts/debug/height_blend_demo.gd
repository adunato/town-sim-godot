extends Node2D

const TERRAIN_SHADER_PATH := "res://shaders/terrain/terrain_binary_mask.gdshader"
const SURFACE_SIZE := Vector2(768.0, 256.0)
const TEXTURE_SIZE := 128
const TRANSITION_WIDTH := 220.0
const HEIGHT_BLEND_INFLUENCE := 3.0
const HEIGHT_BLEND_CONTRAST := 6.0


func _ready() -> void:
	_create_camera()
	_create_demo_row(
		"Regular mask blend",
		Vector2(96.0, 96.0),
		0.0,
		1.0
	)
	_create_demo_row(
		"Height-aware blend with high-contrast height maps",
		Vector2(96.0, 432.0),
		HEIGHT_BLEND_INFLUENCE,
		HEIGHT_BLEND_CONTRAST
	)
	_create_height_preview("Material A height: circles", Vector2(1080.0, 150.0), true)
	_create_height_preview("Material B height: squares", Vector2(1080.0, 470.0), false)


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
	surface.texture = _build_material_texture(true)
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
	material.set_shader_parameter("terrain_type_1_texture", _build_material_texture(true))
	material.set_shader_parameter("terrain_type_2_texture", _build_material_texture(false))
	material.set_shader_parameter("terrain_mask", _build_demo_mask())
	material.set_shader_parameter("terrain_type_1_height", _build_height_texture(true))
	material.set_shader_parameter("terrain_type_2_height", _build_height_texture(false))
	material.set_shader_parameter("terrain_world_origin", Vector2.ZERO)
	material.set_shader_parameter("terrain_world_size", SURFACE_SIZE)
	material.set_shader_parameter("texture_repeat_world_size", float(TEXTURE_SIZE))
	material.set_shader_parameter("height_blend_influence", height_influence)
	material.set_shader_parameter("height_blend_contrast", height_contrast)
	return material


func _build_material_texture(is_material_a: bool) -> Texture2D:
	var image := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var base_color := Color(0.40, 0.22, 0.08, 1.0) if is_material_a else Color(0.13, 0.55, 0.20, 1.0)
	var detail_color := Color(0.92, 0.70, 0.36, 1.0) if is_material_a else Color(0.72, 0.95, 0.28, 1.0)
	for y in range(TEXTURE_SIZE):
		for x in range(TEXTURE_SIZE):
			var high := _height_pattern(Vector2i(x, y), is_material_a) > 0.5
			var stripe := ((x / 16 + y / 16) % 2) == 0
			var color := detail_color if high else base_color
			if stripe:
				color = color.lerp(Color.WHITE, 0.08)
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


func _build_height_texture(is_material_a: bool) -> Texture2D:
	var image := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	for y in range(TEXTURE_SIZE):
		for x in range(TEXTURE_SIZE):
			var height_value := _height_pattern(Vector2i(x, y), is_material_a)
			image.set_pixel(x, y, Color(height_value, height_value, height_value, 1.0))
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


func _height_pattern(pixel: Vector2i, is_material_a: bool) -> float:
	var tile_origin := Vector2i((pixel.x / 32) * 32, (pixel.y / 32) * 32)
	var local_position := pixel - tile_origin
	if is_material_a:
		var circle_center := Vector2(16.0, 16.0)
		return 1.0 if Vector2(local_position).distance_to(circle_center) <= 10.0 else 0.0

	var is_square := local_position.x >= 7 and local_position.x <= 24 and local_position.y >= 7 and local_position.y <= 24
	return 1.0 if is_square else 0.0


func _create_height_preview(label_text: String, position: Vector2, is_material_a: bool) -> void:
	_create_label(label_text, position + Vector2(-96.0, -140.0), 18)
	var preview := Sprite2D.new()
	preview.name = label_text.replace(" ", "").replace(":", "")
	preview.position = position
	preview.texture = _build_height_texture(is_material_a)
	preview.scale = Vector2(1.75, 1.75)
	add_child(preview)


func _create_tile_boundary_marks(position: Vector2) -> void:
	var left_label_position := position + Vector2(80.0, SURFACE_SIZE.y + 12.0)
	var right_label_position := position + Vector2(SURFACE_SIZE.x - 190.0, SURFACE_SIZE.y + 12.0)
	_create_label("Material A tile: circles are high", left_label_position, 16)
	_create_label("Material B tile: squares are high", right_label_position, 16)


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
