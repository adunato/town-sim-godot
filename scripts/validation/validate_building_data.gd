extends SceneTree

const BuildingDataRegistryScript := preload("res://scripts/buildings/building_data_registry.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_run_checks()

	if _failures.is_empty():
		print("validate_building_data.gd: all checks passed")
		quit(0)
	else:
		for failure in _failures:
			printerr(failure)
		quit(1)


func _run_checks() -> void:
	var registry := BuildingDataRegistryScript.new()
	var load_result: Dictionary = registry.load_all()
	_expect(load_result.ok, "building definitions and instances should load: %s" % load_result.get("error", ""))
	if not load_result.ok:
		return

	_expect(load_result.definition_count >= 1, "building_definitions.json should contain at least one definition")
	_expect(load_result.instance_count >= 1, "prototype_building_instances.json should contain at least one instance fixture")
	_verify_definition_lookup(registry)
	_verify_instance_resolution(registry)
	_verify_contract_separation(registry)
	_verify_invalid_definition_configs(registry)
	_verify_invalid_instance_configs(registry)
	_verify_unknown_definition_reference()


func _verify_definition_lookup(registry: RefCounted) -> void:
	var town_hall_result: Dictionary = registry.call("get_definition", "town_hall")
	_expect(town_hall_result.ok, "registry should return known definition id 'town_hall': %s" % town_hall_result.get("error", ""))
	if town_hall_result.ok:
		var definition: Dictionary = town_hall_result.definition
		_expect(definition.display_name == "Town Hall", "town_hall definition should expose display_name")
		_expect(definition.footprint_cells.width == 4, "town_hall definition should expose footprint width")
		_expect(definition.footprint_cells.height == 3, "town_hall definition should expose footprint height")
		_expect(definition.prototype_color == "#8F6A3D", "town_hall definition should expose prototype_color")
		_expect(definition.selectable, "town_hall definition should expose selectable flag")
		_expect(definition.interactable, "town_hall definition should expose interactable flag")

	var second_lookup: Dictionary = registry.call("get_definition", "town_hall")
	_expect(second_lookup.ok, "registry should return the same known definition id on repeated lookup")
	if town_hall_result.ok and second_lookup.ok:
		_expect(second_lookup.definition == town_hall_result.definition, "repeated lookup for town_hall should return equal definition data")

	var unknown_result: Dictionary = registry.call("get_definition", "does_not_exist")
	_expect(not unknown_result.ok, "registry should reject unknown building definition ids")
	_expect(String(unknown_result.get("error", "")).contains("Unknown building definition id"), "unknown definition lookup should report a clear error")


func _verify_instance_resolution(registry: RefCounted) -> void:
	var instances: Array[Dictionary] = registry.call("get_instances")
	_expect(not instances.is_empty(), "registry should expose loaded building instances")
	if instances.is_empty():
		return

	var bakery_instance: Dictionary = {}
	for instance in instances:
		if instance.definition_id == "bakery":
			bakery_instance = instance
			break

	_expect(not bakery_instance.is_empty(), "fixture data should include a bakery instance")
	if bakery_instance.is_empty():
		return

	var resolved: Dictionary = registry.call("resolve_instance_definition", bakery_instance)
	_expect(resolved.ok, "registry should resolve a valid instance to its definition: %s" % resolved.get("error", ""))
	if resolved.ok:
		_expect(resolved.instance.instance_id == "prototype_map_bakery_001", "resolved instance should retain instance_id")
		_expect(resolved.instance.origin_cell.x == 14, "resolved instance should retain origin_cell.x")
		_expect(resolved.definition.id == "bakery", "resolved definition should match instance definition_id")
		_expect(resolved.definition.display_name == "Bakery", "resolved definition should expose display_name")


func _verify_contract_separation(registry: RefCounted) -> void:
	var definitions: Array[Dictionary] = registry.call("get_definitions")
	var instances: Array[Dictionary] = registry.call("get_instances")
	_expect(not definitions.is_empty(), "definitions should be stored separately from instances")
	_expect(not instances.is_empty(), "instances should be stored separately from definitions")
	if definitions.is_empty() or instances.is_empty():
		return

	_expect(definitions[0].has("footprint_cells"), "definition records should own footprint_cells")
	_expect(not definitions[0].has("origin_cell"), "definition records should not own map origin_cell")
	_expect(instances[0].has("origin_cell"), "instance records should own map origin_cell")
	_expect(not instances[0].has("prototype_color"), "instance records should not duplicate prototype_color")


func _verify_invalid_definition_configs(registry: RefCounted) -> void:
	var valid_definition := {
		"id": "valid_shop",
		"display_name": "Valid Shop",
		"footprint_cells": {"width": 2, "height": 2},
		"prototype_color": "#123ABC",
		"selectable": true,
		"interactable": false,
	}
	var valid_config := {
		"schema_version": 1,
		"definitions": [valid_definition],
	}

	_expect_valid_definitions(registry, valid_config, "valid_definition")

	var missing_name := valid_config.duplicate(true)
	missing_name.definitions[0].erase("display_name")
	_expect_invalid_definitions(registry, missing_name, "missing_display_name")

	var duplicate_id := valid_config.duplicate(true)
	duplicate_id.definitions.append(valid_definition.duplicate(true))
	_expect_invalid_definitions(registry, duplicate_id, "duplicate_definition_id")

	var uppercase_id := valid_config.duplicate(true)
	uppercase_id.definitions[0].id = "TownHall"
	_expect_invalid_definitions(registry, uppercase_id, "uppercase_definition_id")

	var invalid_width := valid_config.duplicate(true)
	invalid_width.definitions[0].footprint_cells.width = 0
	_expect_invalid_definitions(registry, invalid_width, "non_positive_width")

	var invalid_color := valid_config.duplicate(true)
	invalid_color.definitions[0].prototype_color = "brown"
	_expect_invalid_definitions(registry, invalid_color, "invalid_color")

	var invalid_flag := valid_config.duplicate(true)
	invalid_flag.definitions[0].selectable = "yes"
	_expect_invalid_definitions(registry, invalid_flag, "invalid_selectable")


func _verify_invalid_instance_configs(registry: RefCounted) -> void:
	var valid_instance := {
		"instance_id": "fixture_shop_001",
		"definition_id": "valid_shop",
		"origin_cell": {"x": 3, "y": 4},
	}
	var valid_config := {
		"schema_version": 1,
		"map_id": "fixture_map",
		"instances": [valid_instance],
	}

	_expect_valid_instances(registry, valid_config, "valid_instance")

	var missing_instance_id := valid_config.duplicate(true)
	missing_instance_id.instances[0].erase("instance_id")
	_expect_invalid_instances(registry, missing_instance_id, "missing_instance_id")

	var duplicate_instance_id := valid_config.duplicate(true)
	duplicate_instance_id.instances.append(valid_instance.duplicate(true))
	_expect_invalid_instances(registry, duplicate_instance_id, "duplicate_instance_id")

	var invalid_origin := valid_config.duplicate(true)
	invalid_origin.instances[0].origin_cell.x = 3.5
	_expect_invalid_instances(registry, invalid_origin, "fractional_origin")

	var missing_map_id := valid_config.duplicate(true)
	missing_map_id.erase("map_id")
	_expect_invalid_instances(registry, missing_map_id, "missing_map_id")


func _verify_unknown_definition_reference() -> void:
	var registry := BuildingDataRegistryScript.new()
	var definitions_result: Dictionary = registry.call("load_definitions")
	_expect(definitions_result.ok, "definitions should load before unknown reference check: %s" % definitions_result.get("error", ""))
	if not definitions_result.ok:
		return

	var invalid_instance := {
		"instance_id": "fixture_unknown_001",
		"definition_id": "unknown_definition",
		"origin_cell": {"x": 1, "y": 1},
	}
	var unresolved: Dictionary = registry.call("resolve_instance_definition", invalid_instance)
	_expect(not unresolved.ok, "registry should reject an instance with unknown definition_id")
	_expect(String(unresolved.get("error", "")).contains("unknown definition_id"), "unknown definition reference should report definition_id")


func _expect_valid_definitions(registry: RefCounted, config: Dictionary, label: String) -> void:
	var result: Dictionary = registry.call("validate_definitions_data", config, label)
	_expect(result.ok, "%s should pass definition validation: %s" % [label, result.get("error", "")])


func _expect_invalid_definitions(registry: RefCounted, config: Dictionary, label: String) -> void:
	var result: Dictionary = registry.call("validate_definitions_data", config, label)
	_expect(not result.ok, "%s should fail definition validation" % label)


func _expect_valid_instances(registry: RefCounted, config: Dictionary, label: String) -> void:
	var result: Dictionary = registry.call("validate_instances_data", config, label)
	_expect(result.ok, "%s should pass instance validation: %s" % [label, result.get("error", "")])


func _expect_invalid_instances(registry: RefCounted, config: Dictionary, label: String) -> void:
	var result: Dictionary = registry.call("validate_instances_data", config, label)
	_expect(not result.ok, "%s should fail instance validation" % label)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
