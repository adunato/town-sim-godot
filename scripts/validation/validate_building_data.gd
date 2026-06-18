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
	_expect(load_result.visual_profile_count >= 1, "building_visual_profiles.json should contain at least one visual profile")
	_expect(load_result.instance_count >= 1, "prototype_building_instances.json should contain at least one instance fixture")
	_verify_definition_lookup(registry)
	_verify_visual_profile_lookup(registry)
	_verify_instance_resolution(registry)
	_verify_visual_profile_resolution(registry)
	_verify_contract_separation(registry)
	_verify_invalid_definition_configs(registry)
	_verify_invalid_visual_profile_configs(registry)
	_verify_invalid_instance_configs(registry)
	_verify_unknown_definition_reference()
	_verify_unknown_visual_profile_reference()


func _verify_definition_lookup(registry: RefCounted) -> void:
	var town_hall_result: Dictionary = registry.call("get_definition", "town_hall")
	_expect(town_hall_result.ok, "registry should return known definition id 'town_hall': %s" % town_hall_result.get("error", ""))
	if town_hall_result.ok:
		var definition: Dictionary = town_hall_result.definition
		_expect(definition.display_name == "Town Hall", "town_hall definition should expose display_name")
		_expect(definition.footprint_cells.width == 4, "town_hall definition should expose footprint width")
		_expect(definition.footprint_cells.height == 3, "town_hall definition should expose footprint height")
		_expect(definition.visual_profile_id == "town_hall_sprite", "town_hall definition should expose visual_profile_id")
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


func _verify_visual_profile_lookup(registry: RefCounted) -> void:
	var profile_result: Dictionary = registry.call("get_visual_profile", "town_hall_sprite")
	_expect(profile_result.ok, "registry should return known visual profile id 'town_hall_sprite': %s" % profile_result.get("error", ""))
	if profile_result.ok:
		var profile: Dictionary = profile_result.visual_profile
		_expect(profile.texture_path == "res://assets/tiles/play/play_cells_atlas.png", "visual profile should expose texture_path")
		_expect(profile.anchor == "footprint_bottom_center", "visual profile should expose anchor")
		_expect(profile.pixel_offset.x == 0 and profile.pixel_offset.y == 0, "visual profile should expose integer pixel_offset")
		_expect(profile.y_sort_origin == "footprint_bottom_center", "visual profile should expose y_sort_origin")
		_expect(profile.render_size.width == 128 and profile.render_size.height == 96, "visual profile should expose render_size")
		_expect(profile.visual_bounds.width == 128 and profile.visual_bounds.height == 96, "visual profile should expose visual_bounds")
		_expect(profile.expected_footprint_cells.width == 4, "visual profile should expose expected footprint width")
		_expect(profile.expected_footprint_cells.height == 3, "visual profile should expose expected footprint height")

	var unknown_result: Dictionary = registry.call("get_visual_profile", "does_not_exist")
	_expect(not unknown_result.ok, "registry should reject unknown visual profile ids")
	_expect(String(unknown_result.get("error", "")).contains("Unknown building visual profile id"), "unknown visual profile lookup should report a clear error")


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


func _verify_visual_profile_resolution(registry: RefCounted) -> void:
	var definitions: Array[Dictionary] = registry.call("get_definitions")
	_expect(not definitions.is_empty(), "definitions should be available for visual profile resolution")
	for definition in definitions:
		var visual_result: Dictionary = registry.call("resolve_definition_visual_profile", definition)
		_expect(visual_result.ok, "definition '%s' should resolve visual profile: %s" % [definition.id, visual_result.get("error", "")])
		if visual_result.ok:
			_expect(visual_result.visual_profile.id == definition.visual_profile_id, "resolved visual profile should match visual_profile_id for '%s'" % definition.id)
			_expect(visual_result.visual_profile.expected_footprint_cells == definition.footprint_cells, "visual profile footprint should match definition footprint for '%s'" % definition.id)

	var instances: Array[Dictionary] = registry.call("get_instances")
	_expect(not instances.is_empty(), "instances should be available for instance visual profile resolution")
	if not instances.is_empty():
		var resolved: Dictionary = registry.call("resolve_instance_visual_profile", instances[0])
		_expect(resolved.ok, "instance should resolve definition and visual profile: %s" % resolved.get("error", ""))
		if resolved.ok:
			_expect(resolved.definition.id == instances[0].definition_id, "resolved visual instance should expose matching definition")
			_expect(resolved.visual_profile.id == resolved.definition.visual_profile_id, "resolved visual instance should expose matching visual profile")


