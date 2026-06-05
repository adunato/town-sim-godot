extends SceneTree

const TILE_SIZE := 32
const PLAY_TILESET_PATH := "res://resources/tilesets/play_cells.tres"
const DEBUG_TILESET_PATH := "res://resources/tilesets/debug_cell_states.tres"
const PLAY_ATLAS_PATH := "res://assets/tiles/play/play_cells_atlas.png"
const DEBUG_ATLAS_PATH := "res://assets/tiles/debug/debug_cell_states_atlas.png"
const PLAY_TILE_PATHS: PackedStringArray = [
	PLAY_ATLAS_PATH,
]
const DEBUG_TILE_PATHS: PackedStringArray = [
	DEBUG_ATLAS_PATH,
]

var _failures: Array[String] = []


func _initialize() -> void:
	_verify_generated_images(PLAY_TILE_PATHS)
	_verify_generated_images(DEBUG_TILE_PATHS)
	_verify_atlas_dimensions(PLAY_ATLAS_PATH, 2)
	_verify_atlas_dimensions(DEBUG_ATLAS_PATH, 5)
	_verify_tileset_file(PLAY_TILESET_PATH, PLAY_ATLAS_PATH, 2)
	_verify_tileset_file(DEBUG_TILESET_PATH, DEBUG_ATLAS_PATH, 5)

	if _failures.is_empty():
		print("validate_tilemap_cell_rendering.gd: all checks passed")
		quit(0)
	else:
		for failure in _failures:
			printerr(failure)
		quit(1)


func _verify_generated_images(paths: PackedStringArray) -> void:
	for path in paths:
		_expect(FileAccess.file_exists(path), "generated tile image should exist: %s" % path)
		var image := Image.new()
		var load_result := image.load(path)
		_expect(load_result == OK, "generated tile image should load: %s" % path)
		if load_result != OK:
			continue
		_expect(image.get_width() >= TILE_SIZE, "generated tile image width should be at least %d: %s" % [TILE_SIZE, path])
		_expect(image.get_height() == TILE_SIZE, "generated tile image height should be %d: %s" % [TILE_SIZE, path])


func _verify_atlas_dimensions(path: String, expected_tiles: int) -> void:
	var image := Image.new()
	var load_result := image.load(path)
	_expect(load_result == OK, "generated atlas should load: %s" % path)
	if load_result != OK:
		return
	_expect(image.get_width() == TILE_SIZE * expected_tiles, "generated atlas width should contain %d tiles: %s" % [expected_tiles, path])
	_expect(image.get_height() == TILE_SIZE, "generated atlas height should be one tile: %s" % path)


func _verify_tileset_file(path: String, expected_texture_path: String, expected_tiles: int) -> void:
	_expect(FileAccess.file_exists(path), "tileset resource file should exist: %s" % path)
	var file := FileAccess.open(path, FileAccess.READ)
	_expect(file != null, "tileset resource file should be readable: %s" % path)
	if file == null:
		return
	var text := file.get_as_text()
	_expect(text.contains("[gd_resource type=\"TileSet\""), "tileset file should declare a TileSet resource: %s" % path)
	_expect(text.contains("tile_size = Vector2i(%d, %d)" % [TILE_SIZE, TILE_SIZE]), "tileset file should declare %dx%d tile_size: %s" % [TILE_SIZE, TILE_SIZE, path])
	_expect(text.contains("path=\"%s\"" % expected_texture_path), "tileset should reference generated atlas: %s -> %s" % [path, expected_texture_path])
	_expect(text.contains("sources/0 = SubResource"), "tileset should contain one shared source id 0: %s" % path)
	for x in range(expected_tiles):
		_expect(text.contains("%d:0/0 = 0" % x), "tileset should expose atlas tile (%d, 0): %s" % [x, path])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
