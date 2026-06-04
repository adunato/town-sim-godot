class_name DebugOverlay
extends Node2D

signal debug_state_changed(is_enabled: bool, mode: String, legend_entries: PackedStringArray)

const MODE_GRID := "grid"
const MODE_CELLS := "cells"
const MODE_PHYSICS := "physics"
const MODE_ENTITIES := "entities"
const MODE_ALL := "all"
const MODES: PackedStringArray = [MODE_GRID, MODE_CELLS, MODE_PHYSICS, MODE_ENTITIES, MODE_ALL]

const COLOR_BOUNDARY := Color(1.0, 1.0, 1.0, 0.95)
const COLOR_GRID := Color(1.0, 1.0, 1.0, 0.30)
const COLOR_WALKABLE := Color(0.15, 0.95, 0.25, 0.34)
const COLOR_BLOCKED := Color(1.0, 0.1, 0.1, 0.48)
const COLOR_OCCUPIED := Color(1.0, 0.5, 0.0, 0.48)
const COLOR_RESERVED := Color(0.1, 0.45, 1.0, 0.58)
const COLOR_PROTECTED := Color(0.85, 0.25, 1.0, 0.62)
const COLOR_FOOTPRINT := Color(1.0, 0.9, 0.1, 0.9)
const COLOR_PLAYER := Color(0.1, 0.9, 1.0, 0.9)
const COLOR_BUILDING_COLLISION := Color(1.0, 0.1, 0.1, 0.85)
const COLOR_PROXIMITY_TARGET := Color(0.1, 0.9, 1.0, 0.70)
const COLOR_HOVER := Color(1.0, 0.9, 0.1, 0.95)
const COLOR_SELECTED := Color(1.0, 1.0, 1.0, 0.95)
const COLOR_LABEL := Color(1.0, 1.0, 1.0, 0.95)

var current_mode := MODE_GRID

var _is_enabled := false
var _map_model: RefCounted
var _mode_index := 0
var _proximity_snapshot_source: Node


func _ready() -> void:
	visible = false
	z_index = 100


func _process(_delta: float) -> void:
	if _is_enabled and (current_mode == MODE_PHYSICS or current_mode == MODE_ENTITIES or current_mode == MODE_ALL):
		queue_redraw()


func set_map_model(map_model: RefCounted) -> void:
	_map_model = map_model
	queue_redraw()
	_emit_debug_state()


func set_proximity_snapshot_source(source: Node) -> void:
	_proximity_snapshot_source = source
	queue_redraw()


func is_overlay_enabled() -> bool:
	return _is_enabled


func toggle_overlay() -> void:
	_is_enabled = not _is_enabled
	visible = _is_enabled
	queue_redraw()
	_emit_debug_state()


func cycle_mode() -> void:
	_mode_index = (_mode_index + 1) % MODES.size()
	current_mode = MODES[_mode_index]
	queue_redraw()
	_emit_debug_state()


func get_legend_entries() -> PackedStringArray:
	match current_mode:
		MODE_GRID:
			return _grid_legend()
		MODE_CELLS:
			return _cells_legend()
		MODE_PHYSICS:
			return _physics_legend()
		MODE_ENTITIES:
			return _entities_legend()
		MODE_ALL:
			var entries := PackedStringArray()
			entries.append_array(_cells_legend())
			for entry in _physics_legend():
				if not entries.has(entry):
					entries.append(entry)
			for entry in _entities_legend():
				if not entries.has(entry):
					entries.append(entry)
			return entries
		_:
			return PackedStringArray()


func _draw() -> void:
	if not _is_enabled or _map_model == null:
		return

	match current_mode:
		MODE_GRID:
			_draw_grid_mode()
		MODE_CELLS:
			_draw_cells_mode()
		MODE_PHYSICS:
			_draw_physics_mode()
		MODE_ENTITIES:
			_draw_entities_mode()
		MODE_ALL:
			_draw_cells_mode()
			_draw_physics_mode()
			_draw_entities_mode()


func _draw_grid_mode() -> void:
	_draw_map_reference()


