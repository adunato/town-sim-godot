extends SceneTree

const TerrainConfigScript := preload("res://scripts/terrain/terrain_config.gd")
const TerrainGeneratorScript := preload("res://scripts/terrain/terrain_generator.gd")
const TerrainCellScript := preload("res://scripts/terrain/terrain_cell.gd")
const TerrainRendererScript := preload("res://scripts/terrain/terrain_renderer_2d.gd")
const TerrainMaterialCatalogScript := preload("res://scripts/terrain/terrain_material_catalog.gd")

const CONFIG_PATH := "res://data/terrain/prototype_terrain_config.json"

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
		_verify_authored_height_maps(renderer)
		_verify_shader_height_contract(renderer)
		_verify_height_aware_boundary_behavior(renderer)
		_verify_interior_stability(renderer)
		_verify_renderer_continuity(renderer)
		_verify_live_height_setting_updates(renderer)
		_verify_invalid_height_settings_failure(renderer)

	renderer.queue_free()
	await process_frame
	await process_frame


func _verify_height_route(renderer: Node) -> void:
	_expect(renderer.call("get_height_input_route") == TerrainMaterialCatalogScript.HEIGHT_ROUTE_AUTHORED_TEXTURES, "height route should use authored texture maps")
	_expect(renderer.call("get_height_brightness_convention") == "brighter_is_higher", "height brightness convention should document brighter texels as higher")

	var terrain_1_height: Texture2D = renderer.call("get_terrain_height_texture", TerrainCellScript.TERRAIN_TYPE_1)
	var terrain_2_height: Texture2D = renderer.call("get_terrain_height_texture", TerrainCellScript.TERRAIN_TYPE_2)
	_expect(terrain_1_height != null, "terrain_1 authored height texture should exist")
	_expect(terrain_2_height != null, "terrain_2 authored height texture should exist")
	_expect(renderer.call("get_terrain_height_texture_size", TerrainCellScript.TERRAIN_TYPE_1).x > 0, "terrain_1 authored height texture should have width")
	_expect(renderer.call("get_terrain_height_texture_size", TerrainCellScript.TERRAIN_TYPE_2).y > 0, "terrain_2 authored height texture should have height")

	var terrain_1_sample: Dictionary = renderer.call("get_height_sample", TerrainCellScript.TERRAIN_TYPE_1, Vector2(0.25, 0.25))
	var terrain_2_sample: Dictionary = renderer.call("get_height_sample", TerrainCellScript.TERRAIN_TYPE_2, Vector2(0.25, 0.25))
	_expect(terrain_1_sample.ok, "terrain_1 authored height sample should be readable: %s" % terrain_1_sample.get("error", ""))
	_expect(terrain_2_sample.ok, "terrain_2 authored height sample should be readable: %s" % terrain_2_sample.get("error", ""))
	if terrain_1_sample.ok:
		_expect(float(terrain_1_sample.value) >= 0.0 and float(terrain_1_sample.value) <= 1.0, "terrain_1 authored height sample should be normalized")
	if terrain_2_sample.ok:
		_expect(float(terrain_2_sample.value) >= 0.0 and float(terrain_2_sample.value) <= 1.0, "terrain_2 authored height sample should be normalized")


func _verify_authored_height_maps(renderer: Node) -> void:
	var catalog := TerrainMaterialCatalogScript.new()
	var catalog_result: Dictionary = catalog.load_from_file()
	_expect(catalog_result.ok, "terrain material catalog should load for height map validation: %s" % catalog_result.get("error", ""))
	if not catalog_result.ok:
		return

	for terrain_type in [TerrainCellScript.TERRAIN_TYPE_1, TerrainCellScript.TERRAIN_TYPE_2]:
		var material_entry: Dictionary = catalog.get_material_for_terrain_type(terrain_type)
		var height_path: String = material_entry.height_path
		_expect(FileAccess.file_exists(height_path), "authored height map should exist: %s" % height_path)
		if not FileAccess.file_exists(height_path):
			continue

		var height_image := Image.new()
		var height_load_result := height_image.load(height_path)
		_expect(height_load_result == OK, "authored height map should load: %s" % height_path)
		if height_load_result != OK:
			continue

		var renderer_height_texture: Texture2D = renderer.call("get_terrain_height_texture", terrain_type)
		_expect(renderer_height_texture != null, "renderer should expose authored height map for %s" % terrain_type)
		if renderer_height_texture != null:
			_expect(Vector2i(renderer_height_texture.get_size()) == height_image.get_size(), "renderer height texture size should match authored map %s" % height_path)
		_verify_authored_height_samples(height_image, height_path)


func _verify_authored_height_samples(height_image: Image, height_path: String) -> void:
	var sample_points := [
		Vector2i(0, 0),
		Vector2i(height_image.get_width() / 4, height_image.get_height() / 4),
		Vector2i(height_image.get_width() / 2, height_image.get_height() / 2),
		Vector2i((height_image.get_width() * 3) / 4, (height_image.get_height() * 3) / 4),
		Vector2i(height_image.get_width() - 1, height_image.get_height() - 1),
	]
	for sample_point in sample_points:
		var actual_height := height_image.get_pixel(sample_point.x, sample_point.y).r
		_expect(
			actual_height >= 0.0 and actual_height <= 1.0,
			"authored height map %s sample %s should be normalized, got %.4f" % [height_path, sample_point, actual_height]
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
	_expect(height_pair.ok, "authored height inputs should contain suitable contrast: %s" % height_pair.get("error", ""))
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


func _verify_live_height_setting_updates(renderer: Node) -> void:
	var original_influence: float = renderer.get("height_blend_influence")
	var original_contrast: float = renderer.get("height_blend_contrast")

	renderer.set("height_blend_influence", 0.35)
	renderer.set("height_blend_contrast", 2.25)
	_expect(
		is_equal_approx(float(renderer.call("get_shader_parameter_value", &"height_blend_influence")), 0.35),
		"changing height_blend_influence at runtime should update the shader parameter"
	)
	_expect(
		is_equal_approx(float(renderer.call("get_shader_parameter_value", &"height_blend_contrast")), 2.25),
		"changing height_blend_contrast at runtime should update the shader parameter"
	)

	renderer.set("height_blend_influence", original_influence)
	renderer.set("height_blend_contrast", original_contrast)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
