extends SceneTree

const TerrainConfigScript := preload("res://scripts/terrain/terrain_config.gd")
const TerrainGeneratorScript := preload("res://scripts/terrain/terrain_generator.gd")
const TerrainCellScript := preload("res://scripts/terrain/terrain_cell.gd")
const TerrainRendererScript := preload("res://scripts/terrain/terrain_renderer_2d.gd")

const CONFIG_PATH := "res://data/terrain/prototype_terrain_config.json"
const SAVED_HEIGHT_MAPS := [
	{
		"source": TerrainRendererScript.TERRAIN_TYPE_1_TEXTURE_PATH,
		"raw_height": "res://assets/Textures/derived_height/mud_height_from_diffuse.png",
		"contrast_preview": "res://assets/Textures/derived_height/mud_height_contrast_preview.png",
	},
	{
		"source": TerrainRendererScript.TERRAIN_TYPE_2_TEXTURE_PATH,
		"raw_height": "res://assets/Textures/derived_height/rocky_grass_height_from_diffuse.png",
		"contrast_preview": "res://assets/Textures/derived_height/rocky_grass_height_contrast_preview.png",
	},
]

var _failures: Array[String] = []


func _initialize() -> void:
	await _run_checks()

	if _failures.is_empty():
		print("validate_height_aware_terrain_blending.gd: all checks passed")
		quit(0)
	else:
		for failure in _failures:
			printerr(failure)
		quit(1)


func _run_checks() -> void:
	var config := TerrainConfigScript.new()
	var load_result: Dictionary = config.load_from_file(CONFIG_PATH)
	_expect(load_result.ok, "prototype_terrain_config.json should load for height-aware terrain validation: %s" % load_result.get("error", ""))
	if not load_result.ok:
		return

	var generator := TerrainGeneratorScript.new()
	var generate_result: Dictionary = generator.generate(config)
	_expect(generate_result.ok, "terrain generator should produce terrain data for height-aware blending: %s" % generate_result.get("error", ""))
	if not generate_result.ok:
		return

	var terrain_data: RefCounted = generate_result.terrain_data
	var renderer := TerrainRendererScript.new()
	get_root().add_child(renderer)
	var render_result: Dictionary = renderer.call("set_terrain_data", terrain_data)
	_expect(render_result.ok, "terrain renderer should configure height-aware terrain data: %s" % render_result.get("error", ""))
	if render_result.ok:
		_verify_height_route(renderer)
		_verify_saved_height_maps()
		_verify_shader_height_contract(renderer)
		_verify_height_aware_boundary_behavior(renderer)
		_verify_interior_stability(renderer)
		_verify_renderer_continuity(renderer)
		_verify_invalid_height_settings_failure(renderer)

	renderer.queue_free()
	await process_frame
	await process_frame


func _verify_height_route(renderer: Node) -> void:
	_expect(renderer.call("get_height_input_route") == TerrainRendererScript.HEIGHT_ROUTE_GENERATED_FROM_DIFFUSE, "height route should be generated from diffuse luminance")
	_expect(renderer.call("get_height_brightness_convention") == "diffuse_luminance_brighter_is_higher", "height brightness convention should document brighter texels as higher")

	var terrain_1_height: Texture2D = renderer.call("get_terrain_height_texture", TerrainCellScript.TERRAIN_TYPE_1)
	var terrain_2_height: Texture2D = renderer.call("get_terrain_height_texture", TerrainCellScript.TERRAIN_TYPE_2)
	_expect(terrain_1_height != null, "terrain_1 generated height texture should exist")
	_expect(terrain_2_height != null, "terrain_2 generated height texture should exist")
	_expect(renderer.call("get_terrain_height_texture_size", TerrainCellScript.TERRAIN_TYPE_1).x > 0, "terrain_1 generated height texture should have width")
	_expect(renderer.call("get_terrain_height_texture_size", TerrainCellScript.TERRAIN_TYPE_2).y > 0, "terrain_2 generated height texture should have height")

	var terrain_1_sample: Dictionary = renderer.call("get_generated_height_sample", TerrainCellScript.TERRAIN_TYPE_1, Vector2(0.25, 0.25))
	var terrain_2_sample: Dictionary = renderer.call("get_generated_height_sample", TerrainCellScript.TERRAIN_TYPE_2, Vector2(0.25, 0.25))
	_expect(terrain_1_sample.ok, "terrain_1 generated height sample should be readable: %s" % terrain_1_sample.get("error", ""))
	_expect(terrain_2_sample.ok, "terrain_2 generated height sample should be readable: %s" % terrain_2_sample.get("error", ""))
	if terrain_1_sample.ok:
		_expect(float(terrain_1_sample.value) >= 0.0 and float(terrain_1_sample.value) <= 1.0, "terrain_1 generated height sample should be normalized")
	if terrain_2_sample.ok:
		_expect(float(terrain_2_sample.value) >= 0.0 and float(terrain_2_sample.value) <= 1.0, "terrain_2 generated height sample should be normalized")


