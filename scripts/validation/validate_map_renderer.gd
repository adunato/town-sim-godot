extends SceneTree

const GridMapModelScript := preload("res://scripts/map/grid_map_model.gd")
const MapRendererScript := preload("res://scripts/map/map_renderer.gd")
const MainScene := preload("res://scenes/main.tscn")

var _failures: Array[String] = []


func _initialize() -> void:
	await _run_checks()

	if _failures.is_empty():
		print("validate_map_renderer.gd: all checks passed")
		quit(0)
	else:
		for failure in _failures:
			printerr(failure)
		quit(1)


func _run_checks() -> void:
	var model := GridMapModelScript.new()
	var load_result: Dictionary = model.load_from_file()
	_expect(load_result.ok, "prototype_map.json should load for map renderer validation: %s" % load_result.get("error", ""))
	if not load_result.ok:
		return

	var renderer := MapRendererScript.new()
	get_root().add_child(renderer)
	renderer.call("set_map_model", model)

	_verify_scene_ownership()
	_verify_geometry(renderer, model)
	_verify_visual_contract(renderer)
	_verify_tilemap_contract(renderer, model)
	await _verify_startup_scene_runs()
	_verify_load_failure_reporting()

	renderer.queue_free()
	await process_frame
	await process_frame


func _verify_scene_ownership() -> void:
	var scene := MainScene.instantiate()
	get_root().add_child(scene)
	await process_frame

	_expect(scene.has_node("World"), "main scene should contain World branch")
	_expect(scene.has_node("World/Map"), "main scene should contain World/Map renderer")
	_expect(scene.get_node("World/Map").get_script() == MapRendererScript, "World/Map should use map_renderer.gd")
	_expect(scene.get_node("World/Map").has_node("TerrainTileMapLayer"), "World/Map should own TerrainTileMapLayer")
	_expect(scene.get_node("World").get_child(0).name == "Map", "Map renderer should be the first World child")
	_expect(scene.get_node("World/Map").z_index < scene.get_node("World/DebugOverlay").z_index, "Map renderer should draw below DebugOverlay")

	scene.queue_free()
	await process_frame
	await process_frame


func _verify_geometry(renderer: Node, model: RefCounted) -> void:
	var bounds: Rect2 = renderer.call("get_map_bounds")
	var expected_size := Vector2(model.grid_width, model.grid_height) * float(model.cell_size)
	_expect(bounds.position == model.origin, "map bounds origin should match GridMapModel origin")
	_expect(bounds.size == expected_size, "map bounds size should match grid dimensions and cell size")

	var first_cell: Rect2 = renderer.call("get_cell_rect", Vector2i.ZERO)
	_expect(first_cell.position == model.origin, "cell (0, 0) should start at map origin")
	_expect(first_cell.size == Vector2.ONE * float(model.cell_size), "cell rect size should match GridMapModel cell_size")

	var sample_cell := Vector2i(3, 2)
	var sample_rect: Rect2 = renderer.call("get_cell_rect", sample_cell)
	var expected_position: Vector2 = model.origin + Vector2(sample_cell) * float(model.cell_size)
	_expect(sample_rect.position == expected_position, "sample cell rect should use configured origin and cell size")


func _verify_visual_contract(renderer: Node) -> void:
	var fill_a: Color = renderer.call("get_cell_fill_color", Vector2i(0, 0))
	var fill_b: Color = renderer.call("get_cell_fill_color", Vector2i(1, 0))
	var fill_a_again: Color = renderer.call("get_cell_fill_color", Vector2i(1, 1))
	_expect(fill_a != fill_b, "adjacent cells should use different checkered fill colours")
	_expect(fill_a == fill_a_again, "cells with matching coordinate parity should use the same fill colour")
	_expect(_is_light_green(fill_a), "cell fill A should be light green")
	_expect(_is_light_green(fill_b), "cell fill B should be light green")
	_expect(_color_distance(fill_a, fill_b) < 0.18, "checkered fill colours should be close green shades")

	var border_color: Color = renderer.call("get_cell_border_color")
	var boundary_color: Color = renderer.call("get_map_boundary_color")
	var border_width: float = renderer.call("get_cell_border_width")
	var boundary_width: float = renderer.call("get_map_boundary_width")
	_expect(border_color.a < boundary_color.a, "cell border should be lower opacity than outer map boundary")
	_expect(border_width < boundary_width, "outer map boundary should be wider than internal cell borders")


func _verify_tilemap_contract(renderer: Node, model: RefCounted) -> void:
	var terrain_layer: TileMapLayer = renderer.call("get_terrain_layer")
	_expect(terrain_layer != null, "map renderer should expose TerrainTileMapLayer")
	_expect(terrain_layer.tile_set != null, "TerrainTileMapLayer should have a play TileSet")
	_expect(terrain_layer.position == model.origin, "TerrainTileMapLayer position should match GridMapModel origin")
	_expect(renderer.call("get_populated_terrain_tile_count") == model.grid_width * model.grid_height, "TerrainTileMapLayer should contain one tile per configured cell")
	_expect(renderer.call("get_terrain_tile_source_id", Vector2i(0, 0)) == 0, "cell (0, 0) should use play tile source A")
	_expect(renderer.call("get_terrain_tile_source_id", Vector2i(1, 0)) == 1, "cell (1, 0) should use play tile source B")
	_expect(renderer.call("get_terrain_tile_source_id", Vector2i(0, 1)) == 1, "cell (0, 1) should use play tile source B")
	_expect(renderer.call("get_terrain_tile_source_id", Vector2i(1, 1)) == 0, "cell (1, 1) should use play tile source A")
	_expect(terrain_layer.get_cell_source_id(Vector2i(0, 0)) == 0, "TerrainTileMapLayer should place source A at cell (0, 0)")
	_expect(terrain_layer.get_cell_source_id(Vector2i(1, 0)) == 1, "TerrainTileMapLayer should place source B at cell (1, 0)")


func _verify_startup_scene_runs() -> void:
	var scene := MainScene.instantiate()
	get_root().add_child(scene)
	await process_frame

	var map := scene.get_node("World/Map")
	_expect(map.call("has_map_model"), "startup scene Map renderer should have a loaded map model")
	_expect(map.call("get_load_error").is_empty(), "startup scene Map renderer should not report a load error")
	_expect(map.call("get_populated_terrain_tile_count") > 0, "startup scene Map renderer should populate terrain tiles")

	scene.queue_free()
	await process_frame
	await process_frame


func _verify_load_failure_reporting() -> void:
	var renderer := MapRendererScript.new()
	renderer.set("config_path", "res://data/maps/does_not_exist.json")
	var result: Dictionary = renderer.call("load_default_map", false)
	_expect(not result.ok, "map renderer should fail when configured map file is missing")
	_expect(not renderer.call("get_load_error").is_empty(), "map renderer should retain concrete load error text")
	renderer.free()


func _is_light_green(color: Color) -> bool:
	return color.g > color.r and color.g > color.b and color.r > color.b and color.g > 0.65


func _color_distance(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
