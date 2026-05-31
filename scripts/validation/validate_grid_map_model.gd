extends SceneTree

const GridMapModelScript := preload("res://scripts/map/grid_map_model.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_run_checks()

	if _failures.is_empty():
		print("validate_grid_map_model.gd: all checks passed")
		quit(0)
	else:
		for failure in _failures:
			printerr(failure)
		quit(1)


func _run_checks() -> void:
	var model := GridMapModelScript.new()
	var load_result: Dictionary = model.load_from_file()
	_expect(load_result.ok, "prototype_map.json should load: %s" % load_result.get("error", ""))
	if not load_result.ok:
		return

	_expect(model.grid_width > 0, "prototype_map.json field grid_width must be positive")
	_expect(model.grid_height > 0, "prototype_map.json field grid_height must be positive")
	_expect(model.cell_size > 0, "prototype_map.json field cell_size must be positive")
	_expect(typeof(model.seed) == TYPE_INT, "prototype_map.json field seed must load as an integer")
	_expect(model.is_cell_in_bounds(model.player_spawn_cell), "prototype_map.json field player_spawn_cell must be in bounds")

	_verify_conversion(model)
	_verify_bounds(model)
	_verify_default_walkability(model)
	_verify_spawn_protection(model)
	_verify_rectangular_reservation(model)
	_verify_invalid_configs()


func _verify_conversion(model: RefCounted) -> void:
	var world_position: Vector2 = model.origin + Vector2(model.cell_size * 3 + 4, model.cell_size * 5 + 7)
	var cell_result: Dictionary = model.world_to_cell(world_position)
	_expect(cell_result.ok, "world_to_cell should accept in-bounds world position %s" % world_position)
	_expect(cell_result.get("cell") == Vector2i(3, 5), "world_to_cell expected cell (3, 5), got %s" % cell_result.get("cell"))

	var outside_result: Dictionary = model.world_to_cell(model.origin - Vector2.ONE)
	_expect(not outside_result.ok, "world_to_cell should reject world position outside map bounds")

	var center_result: Dictionary = model.cell_to_world(Vector2i(1, 1))
	var expected_center: Vector2 = model.origin + Vector2(1.5, 1.5) * float(model.cell_size)
	_expect(center_result.ok, "cell_to_world should accept in-bounds cell (1, 1)")
	_expect(center_result.get("world_position") == expected_center, "cell_to_world expected %s, got %s" % [expected_center, center_result.get("world_position")])


func _verify_bounds(model: RefCounted) -> void:
	_expect(model.is_cell_in_bounds(Vector2i.ZERO), "cell (0, 0) should be in bounds")
	_expect(model.is_cell_in_bounds(Vector2i(model.grid_width - 1, model.grid_height - 1)), "last map cell should be in bounds")
	_expect(not model.is_cell_in_bounds(Vector2i(-1, 0)), "cell (-1, 0) should be out of bounds")
	_expect(not model.is_cell_in_bounds(Vector2i(model.grid_width, 0)), "cell at grid_width should be out of bounds")
	_expect(model.is_world_position_in_bounds(model.origin), "world origin should be in bounds")

	var outside_world: Vector2 = model.origin + Vector2(model.grid_width * model.cell_size, 0)
	_expect(not model.is_world_position_in_bounds(outside_world), "world position on right edge outside grid should be out of bounds")


func _verify_default_walkability(model: RefCounted) -> void:
	var unmarked_cell := Vector2i(0, 0)
	if unmarked_cell == model.player_spawn_cell:
		unmarked_cell = Vector2i(1, 0)

	_expect(model.is_walkable(unmarked_cell), "unmarked in-bounds cell %s should be walkable" % unmarked_cell)


func _verify_spawn_protection(model: RefCounted) -> void:
	_expect(model.is_reserved(model.player_spawn_cell), "player_spawn_cell %s should be reserved" % model.player_spawn_cell)
	_expect(model.is_protected(model.player_spawn_cell), "player_spawn_cell %s should be protected" % model.player_spawn_cell)


func _verify_rectangular_reservation(model: RefCounted) -> void:
	var rect_origin := Vector2i(4, 4)
	var rect_size := Vector2i(2, 3)
	var reserve_result: Dictionary = model.reserve_rect(rect_origin, rect_size, "occupied")
	_expect(reserve_result.ok, "reserve_rect should accept valid rectangle: %s" % reserve_result.get("error", ""))
	for y in range(rect_origin.y, rect_origin.y + rect_size.y):
		for x in range(rect_origin.x, rect_origin.x + rect_size.x):
			_expect(model.is_occupied(Vector2i(x, y)), "reserve_rect should mark occupied cell (%d, %d)" % [x, y])

	var valid_cell := Vector2i(6, 6)
	var out_of_bounds_result: Dictionary = model.reserve_rect(valid_cell, Vector2i(model.grid_width, 1), "blocked")
	_expect(not out_of_bounds_result.ok, "reserve_rect should reject out-of-bounds rectangle")
	_expect(not model.is_blocked(valid_cell), "out-of-bounds reserve_rect should not partially mutate cell %s" % valid_cell)

	var protected_result: Dictionary = model.reserve_rect(model.player_spawn_cell, Vector2i.ONE, "occupied")
	_expect(not protected_result.ok, "reserve_rect should reject protected player_spawn_cell without overwrite")
	_expect(not model.is_occupied(model.player_spawn_cell), "failed protected reservation should not mutate player_spawn_cell to occupied")


func _verify_invalid_configs() -> void:
	var valid_config := {
		"grid_width": 4,
		"grid_height": 4,
		"cell_size": 16,
		"origin": {"x": 0, "y": 0},
		"seed": 1,
		"player_spawn_cell": {"x": 1, "y": 1},
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

	var invalid_spawn := valid_config.duplicate(true)
	invalid_spawn.player_spawn_cell = {"x": 99, "y": 1}
	_expect_invalid_config(invalid_spawn, "player_spawn_cell")


func _expect_invalid_config(config: Dictionary, field_name: String) -> void:
	var model := GridMapModelScript.new()
	var result: Dictionary = model.initialize_from_config(config, "invalid_%s" % field_name)
	_expect(not result.ok, "invalid config field %s should fail validation" % field_name)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
