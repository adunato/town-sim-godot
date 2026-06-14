extends SceneTree

const TerrainConfigScript := preload("res://scripts/terrain/terrain_config.gd")
const TerrainGeneratorScript := preload("res://scripts/terrain/terrain_generator.gd")
const TerrainCellScript := preload("res://scripts/terrain/terrain_cell.gd")
const CONFIG_PATH := "res://data/terrain/prototype_terrain_config.json"

var _failures: Array[String] = []


func _initialize() -> void:
	_run_checks()

	if _failures.is_empty():
		print("validate_terrain_generation.gd: all checks passed")
		quit(0)
	else:
		for failure in _failures:
			printerr(failure)
		quit(1)


func _run_checks() -> void:
	var config := TerrainConfigScript.new()
	var load_result: Dictionary = config.load_from_file(CONFIG_PATH)
	_expect(load_result.ok, "prototype_terrain_config.json should load: %s" % load_result.get("error", ""))
	if not load_result.ok:
		return

	_verify_config(config)

	var generator := TerrainGeneratorScript.new()
	var generate_result: Dictionary = generator.generate(config)
	_expect(generate_result.ok, "terrain generator should produce terrain data: %s" % generate_result.get("error", ""))
	if not generate_result.ok:
		return

	var terrain_data: RefCounted = generate_result.terrain_data
	_verify_generated_data(config, terrain_data)
	_verify_deterministic_generation(config, terrain_data)
	_verify_invalid_configs()
	_print_inspection_output(config, terrain_data)


func _verify_config(config: RefCounted) -> void:
	_expect(config.grid_width > 0, "prototype_terrain_config.json field grid_width must be positive")
	_expect(config.grid_height > 0, "prototype_terrain_config.json field grid_height must be positive")
	_expect(config.cell_size > 0, "prototype_terrain_config.json field cell_size must be positive")
	_expect(typeof(config.seed) == TYPE_INT, "prototype_terrain_config.json field seed must load as an integer")
	_expect(config.noise_scale > 0.0, "prototype_terrain_config.json field noise_scale must be positive")
	_expect(config.terrain_threshold >= -1.0 and config.terrain_threshold <= 1.0, "prototype_terrain_config.json field terrain_threshold must be between -1.0 and 1.0")


func _verify_generated_data(config: RefCounted, terrain_data: RefCounted) -> void:
	_expect(terrain_data.cells.size() == config.grid_width * config.grid_height, "terrain cell count should equal grid_width * grid_height")
	_expect(terrain_data.get_world_bounds() == config.get_world_bounds(), "terrain world bounds should match config world bounds")

	for cell in terrain_data.cells:
		_expect(config.is_cell_in_bounds(cell.coordinate), "generated terrain cell %s should be in bounds" % cell.coordinate)
		_expect(TerrainCellScript.is_known_terrain_type(cell.terrain_type), "generated terrain cell %s should use a known terrain type: %s" % [cell.coordinate, cell.terrain_type])
		var expected_type: String = TerrainCellScript.terrain_type_for_noise(cell.noise_value, config.terrain_threshold)
		_expect(cell.terrain_type == expected_type, "generated terrain cell %s terrain type should match threshold rule" % cell.coordinate)

		var footprint_result: Dictionary = config.cell_footprint(cell.coordinate)
		_expect(footprint_result.ok, "generated terrain cell %s should have a calculable footprint" % cell.coordinate)
		if footprint_result.ok:
			_expect(cell.footprint == footprint_result.footprint, "generated terrain cell %s footprint should match config-derived footprint" % cell.coordinate)

	var first_lookup: Dictionary = terrain_data.get_cell(Vector2i.ZERO)
	_expect(first_lookup.ok, "terrain data should look up generated cell (0, 0)")
	var outside_lookup: Dictionary = terrain_data.get_cell(Vector2i(config.grid_width, 0))
	_expect(not outside_lookup.ok, "terrain data should reject out-of-bounds cell lookup")


