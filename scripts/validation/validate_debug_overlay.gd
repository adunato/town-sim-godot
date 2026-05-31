extends SceneTree

const DebugOverlayScript := preload("res://scripts/debug/debug_overlay.gd")
const FixtureScene := preload("res://scenes/debug/debug_overlay_fixture.tscn")
const GridMapModelScript := preload("res://scripts/map/grid_map_model.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	await _run_checks()

	if _failures.is_empty():
		print("validate_debug_overlay.gd: all checks passed")
		quit(0)
	else:
		for failure in _failures:
			printerr(failure)
		quit(1)


func _run_checks() -> void:
	var model := GridMapModelScript.new()
	var load_result: Dictionary = model.load_from_file()
	_expect(load_result.ok, "prototype_map.json should load for debug overlay validation: %s" % load_result.get("error", ""))
	if not load_result.ok:
		return

	var overlay := DebugOverlayScript.new()
	get_root().add_child(overlay)
	overlay.call("set_map_model", model)

	_expect(not overlay.call("is_overlay_enabled"), "overlay should be hidden by default")
	_expect(overlay.get("current_mode") == "grid", "overlay should start in grid mode")
	_expect(_legend_contains(overlay.call("get_legend_entries"), "map boundary"), "grid legend should include map boundary")
	_expect(_legend_contains(overlay.call("get_legend_entries"), "grid lines"), "grid legend should include grid lines")

	overlay.call("toggle_overlay")
	_expect(overlay.call("is_overlay_enabled"), "toggle command should show overlay")
	overlay.call("toggle_overlay")
	_expect(not overlay.call("is_overlay_enabled"), "toggle command should hide overlay")

	var expected_modes: PackedStringArray = ["cells", "physics", "entities", "all", "grid"]
	for expected_mode in expected_modes:
		overlay.call("cycle_mode")
		_expect(overlay.get("current_mode") == expected_mode, "cycle command expected mode '%s', got '%s'" % [expected_mode, overlay.get("current_mode")])

	overlay.set("current_mode", "cells")
	_expect(_legend_contains(overlay.call("get_legend_entries"), "walkable cell"), "cells legend should include walkable cells")
	_expect(_legend_contains(overlay.call("get_legend_entries"), "protected cell"), "cells legend should include protected cells")

	overlay.set("current_mode", "physics")
	_expect(_legend_contains(overlay.call("get_legend_entries"), "player collision"), "physics legend should include player collision")
	_expect(_legend_contains(overlay.call("get_legend_entries"), "proximity range"), "physics legend should include proximity range")

	overlay.set("current_mode", "entities")
	_expect(_legend_contains(overlay.call("get_legend_entries"), "hovered target"), "entities legend should include hovered target")
	_expect(_legend_contains(overlay.call("get_legend_entries"), "id | display name | type"), "entities legend should include entity label format")

	overlay.set("current_mode", "all")
	_expect(_legend_contains(overlay.call("get_legend_entries"), "walkable cell"), "all legend should include cell diagnostics")
	_expect(_legend_contains(overlay.call("get_legend_entries"), "player collision"), "all legend should include physics diagnostics")
	_expect(_legend_contains(overlay.call("get_legend_entries"), "hovered target"), "all legend should include entity diagnostics")

	await _verify_fixture_scene_contracts()


func _verify_fixture_scene_contracts() -> void:
	var fixture := FixtureScene.instantiate()
	get_root().add_child(fixture)
	await process_frame

	var overlay := fixture.get_node("World/DebugOverlay")
	var readout := fixture.get_node("UI/DebugReadout")
	_expect(overlay.call("is_overlay_enabled"), "fixture overlay should start visible for visual validation")
	_expect(overlay.get("current_mode") == "grid", "fixture overlay should start in grid mode")
	_expect(readout.visible, "fixture readout should be visible")
	_expect(get_nodes_in_group("debug_building_footprints").size() > 0, "fixture should expose building footprint debug nodes")
	_expect(get_nodes_in_group("debug_player_collision").size() > 0, "fixture should expose player collision debug nodes")
	_expect(get_nodes_in_group("debug_building_collision").size() > 0, "fixture should expose building collision debug nodes")
	_expect(get_nodes_in_group("debug_proximity").size() > 0, "fixture should expose proximity debug nodes")
	_expect(get_nodes_in_group("debug_entity_labels").size() >= 3, "fixture should expose entity label debug nodes")
	_expect(get_nodes_in_group("debug_hovered_target").size() > 0, "fixture should expose hovered target debug nodes")
	_expect(get_nodes_in_group("debug_selected_target").size() > 0, "fixture should expose selected target debug nodes")

	fixture.queue_free()


func _legend_contains(entries: PackedStringArray, fragment: String) -> bool:
	for entry in entries:
		if entry.contains(fragment):
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
