extends SceneTree

const BuildingDataRegistryScript := preload("res://scripts/buildings/building_data_registry.gd")
const GridMapModelScript := preload("res://scripts/map/grid_map_model.gd")
const MapRendererScript := preload("res://scripts/map/map_renderer.gd")
const ProceduralBuildingPlacerScript := preload("res://scripts/buildings/procedural_building_placer.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_run_checks()

	if _failures.is_empty():
		print("validate_procedural_building_placement.gd: all checks passed")
		quit(0)
	else:
		for failure in _failures:
			printerr(failure)
		quit(1)


func _run_checks() -> void:
	var registry := BuildingDataRegistryScript.new()
	var load_result: Dictionary = registry.load_definitions()
	_expect(load_result.ok, "building definitions should load: %s" % load_result.get("error", ""))
	if not load_result.ok:
		return

	_verify_default_map_configuration(registry)
	_verify_deterministic_output(registry)
	_verify_seed_variation(registry)
	_verify_invalid_configurations(registry)
	_verify_counts_and_footprints(registry)
	_verify_rejection_and_failure_behavior(registry)
	_verify_spawn_escape(registry)
	_verify_renderer_contract(registry)


func _verify_default_map_configuration(registry: RefCounted) -> void:
	var model := GridMapModelScript.new()
	var load_result: Dictionary = model.load_from_file()
	_expect(load_result.ok, "prototype_map.json should load: %s" % load_result.get("error", ""))
	if not load_result.ok:
		return

	var config: Dictionary = model.building_placement_config
	var placer := ProceduralBuildingPlacerScript.new()
	var validation: Dictionary = placer.validate_placement_config(config, registry)
	_expect(validation.ok, "prototype_map.json building_placement should validate: %s" % validation.get("error", ""))


func _verify_deterministic_output(registry: RefCounted) -> void:
	var config := _placement_config([["town_hall", 1], ["bakery", 2], ["house", 2]], 1, 200, 1)
	var first := _run_placement(registry, _map_config(20, 20, 1234, Vector2i(10, 10), config))
	var second := _run_placement(registry, _map_config(20, 20, 1234, Vector2i(10, 10), config))
	_expect(first.ok, "first deterministic placement should succeed: %s" % first.get("error", ""))
	_expect(second.ok, "second deterministic placement should succeed: %s" % second.get("error", ""))
	if first.ok and second.ok:
		_expect(first.instances == second.instances, "same seed and config should produce identical ordered instances")


func _verify_seed_variation(registry: RefCounted) -> void:
	var config := _placement_config([["house", 4]], 1, 200, 1)
	var first := _run_placement(registry, _map_config(20, 20, 1, Vector2i(10, 10), config))
	var second := _run_placement(registry, _map_config(20, 20, 2, Vector2i(10, 10), config))
	_expect(first.ok, "first seed variation placement should succeed: %s" % first.get("error", ""))
	_expect(second.ok, "second seed variation placement should succeed: %s" % second.get("error", ""))
	if first.ok and second.ok:
		_expect(first.instances != second.instances, "different seeds should vary generated placement when map space allows")


func _verify_invalid_configurations(registry: RefCounted) -> void:
	var placer := ProceduralBuildingPlacerScript.new()
	var valid := _placement_config([["house", 1]], 1, 20, 1)
	_expect(placer.validate_placement_config(valid, registry).ok, "fixture placement config should validate")

	var negative_count := valid.duplicate(true)
	negative_count.requested_models[0].count = -1
	_expect(not placer.validate_placement_config(negative_count, registry).ok, "negative requested model count should fail validation")

	var unknown_id := valid.duplicate(true)
	unknown_id.requested_models[0].definition_id = "unknown_model"
	_expect(not placer.validate_placement_config(unknown_id, registry).ok, "unknown definition id should fail validation")

	var negative_spacing := valid.duplicate(true)
	negative_spacing.minimum_building_spacing = -1
	_expect(not placer.validate_placement_config(negative_spacing, registry).ok, "negative minimum spacing should fail validation")

	var negative_retry := valid.duplicate(true)
	negative_retry.retry_limit = -1
	_expect(not placer.validate_placement_config(negative_retry, registry).ok, "negative retry limit should fail validation")

	var negative_clearance := valid.duplicate(true)
	negative_clearance.spawn_clearance = -1
	_expect(not placer.validate_placement_config(negative_clearance, registry).ok, "negative spawn clearance should fail validation")

	var zero_retry_with_buildings := valid.duplicate(true)
	zero_retry_with_buildings.retry_limit = 0
	_expect(not placer.validate_placement_config(zero_retry_with_buildings, registry).ok, "zero retry limit with requested buildings should fail validation")

	var zero_buildings := _placement_config([["house", 0]], 1, 0, 1)
	_expect(placer.validate_placement_config(zero_buildings, registry).ok, "zero total building count should validate")


func _verify_counts_and_footprints(registry: RefCounted) -> void:
	var config := _placement_config([["town_hall", 1], ["bakery", 2], ["house", 3]], 1, 300, 1)
	var result := _run_placement(registry, _map_config(24, 24, 42, Vector2i(12, 12), config))
	_expect(result.ok, "count and footprint placement should succeed: %s" % result.get("error", ""))
	if not result.ok:
		return

	_expect(result.instances.size() == 6, "generated instance count should equal sum of configured counts")
	var counts := _count_instances_by_definition(result.instances)
	_expect(counts.get("town_hall", 0) == 1, "town_hall generated count should match config")
	_expect(counts.get("bakery", 0) == 2, "bakery generated count should match config")
	_expect(counts.get("house", 0) == 3, "house generated count should match config")

	for instance in result.instances:
		var definition_result: Dictionary = registry.get_definition(String(instance.definition_id))
		_expect(definition_result.ok, "generated instance should reference known definition '%s'" % instance.definition_id)
		if definition_result.ok:
			var footprint := _footprint_size(definition_result.definition)
			_expect(footprint.x > 0 and footprint.y > 0, "generated instance should use positive predefined footprint")

	_verify_generated_invariants(result.model, result.instances, registry, int(config.minimum_building_spacing), int(config.spawn_clearance))


func _verify_rejection_and_failure_behavior(registry: RefCounted) -> void:
	var too_small := _run_placement(registry, _map_config(2, 2, 10, Vector2i(1, 1), _placement_config([["town_hall", 1]], 0, 20, 0)))
	_expect(not too_small.ok, "building larger than map should fail placement")

	var impossible_spacing_config := _placement_config([["house", 2]], 10, 20, 0)
	var impossible_spacing := _run_placement(registry, _map_config(5, 5, 11, Vector2i(4, 4), impossible_spacing_config))
	_expect(not impossible_spacing.ok, "impossible spacing should fail placement")
	_expect(_occupied_cells(impossible_spacing.model).is_empty(), "failed whole layout should not leave occupied cells")

	var spawn_clearance_config := _placement_config([["house", 1]], 0, 20, 10)
	var spawn_clearance := _run_placement(registry, _map_config(4, 4, 12, Vector2i(1, 1), spawn_clearance_config))
	_expect(not spawn_clearance.ok, "impossible spawn clearance should fail placement")
	_expect(_occupied_cells(spawn_clearance.model).is_empty(), "spawn-clearance failure should not mutate occupied cells")


func _verify_spawn_escape(registry: RefCounted) -> void:
	var model := _initialized_model(_map_config(4, 4, 1, Vector2i(1, 1), _placement_config([["house", 0]], 0, 0, 0)))
	var placer := ProceduralBuildingPlacerScript.new()
	_expect(placer.has_spawn_escape(model), "fresh map should have at least one spawn escape neighbor")

	model.reserve_rect(Vector2i(1, 0), Vector2i.ONE, GridMapModelScript.STATE_OCCUPIED)
	model.reserve_rect(Vector2i(1, 2), Vector2i.ONE, GridMapModelScript.STATE_OCCUPIED)
	model.reserve_rect(Vector2i(0, 1), Vector2i.ONE, GridMapModelScript.STATE_OCCUPIED)
	model.reserve_rect(Vector2i(2, 1), Vector2i.ONE, GridMapModelScript.STATE_OCCUPIED)
	_expect(not placer.has_spawn_escape(model), "occupied orthogonal neighbors should fail spawn escape check")

	var blocked_escape := _run_placement(registry, _map_config(4, 4, 1, Vector2i(1, 1), _placement_config([["house", 0]], 0, 0, 0)), [Vector2i(1, 0), Vector2i(1, 2), Vector2i(0, 1), Vector2i(2, 1)])
	_expect(not blocked_escape.ok, "placement should fail when pre-existing occupied cells remove spawn escape")


func _verify_renderer_contract(registry: RefCounted) -> void:
	var config := _placement_config([["town_hall", 1], ["house", 1]], 1, 100, 1)
	var model := _initialized_model(_map_config(20, 20, 55, Vector2i(10, 10), config))
	var renderer := MapRendererScript.new()
	get_root().add_child(renderer)
	renderer.set_map_model(model)

	_expect(renderer.get_placement_error().is_empty(), "renderer should not report placement error: %s" % renderer.get_placement_error())
	var instances: Array[Dictionary] = renderer.get_building_instances()
	_expect(instances.size() == 2, "renderer should expose generated building instances")
	var rects: Dictionary = renderer.get_generated_building_rects()
	_expect(rects.size() == instances.size(), "renderer should expose one generated rect per instance")

	for instance in instances:
		var definition: Dictionary = registry.get_definition(String(instance.definition_id)).definition
		var origin := _vector2i_from_dictionary(instance.origin_cell)
		var expected_position: Vector2 = model.origin + Vector2(origin) * float(model.cell_size)
		var expected_size: Vector2 = Vector2(_footprint_size(definition)) * float(model.cell_size)
		var rect: Rect2 = rects[String(instance.instance_id)]
		_expect(rect.position == expected_position, "building rect should use grid-derived position for %s" % instance.instance_id)
		_expect(rect.size == expected_size, "building rect should use definition footprint size for %s" % instance.instance_id)

	renderer.queue_free()


func _run_placement(registry: RefCounted, map_config: Dictionary, preoccupied_cells: Array[Vector2i] = []) -> Dictionary:
	var model := _initialized_model(map_config)
	if model == null:
		return _failure("Unable to initialize fixture map model.")

	for cell in preoccupied_cells:
		var reserve_result: Dictionary = model.reserve_rect(cell, Vector2i.ONE, GridMapModelScript.STATE_OCCUPIED)
		if not reserve_result.ok:
			return _failure("Unable to preoccupy fixture cell %s: %s" % [cell, reserve_result.error], {"model": model})

	var placer := ProceduralBuildingPlacerScript.new()
	var result: Dictionary = placer.generate(model, registry, map_config.building_placement)
	result["model"] = model
	return result


func _initialized_model(map_config: Dictionary) -> RefCounted:
	var model := GridMapModelScript.new()
	var result: Dictionary = model.initialize_from_config(map_config, "fixture_map")
	if not result.ok:
		_expect(false, "fixture map should initialize: %s" % result.get("error", ""))
		return null
	return model


func _verify_generated_invariants(model: RefCounted, instances: Array[Dictionary], registry: RefCounted, spacing: int, spawn_clearance: int) -> void:
	var footprints: Array[Dictionary] = []
	for instance in instances:
		var definition: Dictionary = registry.get_definition(String(instance.definition_id)).definition
		var origin := _vector2i_from_dictionary(instance.origin_cell)
		var size := _footprint_size(definition)
		_expect(not String(instance.instance_id).is_empty(), "generated instance should have non-empty deterministic instance_id")
		_expect(model.is_cell_in_bounds(origin), "generated origin should be in bounds for %s" % instance.instance_id)
		for cell in _footprint_cells(origin, size):
			_expect(model.is_cell_in_bounds(cell), "footprint cell should be in bounds for %s" % instance.instance_id)
			_expect(model.is_occupied(cell), "accepted footprint cell should be occupied for %s at %s" % [instance.instance_id, cell])
			_expect(not model.is_reserved(cell), "accepted footprint should not cover reserved cell %s" % cell)
			_expect(not model.is_protected(cell), "accepted footprint should not cover protected cell %s" % cell)
			_expect(abs(cell.x - model.player_spawn_cell.x) > spawn_clearance or abs(cell.y - model.player_spawn_cell.y) > spawn_clearance, "accepted footprint should stay out of spawn clearance")

		for prior in footprints:
			_expect(not _rects_intersect(origin, size, prior.origin, prior.size), "generated footprints should not overlap")
			if spacing > 0:
				var prior_buffer_origin: Vector2i = prior.origin - Vector2i(spacing, spacing)
				var prior_buffer_size: Vector2i = prior.size + Vector2i(spacing * 2, spacing * 2)
				_expect(not _rects_intersect(origin, size, prior_buffer_origin, prior_buffer_size), "generated footprints should obey minimum spacing")

		footprints.append({"origin": origin, "size": size})


func _occupied_cells(model: RefCounted) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(model.grid_height):
		for x in range(model.grid_width):
			var cell := Vector2i(x, y)
			if model.is_occupied(cell):
				cells.append(cell)
	return cells


func _placement_config(requested_models: Array, spacing: int, retry_limit: int, spawn_clearance: int) -> Dictionary:
	var entries: Array[Dictionary] = []
	for raw_entry in requested_models:
		entries.append({
			"definition_id": String(raw_entry[0]),
			"count": int(raw_entry[1]),
		})
	return {
		"requested_models": entries,
		"minimum_building_spacing": spacing,
		"retry_limit": retry_limit,
		"spawn_clearance": spawn_clearance,
	}


func _map_config(width: int, height: int, seed: int, spawn_cell: Vector2i, placement_config: Dictionary) -> Dictionary:
	return {
		"grid_width": width,
		"grid_height": height,
		"cell_size": 16,
		"origin": {"x": 0, "y": 0},
		"seed": seed,
		"player_spawn_cell": {"x": spawn_cell.x, "y": spawn_cell.y},
		"building_placement": placement_config,
	}


func _count_instances_by_definition(instances: Array[Dictionary]) -> Dictionary:
	var counts: Dictionary = {}
	for instance in instances:
		counts[String(instance.definition_id)] = int(counts.get(String(instance.definition_id), 0)) + 1
	return counts


func _footprint_size(definition: Dictionary) -> Vector2i:
	return Vector2i(int(definition.footprint_cells.width), int(definition.footprint_cells.height))


func _footprint_cells(origin: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			cells.append(Vector2i(x, y))
	return cells


func _vector2i_from_dictionary(value: Dictionary) -> Vector2i:
	return Vector2i(int(value.x), int(value.y))


func _rects_intersect(a_origin: Vector2i, a_size: Vector2i, b_origin: Vector2i, b_size: Vector2i) -> bool:
	return a_origin.x < b_origin.x + b_size.x \
		and a_origin.x + a_size.x > b_origin.x \
		and a_origin.y < b_origin.y + b_size.y \
		and a_origin.y + a_size.y > b_origin.y


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _failure(message: String, extra: Dictionary = {}) -> Dictionary:
	var result := {
		"ok": false,
		"error": message,
	}
	result.merge(extra, true)
	return result
