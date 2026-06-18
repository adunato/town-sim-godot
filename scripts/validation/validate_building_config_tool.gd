extends SceneTree

const BuildingConfigStoreScript := preload("res://addons/townsim_building_config/building_config_store.gd")
const BuildingConfigDockScript := preload("res://addons/townsim_building_config/building_config_dock.gd")
const BuildingVisualPreviewScript := preload("res://addons/townsim_building_config/building_visual_preview.gd")
const BuildingEntityVisualScript := preload("res://scripts/buildings/building_entity_visual.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	await _run_checks()
	if _failures.is_empty():
		print("validate_building_config_tool.gd: all checks passed")
		quit(0)
	else:
		for failure in _failures:
			printerr(failure)
		quit(1)


func _run_checks() -> void:
	_verify_plugin_registration()
	var store = BuildingConfigStoreScript.new()
	var load_result: Dictionary = store.load_data()
	_expect(load_result.ok, "building configuration store should load project data: %s" % load_result.get("error", ""))
	if not load_result.ok:
		return
	_verify_store_contract(store)
	_verify_terrain_preview(store)
	await _verify_synchronized_tabs()
	await _verify_runtime_outline(store)


func _verify_plugin_registration() -> void:
	_expect(FileAccess.file_exists("res://addons/townsim_building_config/plugin.cfg"), "renamed building config plugin.cfg should exist")
	_expect(FileAccess.file_exists("res://addons/townsim_building_config/plugin.gd"), "renamed building config plugin.gd should exist")
	_expect(not FileAccess.file_exists("res://addons/townsim_building_visual_config/plugin.cfg"), "old building visual config plugin should be removed")
	var plugin_file := FileAccess.open("res://addons/townsim_building_config/plugin.cfg", FileAccess.READ)
	_expect(plugin_file != null and plugin_file.get_as_text().contains("TownSim Building Configuration"), "plugin metadata should use renamed tool label")
	var project_file := FileAccess.open("res://project.godot", FileAccess.READ)
	_expect(project_file != null, "project.godot should be readable")
	if project_file != null:
		var project_text := project_file.get_as_text()
		_expect(project_text.contains("res://addons/townsim_building_config/plugin.cfg"), "project should enable renamed building config plugin")
		_expect(not project_text.contains("res://addons/townsim_building_visual_config/plugin.cfg"), "project should not enable old building visual config plugin")


func _verify_store_contract(store: RefCounted) -> void:
	var definitions: Array[Dictionary] = store.call("get_definitions")
	var profiles: Array[Dictionary] = store.call("get_visual_profiles")
	_expect(not definitions.is_empty(), "store should list building definitions")
	_expect(not profiles.is_empty(), "store should list visual profiles")
	if definitions.is_empty() or profiles.is_empty():
		return

	var definition: Dictionary = definitions[0]
	var definition_id := String(definition.id)
	var profile_result: Dictionary = store.call("get_assigned_profile", definition_id)
	_expect(profile_result.ok, "selected definition should resolve its assigned profile")
	if not profile_result.ok:
		return
	var profile: Dictionary = profile_result.visual_profile
	var profile_id := String(profile.id)

	var id_result: Dictionary = store.call("update_definition_fields", definition_id, {"id": "renamed"})
	_expect(not id_result.ok, "definition IDs should be read-only")
	var profile_id_result: Dictionary = store.call("update_visual_profile_fields", profile_id, {"id": "renamed"})
	_expect(not profile_id_result.ok, "visual profile IDs should be read-only")

	var original_width := int(definition.footprint_cells.width)
	var changed_width := original_width + 1
	var definition_edit: Dictionary = store.call("update_definition_fields", definition_id, {
		"display_name": "%s Edited" % definition.display_name,
		"footprint_cells": {"width": changed_width, "height": int(definition.footprint_cells.height)},
		"visual_profile_id": profile_id,
		"prototype_color": "#123456",
		"selectable": not bool(definition.selectable),
		"interactable": not bool(definition.interactable),
	})
	_expect(definition_edit.ok, "all mutable definition fields should update")
	var mismatch_messages: Array[String] = store.call("get_validation_messages")
	_expect(not mismatch_messages.is_empty(), "footprint mismatch should produce validation feedback")
	var blocked_save: Dictionary = store.call("save", "user://invalid_building_definitions.json", "user://invalid_building_profiles.json")
	_expect(not blocked_save.ok, "save should be blocked while working data is invalid")

	var profile_edit: Dictionary = store.call("update_visual_profile_fields", profile_id, {
		"texture_path": profile.texture_path,
		"source_rect": profile.get("source_rect", null),
		"anchor": "footprint_center",
		"pixel_offset": {"x": 3, "y": -2},
		"y_sort_origin": "footprint_center",
		"render_size": {"width": 96, "height": 80},
		"expected_footprint_cells": {"width": changed_width, "height": int(definition.footprint_cells.height)},
		"visual_bounds": {"x": -8, "y": -12, "width": 112, "height": 96},
	})
	_expect(profile_edit.ok, "all mutable visual profile fields should update")
	_expect(store.call("get_validation_messages").is_empty(), "synchronized footprint edits should restore valid working data")
	_expect(store.call("is_dirty"), "mutable edits should mark the shared working copy dirty")

	var definitions_target := "user://building_config_tool_definitions.json"
	var profiles_target := "user://building_config_tool_profiles.json"
	var save_result: Dictionary = store.call("save", definitions_target, profiles_target)
	_expect(save_result.ok, "valid synchronized edits should save: %s" % save_result.get("error", ""))
	var saved_definitions := _load_json(definitions_target)
	var saved_profiles := _load_json(profiles_target)
	var saved_definition := _find_record(saved_definitions.get("definitions", []), definition_id)
	var saved_profile := _find_record(saved_profiles.get("profiles", []), profile_id)
	_expect(String(saved_definition.get("id", "")) == definition_id, "save should preserve stable definition ID")
	_expect(String(saved_profile.get("id", "")) == profile_id, "save should preserve stable profile ID")
	_expect(int(saved_definition.get("footprint_cells", {}).get("width", 0)) == changed_width, "save should persist definition edits")
	_expect(int(saved_profile.get("expected_footprint_cells", {}).get("width", 0)) == changed_width, "save should persist visual edits")
	_expect(not saved_definition.has("terrain_material_id"), "terrain selection should not be written to definitions")
	_expect(not saved_profile.has("terrain_material_id"), "terrain selection should not be written to profiles")

	var reload_store = BuildingConfigStoreScript.new()
	var reload_result: Dictionary = reload_store.load_data(definitions_target, profiles_target)
	_expect(reload_result.ok, "saved fixture should reload through the same store contract")
	if reload_result.ok:
		reload_store.update_definition_fields(definition_id, {"display_name": "Unsaved"})
		_expect(reload_store.is_dirty(), "fixture mutation should become dirty before reload")
		_expect(reload_store.reload().ok, "reload should restore data from disk")
		_expect(not reload_store.is_dirty(), "reload should discard unsaved working changes")
		var reloaded_definition: Dictionary = reload_store.get_definition(definition_id).definition
		_expect(String(reloaded_definition.display_name) != "Unsaved", "reload should restore persisted definition values")


func _verify_terrain_preview(store: RefCounted) -> void:
	var materials: Array[Dictionary] = store.call("get_terrain_materials")
	_expect(not materials.is_empty(), "terrain material catalog should populate preview choices")
	if materials.is_empty():
		return
	var definition: Dictionary = store.call("get_definitions")[0]
	var profile: Dictionary = store.call("get_assigned_profile", String(definition.id)).visual_profile
	var preview = BuildingVisualPreviewScript.new()
	preview.set_preview_data(definition, profile, materials[0])
	_expect(preview.get_terrain_material_id() == String(materials[0].id), "preview should retain exactly one selected terrain material")
	var padded_rect: Rect2 = preview.get_padded_content_rect()
	var footprint_size := Vector2(float(definition.footprint_cells.width), float(definition.footprint_cells.height)) * 32.0
	_expect(padded_rect.position.x <= -32.0 and padded_rect.position.y <= -32.0, "preview should pad at least one cell before the footprint")
	_expect(padded_rect.end.x >= footprint_size.x + 32.0 and padded_rect.end.y >= footprint_size.y + 32.0, "preview should pad at least one cell after the footprint")
	preview.free()


func _verify_synchronized_tabs() -> void:
	var dock = BuildingConfigDockScript.new()
	get_root().add_child(dock)
	await process_frame
	await process_frame
	_expect(dock.get_tab_count() == 2, "building configuration dock should expose Definition and Visual tabs")
	_expect(dock.get_active_tab_title() == "Definition", "Definition should be the first tab")
	var selected_id := dock.get_selected_definition_id()
	dock.set_active_tab(1)
	_expect(dock.get_active_tab_title() == "Visual", "second tab should be Visual")
	_expect(dock.get_selected_definition_id() == selected_id, "switching tabs should preserve the shared building selection")
	dock.queue_free()
	await process_frame


func _verify_runtime_outline(store: RefCounted) -> void:
	var definition: Dictionary = store.call("get_definitions")[0]
	var profile: Dictionary = store.call("get_assigned_profile", String(definition.id)).visual_profile
	var visual = BuildingEntityVisualScript.new()
	get_root().add_child(visual)
	var rect_size := Vector2(float(definition.footprint_cells.width), float(definition.footprint_cells.height)) * 32.0
	var configure_result: Dictionary = visual.configure(rect_size, Color.WHITE, profile)
	_expect(configure_result.ok, "sprite-backed runtime visual should configure for outline validation")
	_expect(not visual.is_highlight_outline_visible(), "normal sprite-backed rendering should omit the footprint outline")
	visual.set_highlight_color(Color.ORANGE, Color.RED, 4.0)
	_expect(visual.is_highlight_outline_visible(), "explicit highlight should enable its requested outline")
	visual.reset_highlight()
	_expect(not visual.is_highlight_outline_visible(), "reset highlight should return sprite-backed rendering to no outline")
	visual.queue_free()
	await process_frame


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_failures.append("Unable to read saved JSON file '%s'." % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _find_record(records: Array, record_id: String) -> Dictionary:
	for record in records:
		if String(record.get("id", "")) == record_id:
			return record
	return {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
