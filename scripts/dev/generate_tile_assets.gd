extends SceneTree

const TILE_SIZE := 32

const PLAY_TILESET_PATH := "res://resources/tilesets/play_cells.tres"
const DEBUG_TILESET_PATH := "res://resources/tilesets/debug_cell_states.tres"
const PLAY_TILE_ORDER: PackedStringArray = ["grass_a", "grass_b"]
const DEBUG_TILE_ORDER: PackedStringArray = ["walkable", "blocked", "occupied", "reserved", "protected"]

const PLAY_TILES := {
	"grass_a": {
		"path": "res://assets/tiles/play/grass_a.png",
		"source_id": 0,
		"color": Color(0.55, 0.78, 0.42, 1.0),
	},
	"grass_b": {
		"path": "res://assets/tiles/play/grass_b.png",
		"source_id": 1,
		"color": Color(0.51, 0.75, 0.39, 1.0),
	},
}

const DEBUG_TILES := {
	"walkable": {
		"path": "res://assets/tiles/debug/walkable.png",
		"source_id": 0,
		"color": Color(0.15, 0.95, 0.25, 0.34),
	},
	"blocked": {
		"path": "res://assets/tiles/debug/blocked.png",
		"source_id": 1,
		"color": Color(1.0, 0.1, 0.1, 0.48),
	},
	"occupied": {
		"path": "res://assets/tiles/debug/occupied.png",
		"source_id": 2,
		"color": Color(1.0, 0.5, 0.0, 0.48),
	},
	"reserved": {
		"path": "res://assets/tiles/debug/reserved.png",
		"source_id": 3,
		"color": Color(0.1, 0.45, 1.0, 0.58),
	},
	"protected": {
		"path": "res://assets/tiles/debug/protected.png",
		"source_id": 4,
		"color": Color(0.85, 0.25, 1.0, 0.62),
	},
}


func _initialize() -> void:
	var failures: Array[String] = []
	failures.append_array(_write_tile_images(PLAY_TILES))
	failures.append_array(_write_tile_images(DEBUG_TILES))
	failures.append_array(_write_tileset(PLAY_TILESET_PATH, PLAY_TILES, PLAY_TILE_ORDER))
	failures.append_array(_write_tileset(DEBUG_TILESET_PATH, DEBUG_TILES, DEBUG_TILE_ORDER))

	if failures.is_empty():
		print("generate_tile_assets.gd: generated play/debug tiles and tilesets")
		quit(0)
	else:
		for failure in failures:
			printerr(failure)
		quit(1)


func _write_tile_images(tiles: Dictionary) -> Array[String]:
	var failures: Array[String] = []
	for tile_name in tiles:
		var tile: Dictionary = tiles[tile_name]
		var image := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
		image.fill(tile.color)
		var path := String(tile.path)
		var dir_result := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		if dir_result != OK:
			failures.append("Unable to create tile directory for '%s': %s" % [path, error_string(dir_result)])
			continue
		var save_result := image.save_png(path)
		if save_result != OK:
			failures.append("Unable to save tile image '%s': %s" % [path, error_string(save_result)])
	return failures


func _write_tileset(path: String, tiles: Dictionary, tile_order: PackedStringArray) -> Array[String]:
	var failures: Array[String] = []
	var dir_result := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if dir_result != OK:
		failures.append("Unable to create tileset directory for '%s': %s" % [path, error_string(dir_result)])
		return failures

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		failures.append("Unable to write tileset '%s': %s" % [path, error_string(FileAccess.get_open_error())])
		return failures

	var lines: PackedStringArray = []
	lines.append("[gd_resource type=\"TileSet\" load_steps=%d format=3]" % [tile_order.size() * 2 + 1])
	lines.append("")

	var index := 1
	for tile_name in tile_order:
		var tile: Dictionary = tiles[tile_name]
		lines.append("[ext_resource type=\"Texture2D\" path=\"%s\" id=\"%d_%s\"]" % [tile.path, index, tile_name])
		index += 1
	lines.append("")

	index = 1
	for tile_name in tile_order:
		lines.append("[sub_resource type=\"TileSetAtlasSource\" id=\"TileSetAtlasSource_%s\"]" % tile_name)
		lines.append("texture = ExtResource(\"%d_%s\")" % [index, tile_name])
		lines.append("texture_region_size = Vector2i(%d, %d)" % [TILE_SIZE, TILE_SIZE])
		lines.append("0:0/0 = 0")
		lines.append("")
		index += 1

	lines.append("[resource]")
	lines.append("tile_size = Vector2i(%d, %d)" % [TILE_SIZE, TILE_SIZE])
	for tile_name in tile_order:
		var tile: Dictionary = tiles[tile_name]
		lines.append("sources/%d = SubResource(\"TileSetAtlasSource_%s\")" % [int(tile.source_id), tile_name])

	file.store_string("\n".join(lines) + "\n")
	return failures
