extends SceneTree

const TerrainConfigScript := preload("res://scripts/terrain/terrain_config.gd")
const TerrainGeneratorScript := preload("res://scripts/terrain/terrain_generator.gd")
const TerrainCellScript := preload("res://scripts/terrain/terrain_cell.gd")
const TerrainRendererScript := preload("res://scripts/terrain/terrain_renderer_2d.gd")
const MainScene := preload("res://scenes/main.tscn")

const CONFIG_PATH := "res://data/terrain/prototype_terrain_config.json"

var _failures: Array[String] = []


func _initialize() -> void:
	await _run_checks()

	if _failures.is_empty():
		print("validate_basic_terrain_rendering.gd: all checks passed")
		quit(0)
	else:
		for failure in _failures:
			printerr(failure)
		quit(1)


func _run_checks() -> void:
	var config := TerrainConfigScript.new()
	var load_result: Dictionary = config.load_from_file(CONFIG_PATH)
	_expect(load_result.ok, "prototype_terrain_config.json should load for terrain rendering validation: %s" % load_result.get("error", ""))
	if not load_result.ok:
		return

	var generator := TerrainGeneratorScript.new()
	var generate_result: Dictionary = generator.generate(config)
	_expect(generate_result.ok, "terrain generator should produce terrain data for rendering: %s" % generate_result.get("error", ""))
	if not generate_result.ok:
		return

	var terrain_data: RefCounted = generate_result.terrain_data
	var renderer := TerrainRendererScript.new()
	get_root().add_child(renderer)
	renderer.set_terrain_data(terrain_data)

	_verify_texture_inputs(renderer)
	_verify_generated_data_consumption(renderer, terrain_data)
	_verify_geometry(renderer, config, terrain_data)
	_verify_terrain_type_mapping(renderer, terrain_data)
	_verify_mask_contract(renderer, terrain_data)
	_verify_blend_mask_determinism(terrain_data, renderer)
	_verify_shader_surface_contract(renderer)
	_verify_texture_repeat_mapping(renderer)
	await _verify_startup_scene_runs()
	_verify_missing_texture_failure(renderer)
	_verify_invalid_blend_width_failure(renderer)

	renderer.queue_free()
	await process_frame
	await process_frame


func _verify_texture_inputs(renderer: Node) -> void:
	var validation: Dictionary = renderer.call("validate_texture_inputs", true)
	_expect(validation.ok, "terrain renderer should have texture inputs for both terrain types: %s" % validation.get("error", ""))
	_expect(FileAccess.file_exists(TerrainRendererScript.TERRAIN_TYPE_1_TEXTURE_PATH), "terrain_1 texture file should exist: %s" % TerrainRendererScript.TERRAIN_TYPE_1_TEXTURE_PATH)
	_expect(FileAccess.file_exists(TerrainRendererScript.TERRAIN_TYPE_2_TEXTURE_PATH), "terrain_2 texture file should exist: %s" % TerrainRendererScript.TERRAIN_TYPE_2_TEXTURE_PATH)
	_expect(renderer.call("get_texture_for_terrain_type", TerrainCellScript.TERRAIN_TYPE_1) != null, "terrain_1 should resolve to a Texture2D")
	_expect(renderer.call("get_texture_for_terrain_type", TerrainCellScript.TERRAIN_TYPE_2) != null, "terrain_2 should resolve to a Texture2D")


func _verify_generated_data_consumption(renderer: Node, terrain_data: RefCounted) -> void:
	_expect(renderer.call("has_terrain_data"), "terrain renderer should receive generated terrain data")
	_expect(renderer.call("get_rendered_cell_count") == terrain_data.cells.size(), "terrain renderer should expose one rendered cell per generated cell")


func _verify_geometry(renderer: Node, config: RefCounted, terrain_data: RefCounted) -> void:
	_expect(renderer.call("get_rendered_bounds") == terrain_data.get_world_bounds(), "terrain renderer bounds should match generated terrain bounds")
	_expect(renderer.call("get_rendered_bounds") == config.get_world_bounds(), "terrain renderer bounds should match terrain config world bounds")

	for cell in terrain_data.cells:
		var rect_result: Dictionary = renderer.call("get_cell_draw_rect", cell.coordinate)
		_expect(rect_result.ok, "terrain renderer should expose draw rect for generated cell %s: %s" % [cell.coordinate, rect_result.get("error", "")])
		if rect_result.ok:
			_expect(rect_result.rect == cell.footprint, "terrain renderer draw rect should match generated footprint for cell %s" % cell.coordinate)
			_expect(rect_result.rect.size == Vector2.ONE * float(config.cell_size), "terrain renderer cell %s should draw at configured cell size" % cell.coordinate)