func _verify_deterministic_generation(config: RefCounted, first_data: RefCounted) -> void:
	var generator := TerrainGeneratorScript.new()
	var second_result: Dictionary = generator.generate(config)
	_expect(second_result.ok, "terrain generator should produce a second deterministic result: %s" % second_result.get("error", ""))
	if not second_result.ok:
		return

	var second_data: RefCounted = second_result.terrain_data
	_expect(second_data.cells.size() == first_data.cells.size(), "deterministic generation should produce the same cell count")
	if second_data.cells.size() != first_data.cells.size():
		return

	for index in range(first_data.cells.size()):
		var first_cell: RefCounted = first_data.cells[index]
		var second_cell: RefCounted = second_data.cells[index]
		_expect(first_cell.coordinate == second_cell.coordinate, "deterministic generation coordinate mismatch at index %d" % index)
		_expect(is_equal_approx(first_cell.noise_value, second_cell.noise_value), "deterministic generation noise mismatch at cell %s" % first_cell.coordinate)
		_expect(first_cell.terrain_type == second_cell.terrain_type, "deterministic generation terrain type mismatch at cell %s" % first_cell.coordinate)
		_expect(first_cell.footprint == second_cell.footprint, "deterministic generation footprint mismatch at cell %s" % first_cell.coordinate)


func _verify_invalid_configs() -> void:
	var valid_config := {
		"grid_width": 4,
		"grid_height": 4,
		"cell_size": 16,
		"origin": {"x": 0, "y": 0},
		"seed": 1,
		"noise_scale": 8.0,
		"terrain_threshold": 0.0,
	}

	var invalid_width := valid_config.duplicate(true)
	invalid_width.grid_width = 0
	_expect_invalid_config(invalid_width, "grid_width")

	var fractional_width := valid_config.duplicate(true)
	fractional_width.grid_width = 4.5
	_expect_invalid_config(fractional_width, "fractional_grid_width")

	var invalid_cell_size := valid_config.duplicate(true)
	invalid_cell_size.cell_size = 0
	_expect_invalid_config(invalid_cell_size, "cell_size")

	var invalid_seed := valid_config.duplicate(true)
	invalid_seed.seed = 1.25
	_expect_invalid_config(invalid_seed, "seed")

	var invalid_noise_scale := valid_config.duplicate(true)
	invalid_noise_scale.noise_scale = 0.0
	_expect_invalid_config(invalid_noise_scale, "noise_scale")

	var invalid_threshold := valid_config.duplicate(true)
	invalid_threshold.terrain_threshold = 2.0
	_expect_invalid_config(invalid_threshold, "terrain_threshold")

	var missing_origin := valid_config.duplicate(true)
	missing_origin.erase("origin")
	_expect_invalid_config(missing_origin, "origin")


func _expect_invalid_config(config: Dictionary, field_name: String) -> void:
	var terrain_config := TerrainConfigScript.new()
	var result: Dictionary = terrain_config.initialize_from_config(config, "invalid_%s" % field_name)
	_expect(not result.ok, "invalid terrain config field %s should fail validation" % field_name)
	if not result.ok:
		_expect(result.get("error", "").contains("Terrain config"), "invalid terrain config field %s should return a concrete error" % field_name)


func _print_inspection_output(config: RefCounted, terrain_data: RefCounted) -> void:
	var counts: Dictionary = terrain_data.count_by_terrain_type()
	print("Terrain config: %s" % CONFIG_PATH)
	print("Terrain grid: %dx%d cells, cell_size=%d, seed=%d, noise_scale=%.3f, threshold=%.3f" % [config.grid_width, config.grid_height, config.cell_size, config.seed, config.noise_scale, config.terrain_threshold])
	print("Terrain type counts: terrain_1=%d, terrain_2=%d" % [counts.get(TerrainCellScript.TERRAIN_TYPE_1, 0), counts.get(TerrainCellScript.TERRAIN_TYPE_2, 0)])
	print("Terrain row preview: %s" % " / ".join(terrain_data.terrain_type_row_preview()))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
