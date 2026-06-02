class_name ProceduralBuildingPlacer
extends RefCounted

const GridMapModelScript := preload("res://scripts/map/grid_map_model.gd")


func generate(map_model: RefCounted, registry: RefCounted, placement_config: Dictionary) -> Dictionary:
	var config_validation := validate_placement_config(placement_config, registry)
	if not config_validation.ok:
		return config_validation

	var requests: Array[String] = _build_requests(placement_config)
	if not has_spawn_escape(map_model):
		return _failure("Generated layout leaves no orthogonally adjacent walkable escape cell around player spawn %s." % map_model.player_spawn_cell)
	if requests.is_empty():
		return _success({"instances": [], "placements": []})

	var retry_limit := int(placement_config.retry_limit)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(map_model.seed)

	var accepted: Array[Dictionary] = []
	var definition_counts: Dictionary = {}
	var rejection_counts: Dictionary = {}

	for definition_id in requests:
		var definition_result: Dictionary = registry.call("get_definition", definition_id)
		if not definition_result.ok:
			return definition_result

		var definition: Dictionary = definition_result.definition
		var footprint_size := _footprint_size(definition)
		if footprint_size.x > map_model.grid_width or footprint_size.y > map_model.grid_height:
			return _failure("Building definition '%s' footprint %s cannot fit within map bounds %dx%d." % [definition_id, footprint_size, map_model.grid_width, map_model.grid_height])

		var placed := false
		for _attempt in range(retry_limit):
			var origin := Vector2i(
				rng.randi_range(0, map_model.grid_width - footprint_size.x),
				rng.randi_range(0, map_model.grid_height - footprint_size.y)
			)
			var candidate := _validate_candidate(map_model, definition, origin, accepted, placement_config)
			if not candidate.ok:
				var reason := String(candidate.reason)
				rejection_counts[reason] = int(rejection_counts.get(reason, 0)) + 1
				continue

			var sequence := int(definition_counts.get(definition_id, 0)) + 1
			definition_counts[definition_id] = sequence
			var instance := {
				"instance_id": "prototype_map_%s_%03d" % [definition_id, sequence],
				"definition_id": definition_id,
				"origin_cell": {"x": origin.x, "y": origin.y},
			}
			accepted.append({
				"instance": instance,
				"definition": definition,
				"origin": origin,
				"size": footprint_size,
			})
			placed = true
			break

		if not placed:
			return _failure("Unable to place requested building definition '%s' within retry limit %d." % [definition_id, retry_limit], {
				"definition_id": definition_id,
				"retry_limit": retry_limit,
				"rejection_counts": rejection_counts.duplicate(true),
			})

	if not has_spawn_escape(map_model, accepted):
		return _failure("Generated layout leaves no orthogonally adjacent walkable escape cell around player spawn %s." % map_model.player_spawn_cell)

	for placement in accepted:
		var reserve_result: Dictionary = map_model.reserve_rect(placement.origin, placement.size, GridMapModelScript.STATE_OCCUPIED)
		if not reserve_result.ok:
			return _failure("Unable to reserve accepted building footprint for '%s': %s" % [placement.instance.instance_id, reserve_result.error])

	var instances: Array[Dictionary] = []
	for placement in accepted:
		instances.append(placement.instance.duplicate(true))

	return _success({
		"instances": instances,
		"placements": accepted,
	})


func validate_placement_config(placement_config: Dictionary, registry: RefCounted) -> Dictionary:
	if placement_config.is_empty():
		return _failure("Placement configuration is missing.")
	for field in ["requested_models", "minimum_building_spacing", "retry_limit", "spawn_clearance"]:
		if not placement_config.has(field):
			return _failure("Placement configuration is missing required field '%s'." % field)

	if typeof(placement_config.requested_models) != TYPE_ARRAY:
		return _failure("Placement configuration field 'requested_models' must be an array.")
	if not _is_integer_number(placement_config.minimum_building_spacing) or int(placement_config.minimum_building_spacing) < 0:
		return _failure("Placement configuration field 'minimum_building_spacing' must be a non-negative integer.")
	if not _is_integer_number(placement_config.retry_limit) or int(placement_config.retry_limit) < 0:
		return _failure("Placement configuration field 'retry_limit' must be a non-negative integer.")
	if not _is_integer_number(placement_config.spawn_clearance) or int(placement_config.spawn_clearance) < 0:
		return _failure("Placement configuration field 'spawn_clearance' must be a non-negative integer.")

	var total_count := 0
	var seen_ids: Dictionary = {}
	for index in range(placement_config.requested_models.size()):
		var entry: Variant = placement_config.requested_models[index]
		if typeof(entry) != TYPE_DICTIONARY:
			return _failure("Placement configuration requested_models[%d] must be an object." % index)
		if not entry.has("definition_id"):
			return _failure("Placement configuration requested_models[%d] is missing required field 'definition_id'." % index)
		if not entry.has("count"):
			return _failure("Placement configuration requested_models[%d] is missing required field 'count'." % index)
		if typeof(entry.definition_id) != TYPE_STRING or String(entry.definition_id).strip_edges().is_empty():
			return _failure("Placement configuration requested_models[%d].definition_id must be a non-empty string." % index)
		if not _is_integer_number(entry.count) or int(entry.count) < 0:
			return _failure("Placement configuration requested_models[%d].count must be a non-negative integer." % index)

		var definition_id := String(entry.definition_id)
		if seen_ids.has(definition_id):
			return _failure("Placement configuration requested_models contains duplicate definition_id '%s'." % definition_id)
		if not registry.call("has_definition", definition_id):
			return _failure("Placement configuration requested_models[%d] references unknown building definition id '%s'." % [index, definition_id])
		seen_ids[definition_id] = true
		total_count += int(entry.count)

	if total_count > 0 and int(placement_config.retry_limit) == 0:
		return _failure("Placement configuration field 'retry_limit' must be positive when building count is greater than zero.")

	return _success({"building_count": total_count})