func _draw_cells_mode() -> void:
	_draw_cell_states()
	_draw_map_reference()
	_draw_building_footprints()


func _draw_physics_mode() -> void:
	_draw_map_boundary()
	_draw_collision_group("debug_player_collision", COLOR_PLAYER)
	_draw_collision_group("debug_building_collision", COLOR_BUILDING_COLLISION)
	_draw_proximity_ranges()
	_draw_nearby_proximity_targets()


func _draw_entities_mode() -> void:
	_draw_entity_labels()
	_draw_target_markers("debug_selected_target", COLOR_SELECTED, 8.0)
	_draw_target_markers("debug_hovered_target", COLOR_HOVER, 5.0)


func _draw_map_reference() -> void:
	_draw_map_boundary()
	_draw_grid_lines()
	_draw_origin_marker()


func _draw_map_boundary() -> void:
	var map_size := Vector2(_map_model.grid_width, _map_model.grid_height) * float(_map_model.cell_size)
	draw_rect(Rect2(_map_model.origin, map_size), COLOR_BOUNDARY, false, 2.0)


func _draw_grid_lines() -> void:
	var width := float(_map_model.grid_width * _map_model.cell_size)
	var height := float(_map_model.grid_height * _map_model.cell_size)
	for x in range(_map_model.grid_width + 1):
		var column_x: float = _map_model.origin.x + float(x * _map_model.cell_size)
		draw_line(Vector2(column_x, _map_model.origin.y), Vector2(column_x, _map_model.origin.y + height), COLOR_GRID, 1.0)
	for y in range(_map_model.grid_height + 1):
		var row_y: float = _map_model.origin.y + float(y * _map_model.cell_size)
		draw_line(Vector2(_map_model.origin.x, row_y), Vector2(_map_model.origin.x + width, row_y), COLOR_GRID, 1.0)


func _draw_origin_marker() -> void:
	var origin: Vector2 = _map_model.origin
	var marker_size := float(_map_model.cell_size) * 0.45
	draw_circle(origin, 5.0, COLOR_BOUNDARY)
	draw_line(origin, origin + Vector2(marker_size, 0.0), COLOR_BOUNDARY, 3.0)
	draw_line(origin, origin + Vector2(0.0, marker_size), COLOR_BOUNDARY, 3.0)
	draw_string(ThemeDB.fallback_font, origin + Vector2(8.0, 18.0), "(0,0)", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, COLOR_LABEL)


func _draw_cell_states() -> void:
	var font := ThemeDB.fallback_font
	for y in range(_map_model.grid_height):
		for x in range(_map_model.grid_width):
			var cell := Vector2i(x, y)
			var cell_rect := _cell_rect(cell)
			if _map_model.is_walkable(cell):
				draw_rect(cell_rect, COLOR_WALKABLE, true)
			if _map_model.is_blocked(cell):
				draw_rect(cell_rect, COLOR_BLOCKED, true)
			if _map_model.is_occupied(cell):
				draw_rect(cell_rect, COLOR_OCCUPIED, true)
			if _map_model.is_reserved(cell):
				draw_rect(cell_rect, COLOR_RESERVED, true)
			if _map_model.is_protected(cell):
				draw_rect(cell_rect, COLOR_PROTECTED, true)
			var state_label := _cell_state_label(cell)
			if not state_label.is_empty():
				draw_rect(cell_rect, Color(1.0, 1.0, 1.0, 0.9), false, 2.0)
				_draw_centered_cell_label(font, cell_rect, state_label)


func _draw_building_footprints() -> void:
	for node in get_tree().get_nodes_in_group("debug_building_footprints"):
		for cell in _read_footprint_cells(node):
			draw_rect(_cell_rect(cell), COLOR_FOOTPRINT, false, 2.0)


func _draw_collision_group(group_name: StringName, color: Color) -> void:
	for node in get_tree().get_nodes_in_group(group_name):
		_draw_collision_shapes(node, color)


func _draw_collision_shapes(root: Node, color: Color) -> void:
	if root is CollisionShape2D:
		_draw_collision_shape(root, color)
	for child in root.get_children():
		if child is Node:
			_draw_collision_shapes(child, color)