func _verify_contract_separation(registry: RefCounted) -> void:
	var definitions: Array[Dictionary] = registry.call("get_definitions")
	var instances: Array[Dictionary] = registry.call("get_instances")
	_expect(not definitions.is_empty(), "definitions should be stored separately from instances")
	_expect(not instances.is_empty(), "instances should be stored separately from definitions")
	if definitions.is_empty() or instances.is_empty():
		return

	_expect(definitions[0].has("footprint_cells"), "definition records should own footprint_cells")
	_expect(definitions[0].has("visual_profile_id"), "definition records should reference visual profiles")
	_expect(not definitions[0].has("origin_cell"), "definition records should not own map origin_cell")
	_expect(instances[0].has("origin_cell"), "instance records should own map origin_cell")
	_expect(not instances[0].has("prototype_color"), "instance records should not duplicate prototype_color")

	var visual_profiles: Array[Dictionary] = registry.call("get_visual_profiles")
	_expect(not visual_profiles.is_empty(), "visual profiles should be stored separately from definitions")
	if not visual_profiles.is_empty():
		_expect(visual_profiles[0].has("texture_path"), "visual profile records should own texture_path")
		_expect(visual_profiles[0].has("expected_footprint_cells"), "visual profile records should own expected footprint")
		_expect(not visual_profiles[0].has("origin_cell"), "visual profile records should not own map origin_cell")
		_expect(not visual_profiles[0].has("selectable"), "visual profile records should not own gameplay selectable flag")