func _verify_terrain_type_mapping(renderer: Node, terrain_data: RefCounted) -> void:
	var counts: Dictionary = terrain_data.count_by_terrain_type()
	_expect(int(counts.get(TerrainCellScript.TERRAIN_TYPE_1, 0)) > 0, "fixture terrain data should include at least one terrain_1 cell")
	_expect(int(counts.get(TerrainCellScript.TERRAIN_TYPE_2, 0)) > 0, "fixture terrain data should include at least one terrain_2 cell")
	_expect(renderer.call("get_texture_path_for_terrain_type", TerrainCellScript.TERRAIN_TYPE_1).ends_with("mud.png"), "terrain_1 should use mud.png")
	_expect(renderer.call("get_texture_path_for_terrain_type", TerrainCellScript.TERRAIN_TYPE_2).ends_with("rocky_grass.png"), "terrain_2 should use rocky_grass.png")


func _verify_mask_contract(renderer: Node, terrain_data: RefCounted) -> void:
	var mask_texture: Texture2D = renderer.call("get_terrain_mask_texture")
	_expect(mask_texture != null, "terrain renderer should generate a softened terrain blend mask texture")
	var expected_mask_size := Vector2i(
		terrain_data.grid_width * TerrainRendererScript.MASK_PIXELS_PER_CELL,
		terrain_data.grid_height * TerrainRendererScript.MASK_PIXELS_PER_CELL
	)
	_expect(renderer.call("get_terrain_mask_size") == expected_mask_size, "terrain blend mask dimensions should scale from generated terrain grid")
	if mask_texture == null:
		return

	var mask_image := mask_texture.get_image()
	var terrain_1_region_count := 0
	var terrain_2_region_count := 0
	for cell in terrain_data.cells:
		var lookup_result: Dictionary = renderer.call("get_terrain_mask_value", cell.coordinate)
		_expect(lookup_result.ok, "terrain renderer should expose blend mask value for generated cell %s: %s" % [cell.coordinate, lookup_result.get("error", "")])
		var mask_value := 0.0
		if lookup_result.ok:
			mask_value = float(lookup_result.value)

		if cell.terrain_type == TerrainCellScript.TERRAIN_TYPE_1:
			_expect(mask_value < 0.5, "terrain blend mask cell %s should identify terrain_1" % cell.coordinate)
			terrain_1_region_count += 1
		elif cell.terrain_type == TerrainCellScript.TERRAIN_TYPE_2:
			_expect(mask_value >= 0.5, "terrain blend mask cell %s should identify terrain_2" % cell.coordinate)
			terrain_2_region_count += 1

	var sample_uv_result: Dictionary = renderer.call("get_cell_mask_uv_rect", Vector2i.ZERO)
	_expect(sample_uv_result.ok, "terrain renderer should expose mask UV rect for cell (0, 0)")
	if sample_uv_result.ok:
		var expected_size := Vector2(1.0 / float(terrain_data.grid_width), 1.0 / float(terrain_data.grid_height))
		_expect(sample_uv_result.rect.position == Vector2.ZERO, "cell (0, 0) mask UV rect should start at UV origin")
		_expect(sample_uv_result.rect.size == expected_size, "cell mask UV rect size should match one terrain mask texel")

	_expect(terrain_1_region_count > 0, "terrain blend mask should include terrain_1 region values")
	_expect(terrain_2_region_count > 0, "terrain blend mask should include terrain_2 region values")
	_expect(_mask_has_transition_pixels(mask_image), "terrain blend mask should include intermediate transition values near terrain boundaries")


func _mask_has_transition_pixels(mask_image: Image) -> bool:
	for y in range(mask_image.get_height()):
		for x in range(mask_image.get_width()):
			var mask_value := mask_image.get_pixel(x, y).r
			if mask_value > 0.0 and mask_value < 1.0:
				return true

	return false


func _verify_blend_mask_determinism(terrain_data: RefCounted, renderer: Node) -> void:
	var second_renderer := TerrainRendererScript.new()
	second_renderer.set("blend_width_cells", renderer.get("blend_width_cells"))
	get_root().add_child(second_renderer)
	var second_result: Dictionary = second_renderer.call("set_terrain_data", terrain_data)
	_expect(second_result.ok, "second terrain renderer should generate deterministic blend mask: %s" % second_result.get("error", ""))
	if not second_result.ok:
		second_renderer.queue_free()
		return

	var first_mask: Texture2D = renderer.call("get_terrain_mask_texture")
	var second_mask: Texture2D = second_renderer.call("get_terrain_mask_texture")
	_expect(first_mask != null and second_mask != null, "deterministic blend mask comparison should have two generated masks")
	if first_mask != null and second_mask != null:
		var first_image := first_mask.get_image()
		var second_image := second_mask.get_image()
		_expect(first_image.get_size() == second_image.get_size(), "deterministic blend masks should have matching dimensions")
		for cell in terrain_data.cells:
			var sample_pixel := Vector2i(
				cell.coordinate.x * TerrainRendererScript.MASK_PIXELS_PER_CELL + TerrainRendererScript.MASK_PIXELS_PER_CELL / 2,
				cell.coordinate.y * TerrainRendererScript.MASK_PIXELS_PER_CELL + TerrainRendererScript.MASK_PIXELS_PER_CELL / 2
			)
			var first_value := first_image.get_pixel(sample_pixel.x, sample_pixel.y).r
			var second_value := second_image.get_pixel(sample_pixel.x, sample_pixel.y).r
			_expect(is_equal_approx(first_value, second_value), "deterministic blend mask mismatch at cell %s" % cell.coordinate)

	second_renderer.queue_free()


