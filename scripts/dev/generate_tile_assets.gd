extends SceneTree

const TILE_SIZE := 32

const PLAY_TILESET_PATH := "res://resources/tilesets/play_cells.tres"
const DEBUG_TILESET_PATH := "res://resources/tilesets/debug_cell_states.tres"
const PLAY_ATLAS_PATH := "res://assets/tiles/play/play_cells_atlas.png"
const DEBUG_ATLAS_PATH := "res://assets/tiles/debug/debug_cell_states_atlas.png"
const PLAY_TILE_ORDER: PackedStringArray = ["grass_a", "grass_b"]
const DEBUG_TILE_ORDER: PackedStringArray = ["walkable", "blocked", "occupied", "reserved", "protected"]

const PLAY_TILES := {
	"grass_a": {
		"atlas_coords": Vector2i(0, 0),
		"color": Color(0.55, 0.78, 0.42, 1.0),
	},
	"grass_b": {
		"atlas_coords": Vector2i(1, 0),
		"color": Color(0.51, 0.75, 0.39, 1.0),
	},
}

const DEBUG_TILES := {
	"walkable": {
		"atlas_coords": Vector2i(0, 0),
		"color": Color(0.15, 0.95, 0.25, 0.34),
	},
	"blocked": {
		"atlas_coords": Vector2i(1, 0),
		"color": Color(1.0, 0.1, 0.1, 0.48),
	},
	"occupied": {
		"atlas_coords": Vector2i(2, 0),
		"color": Color(1.0, 0.5, 0.0, 0.48),
	},
	"reserved": {
		"atlas_coords": Vector2i(3, 0),
		"color": Color(0.1, 0.45, 1.0, 0.58),
	},
	"protected": {
		"atlas_coords": Vector2i(4, 0),
		"color": Color(0.85, 0.25, 1.0, 0.62),
	},
}


func _initialize() -> void:
	var failures: Array[String] = []
	failures.append_array(_write_tile_atlas(PLAY_ATLAS_PATH, PLAY_TILES, PLAY_TILE_ORDER))
	failures.append_array(_write_tile_atlas(DEBUG_ATLAS_PATH, DEBUG_TILES, DEBUG_TILE_ORDER))
	failures.append_array(_write_tileset(PLAY_TILESET_PATH, PLAY_ATLAS_PATH, PLAY_TILES, PLAY_TILE_ORDER))
	failures.append_array(_write_tileset(DEBUG_TILESET_PATH, DEBUG_ATLAS_PATH, DEBUG_TILES, DEBUG_TILE_ORDER))

	if failures.is_empty():
		print("generate_tile_assets.gd: generated play/debug tiles and tilesets")
		quit(0)
	else:
		for failure in failures:
			printerr(failure)
		quit(1)


func _write_tile_atlas(path: String, tiles: Dictionary, tile_order: PackedStringArray) -> Array[String]:
	var failures: Array[String] = []
	var image := Image.create(TILE_SIZE * tile_order.size(), TILE_SIZE, false, Image.FORMAT_RGBA8)
	for tile_name in tile_order:
		var tile: Dictionary = tiles[tile_name]
		var rect := Rect2i(tile.atlas_coords * TILE_SIZE, Vector2i(TILE_SIZE, TILE_SIZE))
		image.fill_rect(rect, tile.color)
	var dir_result := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if dir_result != OK:
		failures.append("Unable to create tile atlas directory for '%s': %s" % [path, error_string(dir_result)])
		return failures
	var save_result := image.save_png(path)
	if save_result != OK:
		failures.append("Unable to save tile atlas '%s': %s" % [path, error_string(save_result)])
	return failures


func _write_tileset(path: String, atlas_path: String, tiles: Dictionary, tile_order: PackedStringArray) -> Array[String]:
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
	lines.append("[gd_resource type=\"TileSet\" load_steps=3 format=3]")
	lines.append("")
	lines.append("[ext_resource type=\"Texture2D\" path=\"%s\" id=\"1_atlas\"]" % atlas_path)
	lines.append("")
	lines.append("[sub_resource type=\"TileSetAtlasSource\" id=\"TileSetAtlasSource_atlas\"]")
	lines.append("texture = ExtResource(\"1_atlas\")")
	lines.append("texture_region_size = Vector2i(%d, %d)" % [TILE_SIZE, TILE_SIZE])
	for tile_name in tile_order:
		var tile: Dictionary = tiles[tile_name]
		lines.append("%d:%d/0 = 0" % [tile.atlas_coords.x, tile.atlas_coords.y])
	lines.append("")

	lines.append("[resource]")
	lines.append("tile_size = Vector2i(%d, %d)" % [TILE_SIZE, TILE_SIZE])
	lines.append("sources/0 = SubResource(\"TileSetAtlasSource_atlas\")")

	file.store_string("\n".join(lines) + "\n")
	return failures