func _verify_invalid_definition_configs(registry: RefCounted) -> void:
	var valid_definition := {
		"id": "valid_shop",
		"display_name": "Valid Shop",
		"footprint_cells": {"width": 2, "height": 2},
		"visual_profile_id": "valid_shop_sprite",
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

	var missing_profile_id := valid_config.duplicate(true)
	missing_profile_id.definitions[0].erase("visual_profile_id")
	_expect_invalid_definitions(registry, missing_profile_id, "missing_visual_profile_id")


func _verify_invalid_visual_profile_configs(registry: RefCounted) -> void:
	var valid_profile := _valid_visual_profile()
	var valid_config := {
		"schema_version": 1,
		"profiles": [valid_profile],
	}

	_expect_valid_visual_profiles(registry, valid_config, "valid_visual_profile")

	var duplicate_id := valid_config.duplicate(true)
	duplicate_id.profiles.append(valid_profile.duplicate(true))
	_expect_invalid_visual_profiles(registry, duplicate_id, "duplicate_visual_profile_id")

	var missing_texture := valid_config.duplicate(true)
	missing_texture.profiles[0].erase("texture_path")
	_expect_invalid_visual_profiles(registry, missing_texture, "missing_texture_path")

	var invalid_texture := valid_config.duplicate(true)
	invalid_texture.profiles[0].texture_path = "res://assets/buildings/does_not_exist.png"
	_expect_invalid_visual_profiles(registry, invalid_texture, "invalid_texture_path")

	var invalid_region := valid_config.duplicate(true)
	invalid_region.profiles[0].source_rect = {"x": 0, "y": 0, "width": 9999, "height": 9999}
	_expect_invalid_visual_profiles(registry, invalid_region, "invalid_atlas_region")

	var unsupported_anchor := valid_config.duplicate(true)
	unsupported_anchor.profiles[0].anchor = "roof_peak"
	_expect_invalid_visual_profiles(registry, unsupported_anchor, "unsupported_anchor")

	var unsupported_y_sort := valid_config.duplicate(true)
	unsupported_y_sort.profiles[0].y_sort_origin = "image_top"
	_expect_invalid_visual_profiles(registry, unsupported_y_sort, "unsupported_y_sort")

	var malformed_offset := valid_config.duplicate(true)
	malformed_offset.profiles[0].pixel_offset.x = 0.5
	_expect_invalid_visual_profiles(registry, malformed_offset, "malformed_pixel_offset")

	var malformed_render_size := valid_config.duplicate(true)
	malformed_render_size.profiles[0].render_size.height = 0
	_expect_invalid_visual_profiles(registry, malformed_render_size, "malformed_render_size")

	var malformed_visual_bounds := valid_config.duplicate(true)
	malformed_visual_bounds.profiles[0].visual_bounds.width = 0
	_expect_invalid_visual_profiles(registry, malformed_visual_bounds, "malformed_visual_bounds")

	var non_positive_footprint := valid_config.duplicate(true)
	non_positive_footprint.profiles[0].expected_footprint_cells.width = 0
	_expect_invalid_visual_profiles(registry, non_positive_footprint, "non_positive_expected_footprint")

	var valid_definition := {
		"id": "valid_shop",
		"display_name": "Valid Shop",
		"footprint_cells": {"width": 2, "height": 2},
		"visual_profile_id": "fixture_sprite",
		"prototype_color": "#123ABC",
		"selectable": true,
		"interactable": false,
	}
	var mismatched_profile := valid_profile.duplicate(true)
	mismatched_profile.expected_footprint_cells = {"width": 3, "height": 2}
	var mismatch_result: Dictionary = registry.call("validate_visual_profile_footprint_match", valid_definition, mismatched_profile)
	_expect(not mismatch_result.ok, "mismatched logical/profile footprint sizes should fail validation")


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


func _verify_unknown_visual_profile_reference() -> void:
	var registry := BuildingDataRegistryScript.new()
	var definitions_result: Dictionary = registry.call("load_definitions")
	_expect(definitions_result.ok, "definitions should load before unknown visual profile check: %s" % definitions_result.get("error", ""))
	var profiles_result: Dictionary = registry.call("load_visual_profiles")
	_expect(profiles_result.ok, "visual profiles should load before unknown visual profile check: %s" % profiles_result.get("error", ""))
	if not definitions_result.ok or not profiles_result.ok:
		return

	var invalid_definition := {
		"id": "fixture_shop",
		"display_name": "Fixture Shop",
		"footprint_cells": {"width": 2, "height": 2},
		"visual_profile_id": "unknown_profile",
		"prototype_color": "#123ABC",
		"selectable": true,
		"interactable": false,
	}
	var unresolved: Dictionary = registry.call("resolve_definition_visual_profile", invalid_definition)
	_expect(not unresolved.ok, "registry should reject a definition with unknown visual_profile_id")
	_expect(String(unresolved.get("error", "")).contains("unknown visual_profile_id"), "unknown visual profile reference should report visual_profile_id")


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


func _expect_valid_visual_profiles(registry: RefCounted, config: Dictionary, label: String) -> void:
	var result: Dictionary = registry.call("validate_visual_profiles_data", config, label)
	_expect(result.ok, "%s should pass visual profile validation: %s" % [label, result.get("error", "")])


func _expect_invalid_visual_profiles(registry: RefCounted, config: Dictionary, label: String) -> void:
	var result: Dictionary = registry.call("validate_visual_profiles_data", config, label)
	_expect(not result.ok, "%s should fail visual profile validation" % label)


func _valid_visual_profile() -> Dictionary:
	return {
		"id": "fixture_sprite",
		"texture_path": "res://assets/tiles/play/play_cells_atlas.png",
		"source_rect": null,
		"anchor": "footprint_bottom_center",
		"pixel_offset": {"x": 0, "y": 0},
		"y_sort_origin": "footprint_bottom_center",
		"render_size": {"width": 64, "height": 64},
		"visual_bounds": {"x": 0, "y": 0, "width": 64, "height": 64},
		"expected_footprint_cells": {"width": 2, "height": 2},
	}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