func _verify_shader_surface_contract(renderer: Node) -> void:
	_expect(renderer is Polygon2D, "terrain renderer should be one Polygon2D terrain draw surface")
	_expect(renderer.call("get_draw_surface_count") == 1, "terrain renderer should expose one normal terrain draw surface")
	_expect(renderer.call("uses_shader_material"), "terrain renderer should use a ShaderMaterial")
	_expect(renderer.get("polygon").size() == 4, "terrain renderer polygon should use one terrain-sized quad")
	_expect(renderer.get("material") != null, "terrain renderer should assign its shader material")
	_expect(renderer.call("get_shader_parameter_value", &"terrain_type_1_texture") != null, "terrain shader should receive terrain_1 texture")
	_expect(renderer.call("get_shader_parameter_value", &"terrain_type_2_texture") != null, "terrain shader should receive terrain_2 texture")
	_expect(renderer.call("get_shader_parameter_value", &"terrain_mask") != null, "terrain shader should receive terrain blend mask")

	var renderer_script_text := FileAccess.get_file_as_string("res://scripts/terrain/terrain_renderer_2d.gd")
	_expect(not renderer_script_text.contains("func _draw("), "terrain renderer should not implement per-cell custom _draw rendering")
	_expect(not renderer_script_text.contains("draw_texture_rect"), "terrain renderer should not issue per-cell texture draw calls")


func _verify_texture_repeat_mapping(renderer: Node) -> void:
	var rect := Rect2(Vector2(32, 64), Vector2(32, 32))
	var first_region: Rect2 = renderer.call("get_texture_region_for_rect", rect)
	var second_region: Rect2 = renderer.call("get_texture_region_for_rect", rect)
	_expect(first_region == second_region, "texture coordinate mapping should be stable for the same world-space rect")
	_expect(first_region.position != Vector2.ZERO, "texture coordinate mapping should derive UV offset from world-space position")
	_expect(first_region.size.x > 0.0 and first_region.size.y > 0.0, "texture coordinate mapping should produce positive UV size")


func _verify_startup_scene_runs() -> void:
	var scene := MainScene.instantiate()
	get_root().add_child(scene)
	await process_frame

	_expect(scene.has_node("World/Terrain"), "main scene should contain World/Terrain terrain renderer")
	var terrain := scene.get_node("World/Terrain")
	_expect(terrain.get_script() == TerrainRendererScript, "World/Terrain should use terrain_renderer_2d.gd")
	_expect(terrain is Polygon2D, "World/Terrain should be a Polygon2D shader surface")
	_expect(terrain.call("has_terrain_data"), "startup scene terrain renderer should have generated terrain data")
	_expect(terrain.call("get_rendered_cell_count") > 0, "startup scene terrain renderer should expose generated terrain cells")
	_expect(terrain.call("get_draw_surface_count") == 1, "startup scene terrain renderer should use one draw surface")
	_expect(terrain.z_index > scene.get_node("World/Map").z_index, "terrain renderer should draw above the prototype map background")
	_expect(terrain.z_index < scene.get_node("World/DebugOverlay").z_index, "terrain renderer should draw below the debug overlay")

	scene.queue_free()
	await process_frame
	await process_frame


func _verify_missing_texture_failure(renderer: Node) -> void:
	var original_texture: Texture2D = renderer.get("terrain_type_1_texture")
	renderer.set("terrain_type_1_texture", null)
	var validation: Dictionary = renderer.call("validate_texture_inputs", false)
	_expect(not validation.ok, "terrain renderer validation should fail when terrain_1 texture is missing")
	_expect(String(validation.get("error", "")).contains("terrain_1"), "missing terrain texture error should name terrain_1")
	renderer.set("terrain_type_1_texture", original_texture)


func _verify_invalid_blend_width_failure(renderer: Node) -> void:
	var original_blend_width: float = renderer.get("blend_width_cells")
	renderer.set("blend_width_cells", 0.0)
	var validation: Dictionary = renderer.call("validate_blend_settings")
	_expect(not validation.ok, "terrain renderer validation should fail when blend_width_cells is not positive")
	_expect(String(validation.get("error", "")).contains("blend_width_cells"), "invalid blend width error should name blend_width_cells")
	renderer.set("blend_width_cells", original_blend_width)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
