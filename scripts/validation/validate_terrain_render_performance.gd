extends SceneTree

const TerrainGeneratorScript := preload("res://scripts/terrain/terrain_generator.gd")
const TerrainConfigScript := preload("res://scripts/terrain/terrain_config.gd")
const TerrainRendererScript := preload("res://scripts/terrain/terrain_renderer_2d.gd")
const TerrainMaterialCatalogScript := preload("res://scripts/terrain/terrain_material_catalog.gd")

const CONFIG_PATH := "res://data/terrain/prototype_terrain_config.json"

var _failures: Array[String] = []


func _initialize() -> void:
	await _run_checks()

	if _failures.is_empty():
		print("validate_terrain_render_performance.gd: all checks passed")
		quit(0)
	else:
		for failure in _failures:
			printerr(failure)
		quit(1)


func _run_checks() -> void:
	var config := TerrainConfigScript.new()
	var load_result: Dictionary = config.load_from_file(CONFIG_PATH)
	_expect(load_result.ok, "prototype_terrain_config.json should load for terrain performance validation: %s" % load_result.get("error", ""))
	if not load_result.ok:
		return

	var generator := TerrainGeneratorScript.new()
	var generate_result: Dictionary = generator.generate(config)
	_expect(generate_result.ok, "terrain generator should produce terrain data for terrain performance validation: %s" % generate_result.get("error", ""))
	if not generate_result.ok:
		return

	var renderer := TerrainRendererScript.new()
	get_root().add_child(renderer)
	var render_result: Dictionary = renderer.call("set_terrain_data", generate_result.terrain_data)
	_expect(render_result.ok, "terrain renderer should configure terrain data for performance validation: %s" % render_result.get("error", ""))
	if render_result.ok:
		_verify_performance_shape(renderer, generate_result.terrain_data)

	renderer.queue_free()
	await process_frame
	await process_frame


func _verify_performance_shape(renderer: Node, terrain_data: RefCounted) -> void:
	var terrain_cell_count := int(renderer.call("get_rendered_cell_count"))
	var terrain_draw_surfaces := int(renderer.call("get_draw_surface_count"))
	var terrain_mask_size: Vector2i = renderer.call("get_terrain_mask_size")
	var height_route := String(renderer.call("get_height_input_route"))
	var uses_shader_material := bool(renderer.call("uses_shader_material"))
	var runtime_texture_loading_mode := String(renderer.call("get_runtime_texture_loading_mode"))
	var expected_mask_size := Vector2i(
		terrain_data.grid_width * TerrainRendererScript.MASK_PIXELS_PER_CELL,
		terrain_data.grid_height * TerrainRendererScript.MASK_PIXELS_PER_CELL
	)

	print("terrain_render_performance_shape:")
	print("  terrain_cells: %d" % terrain_cell_count)
	print("  terrain_draw_surfaces: %d" % terrain_draw_surfaces)
	print("  terrain_mask_size: %s" % [terrain_mask_size])
	print("  terrain_height_route: %s" % height_route)
	print("  terrain_uses_shader_material: %s" % [uses_shader_material])
	print("  runtime_texture_loading_mode: %s" % runtime_texture_loading_mode)

	_expect(terrain_cell_count == terrain_data.cells.size(), "terrain renderer should report one rendered cell per generated terrain cell")
	_expect(terrain_draw_surfaces == 1, "normal terrain rendering should use exactly one bounded terrain draw surface")
	_expect(terrain_draw_surfaces < terrain_cell_count, "terrain draw surface count should not scale with terrain cell count")
	_expect(terrain_mask_size == expected_mask_size, "terrain blend mask size should match generated terrain grid and mask resolution")
	_expect(height_route == TerrainMaterialCatalogScript.HEIGHT_ROUTE_AUTHORED_TEXTURES, "terrain renderer should use authored height maps")
	_expect(uses_shader_material, "terrain renderer should use a ShaderMaterial")
	_expect(runtime_texture_loading_mode == "resource_loader_texture2d", "terrain renderer should use ResourceLoader Texture2D runtime texture loading")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