func _draw_collision_shape(collision_shape: CollisionShape2D, color: Color) -> void:
	if collision_shape.shape == null:
		return

	var transform := collision_shape.global_transform
	if collision_shape.shape is RectangleShape2D:
		var rect_shape := collision_shape.shape as RectangleShape2D
		var rect := Rect2(-rect_shape.size * 0.5, rect_shape.size)
		draw_set_transform_matrix(transform)
		draw_rect(rect, color, false, 2.0)
		draw_set_transform_matrix(Transform2D.IDENTITY)
	elif collision_shape.shape is CircleShape2D:
		var circle_shape := collision_shape.shape as CircleShape2D
		draw_circle(transform.origin, circle_shape.radius * transform.get_scale().x, Color(color, 0.08))
		draw_arc(transform.origin, circle_shape.radius * transform.get_scale().x, 0.0, TAU, 48, color, 2.0)


func _draw_proximity_ranges() -> void:
	var snapshot := _read_proximity_snapshot()
	if not snapshot.is_empty():
		var radius := float(snapshot.get("proximity_radius", 0.0))
		var center: Vector2 = snapshot.get("player_world_position", Vector2.ZERO)
		if radius > 0.0:
			draw_arc(center, radius, 0.0, TAU, 64, COLOR_PLAYER, 2.0)
		return

	for node in get_tree().get_nodes_in_group("debug_proximity"):
		var radius := _read_float(node, "proximity_radius", "get_proximity_radius")
		if radius <= 0.0:
			continue
		var center := _read_position(node)
		draw_arc(center, radius, 0.0, TAU, 64, COLOR_PLAYER, 2.0)


func _draw_nearby_proximity_targets() -> void:
	var snapshot := _read_proximity_snapshot()
	if snapshot.is_empty():
		return

	var nearby_ids := _string_array_from_variant(snapshot.get("nearby_entity_ids", []))
	if nearby_ids.is_empty():
		return

	for node in get_tree().get_nodes_in_group("debug_entity_labels"):
		if not node is Node:
			continue
		var entity_id := _read_string(node, "entity_id", "get_entity_id")
		if not nearby_ids.has(entity_id):
			continue
		if node.has_method("get_world_rect"):
			draw_rect(node.call("get_world_rect"), COLOR_PROXIMITY_TARGET, false, 3.0)
		else:
			draw_arc(_read_position(node), 11.0, 0.0, TAU, 24, COLOR_PROXIMITY_TARGET, 3.0)


func _draw_entity_labels() -> void:
	var font := ThemeDB.fallback_font
	for node in get_tree().get_nodes_in_group("debug_entity_labels"):
		if not node is Node2D:
			continue
		var label := _read_entity_label(node)
		if label.is_empty():
			continue
		var position := _read_position(node) + Vector2(8.0, -8.0)
		draw_string(font, position, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, COLOR_LABEL)


func _draw_target_markers(group_name: StringName, color: Color, marker_size: float) -> void:
	for node in get_tree().get_nodes_in_group(group_name):
		var center := _read_position(node)
		draw_line(center - Vector2(marker_size, 0.0), center + Vector2(marker_size, 0.0), color, 2.0)
		draw_line(center - Vector2(0.0, marker_size), center + Vector2(0.0, marker_size), color, 2.0)
		draw_arc(center, marker_size + 3.0, 0.0, TAU, 24, color, 2.0)


func _cell_rect(cell: Vector2i) -> Rect2:
	var top_left: Vector2 = _map_model.origin + Vector2(cell) * float(_map_model.cell_size)
	return Rect2(top_left, Vector2.ONE * float(_map_model.cell_size))


func _cell_state_label(cell: Vector2i) -> String:
	var parts: PackedStringArray = []
	if _map_model.is_blocked(cell):
		parts.append("B")
	if _map_model.is_occupied(cell):
		parts.append("O")
	if _map_model.is_reserved(cell):
		parts.append("R")
	if _map_model.is_protected(cell):
		parts.append("P")
	return "/".join(parts)