func _verify_saved_height_maps() -> void:
	for height_map: Dictionary in SAVED_HEIGHT_MAPS:
		var source_path: String = height_map.source
		var raw_height_path: String = height_map.raw_height
		var contrast_preview_path: String = height_map.contrast_preview
		_expect(FileAccess.file_exists(raw_height_path), "saved raw height map should exist: %s" % raw_height_path)
		_expect(FileAccess.file_exists(contrast_preview_path), "saved contrast-preview height map should exist: %s" % contrast_preview_path)
		if not FileAccess.file_exists(raw_height_path):
			continue

		var source_image := Image.new()
		var source_load_result := source_image.load(source_path)
		_expect(source_load_result == OK, "source diffuse texture should load for saved height validation: %s" % source_path)
		var height_image := Image.new()
		var height_load_result := height_image.load(raw_height_path)
		_expect(height_load_result == OK, "saved raw height map should load: %s" % raw_height_path)
		if source_load_result != OK or height_load_result != OK:
			continue

		_expect(height_image.get_size() == source_image.get_size(), "saved raw height map dimensions should match source texture for %s" % source_path)
		_verify_saved_height_samples(source_image, height_image, raw_height_path)


func _verify_saved_height_samples(source_image: Image, height_image: Image, height_path: String) -> void:
	var sample_points := [
		Vector2i(0, 0),
		Vector2i(source_image.get_width() / 4, source_image.get_height() / 4),
		Vector2i(source_image.get_width() / 2, source_image.get_height() / 2),
		Vector2i((source_image.get_width() * 3) / 4, (source_image.get_height() * 3) / 4),
		Vector2i(source_image.get_width() - 1, source_image.get_height() - 1),
	]
	for sample_point in sample_points:
		var source_color := source_image.get_pixel(sample_point.x, sample_point.y)
		var expected_luminance := source_color.r * 0.2126 + source_color.g * 0.7152 + source_color.b * 0.0722
		var actual_height := height_image.get_pixel(sample_point.x, sample_point.y).r
		_expect(
			absf(expected_luminance - actual_height) <= 0.005,
			"saved raw height map %s sample %s should match diffuse luminance, expected %.4f got %.4f" % [height_path, sample_point, expected_luminance, actual_height]
		)


func _verify_shader_height_contract(renderer: Node) -> void:
	_expect(renderer.call("get_shader_parameter_value", &"terrain_mask") != null, "terrain shader should receive the regular blend mask")
	_expect(renderer.call("get_shader_parameter_value", &"terrain_type_1_height") != null, "terrain shader should receive terrain_1 height input")
	_expect(renderer.call("get_shader_parameter_value", &"terrain_type_2_height") != null, "terrain shader should receive terrain_2 height input")
	_expect(renderer.call("get_shader_parameter_value", &"height_blend_influence") == renderer.get("height_blend_influence"), "terrain shader should receive height_blend_influence")
	_expect(renderer.call("get_shader_parameter_value", &"height_blend_contrast") == renderer.get("height_blend_contrast"), "terrain shader should receive height_blend_contrast")

	var shader_text := FileAccess.get_file_as_string("res://shaders/terrain/terrain_binary_mask.gdshader")
	_expect(shader_text.contains("terrain_type_1_height"), "terrain shader source should declare terrain_1 height input")
	_expect(shader_text.contains("terrain_type_2_height"), "terrain shader source should declare terrain_2 height input")
	_expect(shader_text.contains("height_aware_mask"), "terrain shader source should use height-aware mask logic")


