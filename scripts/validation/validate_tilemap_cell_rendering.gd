extends SceneTree

const TILE_SIZE := 32
const PLAY_TILESET_PATH := "res://resources/tilesets/play_cells.tres"
const DEBUG_TILESET_PATH := "res://resources/tilesets/debug_cell_states.tres"
const PLAY_TILE_PATHS: PackedStringArray = [
	"res://assets/tiles/play/grass_a.png",
	"res://assets/tiles/play/grass_b.png",
]
const DEBUG_TILE_PATHS: PackedStringArray = [
	"res://assets/tiles/debug/walkable.png",
	"res://assets/tiles/debug/blocked.png",
	"res://assets/tiles/debug/occupied.png",
	"res://assets/tiles/debug/reserved.png",
	"res://assets/tiles/debug/protected.png",
]

var _failures: Array[String] = []


func _initialize() -> void:
	_verify_generated_images(PLAY_TILE_PATHS)
	_verify_generated_images(DEBUG_TILE_PATHS)
	_verify_tileset_file(PLAY_TILESET_PATH, PLAY_TILE_PATHS, 2)
	_verify_tileset_file(DEBUG_TILESET_PATH, DEBUG_TILE_PATHS, 5)

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
		_expect(image.get_width() == TILE_SIZE, "generated tile image width should be %d: %s" % [TILE_SIZE, path])
		_expect(image.get_height() == TILE_SIZE, "generated tile image height should be %d: %s" % [TILE_SIZE, path])


func _verify_tileset_file(path: String, expected_texture_paths: PackedStringArray, expected_sources: int) -> void:
	_expect(FileAccess.file_exists(path), "tileset resource file should exist: %s" % path)
	var file := FileAccess.open(path, FileAccess.READ)
	_expect(file != null, "tileset resource file should be readable: %s" % path)
	if file == null:
		return
	var text := file.get_as_text()
	_expect(text.contains("[gd_resource type=\"TileSet\""), "tileset file should declare a TileSet resource: %s" % path)
	_expect(text.contains("tile_size = Vector2i(%d, %d)" % [TILE_SIZE, TILE_SIZE]), "tileset file should declare %dx%d tile_size: %s" % [TILE_SIZE, TILE_SIZE, path])
	for texture_path in expected_texture_paths:
		_expect(text.contains("path=\"%s\"" % texture_path), "tileset should reference generated texture: %s -> %s" % [path, texture_path])
	for source_id in range(expected_sources):
		_expect(text.contains("sources/%d = SubResource" % source_id), "tileset should contain source id %d: %s" % [source_id, path])
	_expect(text.count("0:0/0 = 0") == expected_sources, "tileset should expose one atlas tile per source: %s" % path)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