func _draw_centered_cell_label(font: Font, cell_rect: Rect2, label: String) -> void:
	var font_size := 12
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var ascent := font.get_ascent(font_size)
	var center := cell_rect.get_center()
	var draw_position := Vector2(center.x - text_size.x * 0.5, center.y + ascent * 0.5 - 1.0)
	draw_string(font, draw_position, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, COLOR_LABEL)


func _read_footprint_cells(node: Node) -> Array[Vector2i]:
	var raw_cells: Variant = []
	if node.has_method("get_debug_footprint_cells"):
		raw_cells = node.call("get_debug_footprint_cells")
	elif _has_property(node, "debug_footprint_cells"):
		raw_cells = node.get("debug_footprint_cells")

	var cells: Array[Vector2i] = []
	if typeof(raw_cells) != TYPE_ARRAY:
		return cells

	for raw_cell in raw_cells:
		if raw_cell is Vector2i:
			cells.append(raw_cell)
	return cells


func _read_float(node: Node, property_name: StringName, method_name: StringName) -> float:
	if node.has_method(method_name):
		return float(node.call(method_name))
	if not _has_property(node, property_name):
		return 0.0
	var raw_value: Variant = node.get(property_name)
	if typeof(raw_value) == TYPE_INT or typeof(raw_value) == TYPE_FLOAT:
		return float(raw_value)
	return 0.0


func _read_position(node: Node) -> Vector2:
	if node is Node2D:
		return (node as Node2D).global_position
	return Vector2.ZERO


func _read_entity_label(node: Node) -> String:
	var identity := node.get_node_or_null("IdentityComponent")
	var entity_id := String(identity.call("get_entity_id")) if identity != null else _read_string(node, "entity_id", "get_entity_id")
	var display_name := String(identity.call("get_display_name")) if identity != null else _read_string(node, "display_name", "get_display_name")
	var entity_type := String(identity.call("get_entity_type")) if identity != null else _read_string(node, "entity_type", "get_entity_type")
	if entity_id.is_empty() and display_name.is_empty() and entity_type.is_empty():
		return ""
	return "%s | %s | %s" % [entity_id, display_name, entity_type]


func _read_proximity_snapshot() -> Dictionary:
	if _proximity_snapshot_source == null or not is_instance_valid(_proximity_snapshot_source):
		return {}
	if not _proximity_snapshot_source.has_method("get_proximity_snapshot"):
		return {}
	var snapshot: Variant = _proximity_snapshot_source.call("get_proximity_snapshot")
	if typeof(snapshot) != TYPE_DICTIONARY:
		return {}
	return snapshot


func _string_array_from_variant(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for item in value:
		result.append(String(item))
	return result


func _read_string(node: Node, property_name: StringName, method_name: StringName) -> String:
	if node.has_method(method_name):
		return str(node.call(method_name))
	if not _has_property(node, property_name):
		return ""
	var raw_value: Variant = node.get(property_name)
	if raw_value == null:
		return ""
	return str(raw_value)


func _has_property(node: Node, property_name: StringName) -> bool:
	for property in node.get_property_list():
		if property.name == property_name:
			return true
	return false


func _grid_legend() -> PackedStringArray:
	return PackedStringArray(["white outline: map boundary", "white cross: map origin", "faint white lines: grid lines"])


func _cells_legend() -> PackedStringArray:
	return PackedStringArray([
		"white outline: map boundary",
		"white cross: map origin",
		"faint white lines: grid lines",
		"green fill: walkable cell",
		"red fill: blocked cell",
		"orange fill: occupied cell",
		"blue fill: reserved cell",
		"purple fill: protected cell",
		"yellow outline: building footprint",
	])


func _physics_legend() -> PackedStringArray:
	return PackedStringArray([
		"white outline: map boundary",
		"cyan outline: player collision",
		"red outline: building collision",
		"cyan ring: proximity range",
	])


func _entities_legend() -> PackedStringArray:
	return PackedStringArray([
		"yellow marker: hovered target",
		"white marker: selected target",
		"text label: id | display name | type",
	])


func _emit_debug_state() -> void:
	debug_state_changed.emit(_is_enabled, current_mode, get_legend_entries())