func _verify_height_aware_boundary_behavior(renderer: Node) -> void:
	var height_pair := _find_generated_height_contrast(renderer)
	_expect(height_pair.ok, "generated diffuse-derived height inputs should contain suitable contrast: %s" % height_pair.get("error", ""))
	if not height_pair.ok:
		return

	var regular_mask := 0.5
	var adjusted_mask: float = renderer.call("get_height_aware_mask_value", regular_mask, height_pair.terrain_1_height, height_pair.terrain_2_height)
	_expect(not is_equal_approx(adjusted_mask, regular_mask), "height-aware alpha should modify a boundary mask when generated height contrast exists")
	_expect(adjusted_mask >= 0.0 and adjusted_mask <= 1.0, "height-aware boundary mask should stay normalized")


func _find_generated_height_contrast(renderer: Node) -> Dictionary:
	var terrain_1_height: Texture2D = renderer.call("get_terrain_height_texture", TerrainCellScript.TERRAIN_TYPE_1)
	var terrain_2_height: Texture2D = renderer.call("get_terrain_height_texture", TerrainCellScript.TERRAIN_TYPE_2)
	if terrain_1_height == null or terrain_2_height == null:
		return {"ok": false, "error": "height textures are missing"}

	var terrain_1_image := terrain_1_height.get_image()
	var terrain_2_image := terrain_2_height.get_image()
	var sample_width: int = min(terrain_1_image.get_width(), terrain_2_image.get_width())
	var sample_height: int = min(terrain_1_image.get_height(), terrain_2_image.get_height())
	for y in range(sample_height):
		for x in range(sample_width):
			var terrain_1_value := terrain_1_image.get_pixel(x, y).r
			var terrain_2_value := terrain_2_image.get_pixel(x, y).r
			if absf(terrain_2_value - terrain_1_value) > 0.03:
				return {
					"ok": true,
					"terrain_1_height": terrain_1_value,
					"terrain_2_height": terrain_2_value,
				}

	return {"ok": false, "error": "no sampled height pair differed by more than 0.03"}


func _verify_interior_stability(renderer: Node) -> void:
	var terrain_1_result: float = renderer.call("get_height_aware_mask_value", 0.0, 0.0, 1.0)
	var terrain_2_result: float = renderer.call("get_height_aware_mask_value", 1.0, 1.0, 0.0)
	_expect(is_equal_approx(terrain_1_result, 0.0), "height data should not replace stable terrain_1 interiors")
	_expect(is_equal_approx(terrain_2_result, 1.0), "height data should not replace stable terrain_2 interiors")


func _verify_renderer_continuity(renderer: Node) -> void:
	_expect(renderer is Polygon2D, "terrain renderer should remain one Polygon2D terrain draw surface")
	_expect(renderer.call("get_draw_surface_count") == 1, "height-aware terrain renderer should keep one normal draw surface")
	_expect(renderer.call("uses_shader_material"), "height-aware terrain renderer should keep using ShaderMaterial")

	var renderer_script_text := FileAccess.get_file_as_string("res://scripts/terrain/terrain_renderer_2d.gd")
	_expect(not renderer_script_text.contains("func _draw("), "height-aware renderer should not implement per-cell custom _draw rendering")
	_expect(not renderer_script_text.contains("draw_texture_rect"), "height-aware renderer should not issue per-cell texture draw calls")


func _verify_invalid_height_settings_failure(renderer: Node) -> void:
	var original_influence: float = renderer.get("height_blend_influence")
	renderer.set("height_blend_influence", 3.5)
	var validation: Dictionary = renderer.call("validate_height_settings")
	_expect(not validation.ok, "terrain renderer validation should fail when height_blend_influence is outside 0.0 to 3.0")
	_expect(String(validation.get("error", "")).contains("height_blend_influence"), "invalid height influence error should name height_blend_influence")
	renderer.set("height_blend_influence", original_influence)

	var original_contrast: float = renderer.get("height_blend_contrast")
	renderer.set("height_blend_contrast", 0.0)
	validation = renderer.call("validate_height_settings")
	_expect(not validation.ok, "terrain renderer validation should fail when height_blend_contrast is not positive")
	_expect(String(validation.get("error", "")).contains("height_blend_contrast"), "invalid height contrast error should name height_blend_contrast")
	renderer.set("height_blend_contrast", original_contrast)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
