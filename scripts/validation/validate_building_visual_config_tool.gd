extends SceneTree

const BuildingVisualConfigStoreScript := preload("res://addons/townsim_building_visual_config/building_visual_config_store.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_run_checks()

	if _failures.is_empty():
		print("validate_building_visual_config_tool.gd: all checks passed")
		quit(0)
	else:
		for failure in _failures:
			printerr(failure)
		quit(1)


func _run_checks() -> void:
	_verify_plugin_registration()

	var store = BuildingVisualConfigStoreScript.new()
	var load_result: Dictionary = store.load_data()
	_expect(load_result.ok, "building visual configuration store should load project data: %s" % load_result.get("error", ""))
	if not load_result.ok:
		return

	var definitions: Array[Dictionary] = store.get_definitions()
	var profiles: Array[Dictionary] = store.get_visual_profiles()
	_expect(not definitions.is_empty(), "tool should list building definitions")
	_expect(not profiles.is_empty(), "tool should list visual profiles")
	if definitions.is_empty() or profiles.is_empty():
		return

	var definition := definitions[0].duplicate(true)
	var profile_result: Dictionary = store.get_visual_profile(String(definition.visual_profile_id))
	_expect(profile_result.ok, "tool should load the selected building's referenced visual profile: %s" % profile_result.get("error", ""))
	if not profile_result.ok:
		return

	var profile: Dictionary = profile_result.visual_profile
	var messages := store.get_validation_messages(definition, profile)
	_expect(messages.is_empty(), "current building/profile selection should validate: %s" % str(messages))

	_verify_edit_validation(store, definition, profile)
	_verify_assignment_validation(store, definition, profile)
	_verify_save_contract(store, definition, profile)


func _verify_plugin_registration() -> void:
	_expect(FileAccess.file_exists("res://addons/townsim_building_visual_config/plugin.cfg"), "building visual config plugin.cfg should exist")
	_expect(FileAccess.file_exists("res://addons/townsim_building_visual_config/plugin.gd"), "building visual config plugin.gd should exist")
	var project_file := FileAccess.open("res://project.godot", FileAccess.READ)
	_expect(project_file != null, "project.godot should be readable")
	if project_file != null:
		var project_text := project_file.get_as_text()
		_expect(project_text.contains("res://addons/townsim_building_visual_config/plugin.cfg"), "project.godot should enable the building visual configuration plugin")


func _verify_edit_validation(store: RefCounted, definition: Dictionary, profile: Dictionary) -> void:
	var edited := profile.duplicate(true)
	edited.anchor = "footprint_center"
	edited.pixel_offset = {"x": 4, "y": -2}
	edited.y_sort_origin = "footprint_center"
	edited.visual_bounds = {"x": -8, "y": -16, "width": 96, "height": 88}
	var messages: Array[String] = store.call("get_validation_messages", definition, edited)
	_expect(messages.is_empty(), "valid edited placement fields should pass validation: %s" % str(messages))

	var invalid_anchor := edited.duplicate(true)
	invalid_anchor.anchor = "roof_peak"
	var anchor_messages: Array[String] = store.call("get_validation_messages", definition, invalid_anchor)
	_expect(not anchor_messages.is_empty(), "unsupported anchor edits should produce validation feedback")

	var invalid_bounds := edited.duplicate(true)
	invalid_bounds.visual_bounds.width = 0
	var bounds_messages: Array[String] = store.call("get_validation_messages", definition, invalid_bounds)
	_expect(not bounds_messages.is_empty(), "malformed visual bounds should produce validation feedback")


func _verify_assignment_validation(store: RefCounted, definition: Dictionary, profile: Dictionary) -> void:
	var invalid_assignment := definition.duplicate(true)
	invalid_assignment.visual_profile_id = "unknown_profile"
	var messages: Array[String] = store.call("get_validation_messages", invalid_assignment, profile)
	_expect(not messages.is_empty(), "unknown visual_profile_id assignment should produce validation feedback")

	var mismatched_assignment := definition.duplicate(true)
	for candidate in store.call("get_visual_profiles"):
		if String(candidate.id) != String(profile.id) and candidate.expected_footprint_cells != definition.footprint_cells:
			mismatched_assignment.visual_profile_id = candidate.id
			var mismatch_messages: Array[String] = store.call("get_validation_messages", mismatched_assignment, candidate)
			_expect(not mismatch_messages.is_empty(), "footprint mismatch assignment should produce validation feedback")
			return


func _verify_save_contract(store: RefCounted, definition: Dictionary, profile: Dictionary) -> void:
	var edited_definition := definition.duplicate(true)
	var edited_profile := profile.duplicate(true)
	edited_profile.pixel_offset = {"x": 7, "y": -3}
	edited_profile.visual_bounds = {"x": -4, "y": -8, "width": 132, "height": 104}

	var definition_apply: Dictionary = store.call("apply_definition_profile_id", String(edited_definition.id), String(edited_profile.id))
	_expect(definition_apply.ok, "tool should apply visual_profile_id assignment to selected definition: %s" % definition_apply.get("error", ""))
	var profile_apply: Dictionary = store.call("apply_visual_profile_fields", String(edited_profile.id), {
		"anchor": edited_profile.anchor,
		"pixel_offset": edited_profile.pixel_offset,
		"y_sort_origin": edited_profile.y_sort_origin,
		"visual_bounds": edited_profile.visual_bounds,
	})
	_expect(profile_apply.ok, "tool should apply visual profile placement edits: %s" % profile_apply.get("error", ""))

	var definitions_target := "user://building_visual_config_tool_definitions.json"
	var profiles_target := "user://building_visual_config_tool_profiles.json"
	var save_result: Dictionary = store.call("save", definitions_target, profiles_target)
	_expect(save_result.ok, "tool should save edited definition/profile artifacts: %s" % save_result.get("error", ""))

	var definitions_data := _load_json(definitions_target)
	var profiles_data := _load_json(profiles_target)
	_expect(definitions_data.has("definitions"), "saved definitions artifact should contain definitions")
	_expect(profiles_data.has("profiles"), "saved profiles artifact should contain profiles")
	if definitions_data.has("definitions"):
		var saved_definition := _find_record(definitions_data.definitions, String(edited_definition.id))
		_expect(saved_definition.footprint_cells == definition.footprint_cells, "save should not change logical building footprint")
	if profiles_data.has("profiles"):
		var saved_profile := _find_record(profiles_data.profiles, String(edited_profile.id))
		_expect(int(saved_profile.pixel_offset.x) == int(edited_profile.pixel_offset.x), "save should persist pixel_offset.x edits")
		_expect(int(saved_profile.pixel_offset.y) == int(edited_profile.pixel_offset.y), "save should persist pixel_offset.y edits")
		_expect(int(saved_profile.visual_bounds.x) == int(edited_profile.visual_bounds.x), "save should persist visual_bounds.x edits")
		_expect(int(saved_profile.visual_bounds.y) == int(edited_profile.visual_bounds.y), "save should persist visual_bounds.y edits")
		_expect(int(saved_profile.visual_bounds.width) == int(edited_profile.visual_bounds.width), "save should persist visual_bounds.width edits")
		_expect(int(saved_profile.visual_bounds.height) == int(edited_profile.visual_bounds.height), "save should persist visual_bounds.height edits")


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_failures.append("Unable to read saved JSON file '%s': %s" % [path, error_string(FileAccess.get_open_error())])
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		_failures.append("Saved JSON file '%s' should parse as an object" % path)
		return {}
	return parsed


func _find_record(records: Array, record_id: String) -> Dictionary:
	for record in records:
		if String(record.get("id", "")) == record_id:
			return record
	_failures.append("Unable to find saved record '%s'" % record_id)
	return {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
