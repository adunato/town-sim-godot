class_name DebugReadout
extends Control

const PANEL_WIDTH := 376.0
const HEADER_HEIGHT := 70.0
const ROW_HEIGHT := 22.0
const PANEL_MARGIN := 12.0
const ICON_SIZE := 14.0
const TITLE_FONT_SIZE := 14
const BODY_FONT_SIZE := 12
const MUTED_TEXT := Color(0.78, 0.82, 0.86, 1.0)
const PANEL_BG := Color(0.05, 0.06, 0.07, 0.86)
const PANEL_BORDER := Color(0.75, 0.78, 0.82, 0.35)
const CHIP_BG := Color(0.12, 0.18, 0.24, 0.95)
const TEXT_COLOR := Color(1.0, 1.0, 1.0, 0.96)

var _seed := 0
var _mode := "grid"
var _legend_entries := PackedStringArray()
var _panel_style := StyleBoxFlat.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -PANEL_WIDTH - 8.0
	offset_top = 8.0
	offset_right = -8.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_panel_style.bg_color = PANEL_BG
	_panel_style.border_color = PANEL_BORDER
	_panel_style.set_border_width_all(1)
	_panel_style.set_corner_radius_all(4)
	_update_panel_height()


func set_seed(seed: int) -> void:
	_seed = seed
	queue_redraw()


func set_overlay_state(is_enabled: bool, mode: String, legend_entries: PackedStringArray) -> void:
	visible = is_enabled
	if not is_enabled:
		return

	_mode = mode
	_legend_entries = legend_entries
	_update_panel_height()
	queue_redraw()


func _draw() -> void:
	if not visible:
		return

	var font := ThemeDB.fallback_font
	var panel_rect := Rect2(Vector2.ZERO, size)
	draw_style_box(_panel_style, panel_rect)

	var cursor := Vector2(PANEL_MARGIN, PANEL_MARGIN + TITLE_FONT_SIZE)
	draw_string(font, cursor, "Debug Overlay", HORIZONTAL_ALIGNMENT_LEFT, -1.0, TITLE_FONT_SIZE, TEXT_COLOR)

	var chip_rect := Rect2(Vector2(PANEL_WIDTH - PANEL_MARGIN - 92.0, PANEL_MARGIN - 2.0), Vector2(92.0, 22.0))
	draw_rect(chip_rect, CHIP_BG, true)
	draw_rect(chip_rect, PANEL_BORDER, false, 1.0)
	draw_string(font, chip_rect.position + Vector2(10.0, 15.0), _mode, HORIZONTAL_ALIGNMENT_LEFT, -1.0, BODY_FONT_SIZE, TEXT_COLOR)

	cursor.y += 20.0
	draw_string(font, cursor, "Seed  %d" % _seed, HORIZONTAL_ALIGNMENT_LEFT, -1.0, BODY_FONT_SIZE, MUTED_TEXT)

	var separator_y := HEADER_HEIGHT - 10.0
	draw_line(Vector2(PANEL_MARGIN, separator_y), Vector2(PANEL_WIDTH - PANEL_MARGIN, separator_y), PANEL_BORDER, 1.0)
	draw_string(font, Vector2(PANEL_MARGIN, separator_y + 18.0), "Legend", HORIZONTAL_ALIGNMENT_LEFT, -1.0, BODY_FONT_SIZE, MUTED_TEXT)

	var row_y := HEADER_HEIGHT + 24.0
	for entry in _legend_entries:
		_draw_legend_row(font, Vector2(PANEL_MARGIN, row_y), entry)
		row_y += ROW_HEIGHT


