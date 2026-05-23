extends Node2D

@export var walkable_color := Color(0.1, 0.75, 1.0, 0.24)
@export var blocked_color := Color(1.0, 0.16, 0.12, 0.08)
@export var current_tile_color := Color(1.0, 0.9, 0.15, 0.55)

var map_loader: Node
var player: CharacterBody2D
var is_visible := true
var canvas_layer: CanvasLayer
var status_label: Label


func _ready() -> void:
	canvas_layer = CanvasLayer.new()
	add_child(canvas_layer)
	status_label = Label.new()
	status_label.position = Vector2(12, 12)
	status_label.add_theme_color_override("font_color", Color.WHITE)
	status_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	status_label.add_theme_constant_override("shadow_offset_x", 1)
	status_label.add_theme_constant_override("shadow_offset_y", 1)
	canvas_layer.add_child(status_label)


func setup(loader: Node, player_node: CharacterBody2D) -> void:
	map_loader = loader
	player = player_node
	queue_redraw()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("toggle_debug_overlay"):
		is_visible = not is_visible
		visible = is_visible
		canvas_layer.visible = is_visible
	if is_visible:
		_update_status()
		queue_redraw()


func _draw() -> void:
	if map_loader == null or not map_loader.is_loaded:
		return

	var map_size: Vector2i = map_loader.get_map_size()
	var tile_size: int = map_loader.get_tile_size()
	for y in range(map_size.y):
		for x in range(map_size.x):
			var tile := Vector2i(x, y)
			var tile_color := walkable_color if map_loader.is_tile_walkable(tile) else blocked_color
			var top_left: Vector2 = map_loader.tile_to_world(tile) - Vector2(tile_size / 2.0, tile_size / 2.0)
			draw_rect(Rect2(to_local(top_left), Vector2(tile_size, tile_size)), tile_color, true)

	if player != null:
		var current_tile: Vector2i = map_loader.world_to_tile(player.global_position)
		var current_top_left: Vector2 = map_loader.tile_to_world(current_tile) - Vector2(tile_size / 2.0, tile_size / 2.0)
		draw_rect(Rect2(to_local(current_top_left), Vector2(tile_size, tile_size)), current_tile_color, false, 2.0)


func _update_status() -> void:
	if status_label == null:
		return
	if map_loader == null or not map_loader.is_loaded or player == null:
		status_label.text = "Debug: waiting for map"
		return

	var tile: Vector2i = map_loader.world_to_tile(player.global_position)
	var walkable: bool = map_loader.is_tile_walkable(tile)
	var warnings: Array[String] = map_loader.get_validation_warnings()
	var lines: Array[String] = [
		"Debug overlay",
		"Player tile: [%d, %d]" % [tile.x, tile.y],
		"Walkable: %s" % str(walkable)
	]
	for warning in warnings:
		lines.append("Warning: %s" % warning)
	status_label.text = "\n".join(lines)