func has_spawn_escape(map_model: RefCounted, accepted_placements: Array[Dictionary] = []) -> bool:
	var neighbors: Array[Vector2i] = [
		map_model.player_spawn_cell + Vector2i.UP,
		map_model.player_spawn_cell + Vector2i.DOWN,
		map_model.player_spawn_cell + Vector2i.LEFT,
		map_model.player_spawn_cell + Vector2i.RIGHT,
	]
	for neighbor in neighbors:
		if not map_model.is_cell_in_bounds(neighbor):
			continue
		if not map_model.is_walkable(neighbor):
			continue
		if _cell_in_accepted_footprints(neighbor, accepted_placements):
			continue
		return true
	return false


func _build_requests(placement_config: Dictionary) -> Array[String]:
	var requests: Array[String] = []
	for entry in placement_config.requested_models:
		for _index in range(int(entry.count)):
			requests.append(String(entry.definition_id))
	return requests


func _validate_candidate(map_model: RefCounted, definition: Dictionary, origin: Vector2i, accepted: Array[Dictionary], placement_config: Dictionary) -> Dictionary:
	var definition_id := String(definition.id)
	var size := _footprint_size(definition)
	var spacing := int(placement_config.minimum_building_spacing)
	var spawn_clearance := int(placement_config.spawn_clearance)

	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			var cell := Vector2i(x, y)
			if not map_model.is_cell_in_bounds(cell):
				return _candidate_failure("bounds", "Building definition '%s' footprint includes out-of-bounds cell %s." % [definition_id, cell])
			if map_model.is_blocked(cell):
				return _candidate_failure("blocked", "Building definition '%s' footprint includes blocked cell %s." % [definition_id, cell])
			if map_model.is_occupied(cell):
				return _candidate_failure("occupied", "Building definition '%s' footprint includes occupied cell %s." % [definition_id, cell])
			if map_model.is_reserved(cell):
				return _candidate_failure("reserved", "Building definition '%s' footprint includes reserved cell %s." % [definition_id, cell])
			if map_model.is_protected(cell):
				return _candidate_failure("protected", "Building definition '%s' footprint includes protected cell %s." % [definition_id, cell])
			if _cell_in_spawn_clearance(cell, map_model.player_spawn_cell, spawn_clearance):
				return _candidate_failure("spawn_clearance", "Building definition '%s' footprint includes spawn clearance cell %s." % [definition_id, cell])

	for placement in accepted:
		if _rects_intersect(origin, size, placement.origin, placement.size):
			return _candidate_failure("overlap", "Building definition '%s' overlaps accepted building '%s'." % [definition_id, placement.instance.instance_id])
		if spacing > 0:
			var accepted_buffer_origin: Vector2i = placement.origin - Vector2i(spacing, spacing)
			var accepted_buffer_size: Vector2i = placement.size + Vector2i(spacing * 2, spacing * 2)
			var candidate_buffer_origin := origin - Vector2i(spacing, spacing)
			var candidate_buffer_size := size + Vector2i(spacing * 2, spacing * 2)
			if _rects_intersect(origin, size, accepted_buffer_origin, accepted_buffer_size) \
					or _rects_intersect(placement.origin, placement.size, candidate_buffer_origin, candidate_buffer_size):
				return _candidate_failure("spacing", "Building definition '%s' violates minimum spacing from accepted building '%s'." % [definition_id, placement.instance.instance_id])

	return _success()


func _cell_in_accepted_footprints(cell: Vector2i, accepted_placements: Array[Dictionary]) -> bool:
	for placement in accepted_placements:
		if _cell_in_rect(cell, placement.origin, placement.size):
			return true
	return false


func _cell_in_spawn_clearance(cell: Vector2i, spawn_cell: Vector2i, spawn_clearance: int) -> bool:
	return abs(cell.x - spawn_cell.x) <= spawn_clearance and abs(cell.y - spawn_cell.y) <= spawn_clearance


func _cell_in_rect(cell: Vector2i, origin: Vector2i, size: Vector2i) -> bool:
	return cell.x >= origin.x and cell.y >= origin.y and cell.x < origin.x + size.x and cell.y < origin.y + size.y


func _rects_intersect(a_origin: Vector2i, a_size: Vector2i, b_origin: Vector2i, b_size: Vector2i) -> bool:
	return a_origin.x < b_origin.x + b_size.x \
		and a_origin.x + a_size.x > b_origin.x \
		and a_origin.y < b_origin.y + b_size.y \
		and a_origin.y + a_size.y > b_origin.y


func _footprint_size(definition: Dictionary) -> Vector2i:
	return Vector2i(int(definition.footprint_cells.width), int(definition.footprint_cells.height))


func _is_integer_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	return is_equal_approx(float(value), float(int(value)))


func _candidate_failure(reason: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"error": message,
	}


func _success(extra: Dictionary = {}) -> Dictionary:
	var result := {"ok": true}
	result.merge(extra, true)
	return result


func _failure(message: String, extra: Dictionary = {}) -> Dictionary:
	var result := {
		"ok": false,
		"error": message,
	}
	result.merge(extra, true)
	return result