func _draw_legend_row(font: Font, origin: Vector2, entry: String) -> void:
	var visual := _legend_visual(entry)
	var icon_rect := Rect2(origin, Vector2(ICON_SIZE, ICON_SIZE))
	var color: Color = visual.color

	match visual.kind:
		"fill":
			draw_rect(icon_rect, color, true)
			draw_rect(icon_rect, Color(1.0, 1.0, 1.0, 0.65), false, 1.0)
		"outline":
			draw_rect(icon_rect, color, false, 2.0)
		"line":
			draw_line(icon_rect.position + Vector2(1.0, ICON_SIZE * 0.5), icon_rect.position + Vector2(ICON_SIZE - 1.0, ICON_SIZE * 0.5), color, 2.0)
		"cross":
			var center := icon_rect.get_center()
			draw_circle(center, 2.5, color)
			draw_line(center, center + Vector2(ICON_SIZE * 0.35, 0.0), color, 2.0)
			draw_line(center, center + Vector2(0.0, ICON_SIZE * 0.35), color, 2.0)
		"ring":
			draw_arc(icon_rect.get_center(), ICON_SIZE * 0.45, 0.0, TAU, 24, color, 2.0)
		"marker":
			var center := icon_rect.get_center()
			draw_arc(center, ICON_SIZE * 0.42, 0.0, TAU, 24, color, 2.0)
			draw_line(center - Vector2(ICON_SIZE * 0.35, 0.0), center + Vector2(ICON_SIZE * 0.35, 0.0), color, 1.5)
			draw_line(center - Vector2(0.0, ICON_SIZE * 0.35), center + Vector2(0.0, ICON_SIZE * 0.35), color, 1.5)
		"text":
			draw_string(font, icon_rect.position + Vector2(1.0, 11.0), "id", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, color)
		_:
			draw_circle(icon_rect.get_center(), ICON_SIZE * 0.35, color)

	draw_string(font, origin + Vector2(24.0, 12.0), visual.label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, BODY_FONT_SIZE, TEXT_COLOR)


func _legend_visual(entry: String) -> Dictionary:
	if entry.contains("walkable"):
		return _legend_item("fill", Color(0.15, 0.95, 0.25, 0.9), "Walkable cell")
	if entry.contains("blocked"):
		return _legend_item("fill", Color(1.0, 0.1, 0.1, 0.9), "Blocked cell")
	if entry.contains("occupied"):
		return _legend_item("fill", Color(1.0, 0.5, 0.0, 0.9), "Occupied cell")
	if entry.contains("reserved"):
		return _legend_item("fill", Color(0.1, 0.45, 1.0, 0.9), "Reserved cell")
	if entry.contains("protected"):
		return _legend_item("fill", Color(0.85, 0.25, 1.0, 0.9), "Protected cell")
	if entry.contains("building footprint"):
		return _legend_item("outline", Color(1.0, 0.9, 0.1, 1.0), "Building footprint")
	if entry.contains("map boundary"):
		return _legend_item("outline", Color(1.0, 1.0, 1.0, 0.95), "Map boundary")
	if entry.contains("map origin"):
		return _legend_item("cross", Color(1.0, 1.0, 1.0, 0.95), "Map origin")
	if entry.contains("grid lines"):
		return _legend_item("line", Color(1.0, 1.0, 1.0, 0.75), "Grid lines")
	if entry.contains("player collision"):
		return _legend_item("outline", Color(0.1, 0.9, 1.0, 1.0), "Player collision")
	if entry.contains("building collision"):
		return _legend_item("outline", Color(1.0, 0.1, 0.1, 1.0), "Building collision")
	if entry.contains("proximity"):
		return _legend_item("ring", Color(0.1, 0.9, 1.0, 1.0), "Proximity range")
	if entry.contains("hovered"):
		return _legend_item("marker", Color(1.0, 0.9, 0.1, 1.0), "Hovered target")
	if entry.contains("selected"):
		return _legend_item("marker", Color(1.0, 1.0, 1.0, 1.0), "Selected target")
	if entry.contains("id | display name | type"):
		return _legend_item("text", Color(1.0, 1.0, 1.0, 0.95), "Entity label")
	return _legend_item("dot", Color(1.0, 1.0, 1.0, 0.8), entry.capitalize())


func _legend_item(kind: String, color: Color, label: String) -> Dictionary:
	return {
		"kind": kind,
		"color": color,
		"label": label,
	}


func _update_panel_height() -> void:
	var panel_height: float = HEADER_HEIGHT + 24.0 + float(max(1, _legend_entries.size())) * ROW_HEIGHT + PANEL_MARGIN
	custom_minimum_size = Vector2(PANEL_WIDTH, panel_height)
	offset_bottom = offset_top + panel_height
