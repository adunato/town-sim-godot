class_name GameHud
extends Control

signal clear_selection_requested
signal inspect_interaction_requested
signal debug_toggle_requested
signal interaction_context_requested(screen_position: Vector2)

const UNKNOWN_TEXT := "Unknown"
const UNAVAILABLE_TEXT := "Unavailable"
const NO_VALUE_TEXT := "-"
const PANEL_BG := Color(0.05, 0.06, 0.07, 0.88)
const PANEL_BORDER := Color(0.75, 0.78, 0.82, 0.38)
const TEXT_COLOR := Color(1.0, 1.0, 1.0, 0.96)
const MUTED_TEXT := Color(0.78, 0.82, 0.86, 1.0)
const SELECTION_PANEL_SIZE := Vector2(280.0, 190.0)
const DETAILS_PANEL_SIZE := Vector2(320.0, 250.0)
const CONTEXT_MENU_SIZE := Vector2(220.0, 132.0)
const STATUS_HEIGHT := 30.0
const MARGIN := 12.0

var _selection_snapshot: Dictionary = {"has_target": false}
var _context_target_label := NO_VALUE_TEXT

var _selection_panel: PanelContainer
var _selection_name_value: Label
var _selection_type_value: Label
var _selection_id_value: Label
var _selection_interaction_value: Label
var _details_button: Button
var _interact_button: Button
var _details_panel: PanelContainer
var _details_name_value: Label
var _details_type_value: Label
var _details_id_value: Label
var _details_interaction_value: Label
var _details_position_value: Label
var _context_menu: PanelContainer
var _context_target_value: Label
var _context_action_value: Label
var _inspect_button: Button
var _status_label: Label
var _debug_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	set_selection_snapshot(_selection_snapshot)
	set_status_text("Ready")
	set_debug_state(false)


func set_selection_snapshot(snapshot: Dictionary) -> void:
	_selection_snapshot = snapshot.duplicate(true)
	var has_target := bool(_selection_snapshot.get("has_target", false))
	var display_name := _read_text(_selection_snapshot, "display_name", UNKNOWN_TEXT)
	var entity_type := _read_text(_selection_snapshot, "entity_type", UNKNOWN_TEXT)
	var entity_id := _read_text(_selection_snapshot, "entity_id", UNKNOWN_TEXT)
	var interaction := _interaction_label(_selection_snapshot)
	var position := _position_label(_selection_snapshot.get("position", null))

	if has_target:
		_selection_name_value.text = display_name
		_selection_type_value.text = entity_type
		_selection_id_value.text = entity_id
		_selection_interaction_value.text = interaction
		set_status_text("Selected: %s" % display_name)
	else:
		_selection_name_value.text = "No selection"
		_selection_type_value.text = NO_VALUE_TEXT
		_selection_id_value.text = NO_VALUE_TEXT
		_selection_interaction_value.text = NO_VALUE_TEXT
		set_status_text("No selection")
		hide_selection_details()
		hide_interaction_context_menu()

	_details_name_value.text = display_name if has_target else NO_VALUE_TEXT
	_details_type_value.text = entity_type if has_target else NO_VALUE_TEXT
	_details_id_value.text = entity_id if has_target else NO_VALUE_TEXT
	_details_interaction_value.text = interaction if has_target else NO_VALUE_TEXT
	_details_position_value.text = position if has_target else NO_VALUE_TEXT
	_context_target_label = display_name if has_target else NO_VALUE_TEXT
	_details_button.disabled = not has_target
	_interact_button.disabled = not has_target


func show_selection_details() -> void:
	if not bool(_selection_snapshot.get("has_target", false)):
		return
	_details_panel.visible = true
	_position_details_panel()


func hide_selection_details() -> void:
	_details_panel.visible = false


func show_interaction_context_menu(screen_position: Vector2, target_label := "", enabled := true) -> void:
	_context_target_label = target_label if not target_label.is_empty() else _context_target_label
	_context_target_value.text = _context_target_label
	_context_action_value.text = "Inspect"
	_inspect_button.disabled = not enabled
	_context_menu.visible = true
	_position_context_menu(screen_position)


func hide_interaction_context_menu() -> void:
	_context_menu.visible = false


func set_status_text(text: String) -> void:
	_status_label.text = text


func set_debug_state(is_enabled: bool, _mode := "", _legend_entries := PackedStringArray()) -> void:
	_debug_button.text = "Debug: On" if is_enabled else "Debug: Off"


func get_status_text() -> String:
	return _status_label.text


func get_debug_button_text() -> String:
	return _debug_button.text


func get_selection_field_text(field_name: StringName) -> String:
	match field_name:
		&"Name":
			return _selection_name_value.text
		&"Type":
			return _selection_type_value.text
		&"ID":
			return _selection_id_value.text
		&"Interaction":
			return _selection_interaction_value.text
		_:
			return ""


func is_details_visible() -> bool:
	return _details_panel.visible


func is_context_menu_visible() -> bool:
	return _context_menu.visible


func get_details_rect() -> Rect2:
	return Rect2(_details_panel.position, DETAILS_PANEL_SIZE)


func get_context_menu_rect() -> Rect2:
	return Rect2(_context_menu.position, CONTEXT_MENU_SIZE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		if _details_panel != null:
			_position_details_panel()
		if _context_menu != null and _context_menu.visible:
			_position_context_menu(_context_menu.position)


func _build_ui() -> void:
	_selection_panel = _panel("SelectionPanel", SELECTION_PANEL_SIZE)
	_selection_panel.position = Vector2(MARGIN, MARGIN)
	add_child(_selection_panel)

	var selection_rows := _panel_vbox(_selection_panel, "Selection")
	_selection_name_value = _add_value_row(selection_rows, "Name")
	_selection_type_value = _add_value_row(selection_rows, "Type")
	_selection_id_value = _add_value_row(selection_rows, "ID")
	_selection_interaction_value = _add_value_row(selection_rows, "Interaction")

	var selection_buttons := HBoxContainer.new()
	selection_rows.add_child(selection_buttons)
	_details_button = _button("DetailsButton", "Details")
	_details_button.pressed.connect(show_selection_details)
	selection_buttons.add_child(_details_button)
	_interact_button = _button("InteractButton", "Interact")
	_interact_button.pressed.connect(_on_interact_pressed)
	selection_buttons.add_child(_interact_button)
	_debug_button = _button("DebugToggleButton", "Debug: Off")
	_debug_button.pressed.connect(_on_debug_toggle_pressed)
	selection_buttons.add_child(_debug_button)

	_details_panel = _panel("SelectionDetails", DETAILS_PANEL_SIZE)
	_details_panel.visible = false
	add_child(_details_panel)
	var details_rows := _panel_vbox(_details_panel, "Selection Details")
	_details_name_value = _add_value_row(details_rows, "Name")
	_details_type_value = _add_value_row(details_rows, "Type")
	_details_id_value = _add_value_row(details_rows, "ID")
	_details_interaction_value = _add_value_row(details_rows, "Interaction")
	_details_position_value = _add_value_row(details_rows, "Position")
	var details_buttons := HBoxContainer.new()
	details_rows.add_child(details_buttons)
	var close_details := _button("CloseDetailsButton", "Close")
	close_details.pressed.connect(hide_selection_details)
	details_buttons.add_child(close_details)
	var clear_selection := _button("ClearSelectionButton", "Clear Selection")
	clear_selection.pressed.connect(_on_clear_selection_pressed)
	details_buttons.add_child(clear_selection)

	_context_menu = _panel("InteractionContextMenu", CONTEXT_MENU_SIZE)
	_context_menu.visible = false
	add_child(_context_menu)
	var context_rows := _panel_vbox(_context_menu, "Interaction")
	_context_target_value = _add_value_row(context_rows, "Target")
	_context_action_value = _add_value_row(context_rows, "Action")
	var context_buttons := HBoxContainer.new()
	context_rows.add_child(context_buttons)
	_inspect_button = _button("InspectButton", "Inspect")
	_inspect_button.pressed.connect(_on_inspect_pressed)
	context_buttons.add_child(_inspect_button)
	var close_context := _button("CloseContextButton", "Close")
	close_context.pressed.connect(hide_interaction_context_menu)
	context_buttons.add_child(close_context)

	_status_label = Label.new()
	_status_label.name = "StatusStrip"
	_status_label.text = "Ready"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.add_theme_color_override("font_color", TEXT_COLOR)
	_status_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_status_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_status_label.offset_left = MARGIN
	_status_label.offset_right = -MARGIN
	_status_label.offset_top = -STATUS_HEIGHT - MARGIN
	_status_label.offset_bottom = -MARGIN
	add_child(_status_label)

	_position_details_panel()


func _panel(node_name: String, panel_size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.custom_minimum_size = panel_size
	panel.size = panel_size
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = PANEL_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _panel_vbox(panel: PanelContainer, title: String) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.name = "%sMargin" % title.replace(" ", "")
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var rows := VBoxContainer.new()
	rows.name = "%sRows" % title.replace(" ", "")
	rows.add_theme_constant_override("separation", 6)
	margin.add_child(rows)

	var heading := Label.new()
	heading.name = "%sTitle" % title.replace(" ", "")
	heading.text = title
	heading.add_theme_color_override("font_color", TEXT_COLOR)
	rows.add_child(heading)
	return rows


func _add_value_row(parent: VBoxContainer, label_text: String) -> Label:
	var row := HBoxContainer.new()
	row.name = "%sRow" % label_text
	parent.add_child(row)
	var label := Label.new()
	label.name = "%sLabel" % label_text
	label.text = label_text
	label.custom_minimum_size = Vector2(90.0, 0.0)
	label.add_theme_color_override("font_color", MUTED_TEXT)
	row.add_child(label)
	var value := Label.new()
	value.name = "%sValue" % label_text
	value.text = NO_VALUE_TEXT
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.add_theme_color_override("font_color", TEXT_COLOR)
	row.add_child(value)
	return value


func _button(node_name: String, label_text: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = label_text
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	return button


func _on_interact_pressed() -> void:
	interaction_context_requested.emit(get_viewport().get_mouse_position())


func _on_inspect_pressed() -> void:
	hide_interaction_context_menu()
	inspect_interaction_requested.emit()


func _on_clear_selection_pressed() -> void:
	hide_selection_details()
	hide_interaction_context_menu()
	clear_selection_requested.emit()


func _on_debug_toggle_pressed() -> void:
	debug_toggle_requested.emit()


func _position_details_panel() -> void:
	var viewport_size := get_viewport_rect().size
	_details_panel.size = DETAILS_PANEL_SIZE
	_details_panel.position = Vector2(
		max(MARGIN, viewport_size.x - DETAILS_PANEL_SIZE.x - MARGIN),
		MARGIN
	)


func _position_context_menu(screen_position: Vector2) -> void:
	var viewport_size := get_viewport_rect().size
	_context_menu.size = CONTEXT_MENU_SIZE
	_context_menu.position = Vector2(
		clampf(screen_position.x, MARGIN, max(MARGIN, viewport_size.x - CONTEXT_MENU_SIZE.x - MARGIN)),
		clampf(screen_position.y, MARGIN, max(MARGIN, viewport_size.y - CONTEXT_MENU_SIZE.y - MARGIN))
	)


func _read_text(snapshot: Dictionary, key: String, fallback: String) -> String:
	var value := String(snapshot.get(key, ""))
	return value if not value.is_empty() else fallback


func _interaction_label(snapshot: Dictionary) -> String:
	if not snapshot.has("interactable"):
		return UNAVAILABLE_TEXT
	return "Available" if bool(snapshot.get("interactable", false)) else UNAVAILABLE_TEXT


func _position_label(value: Variant) -> String:
	if value is Vector2:
		var position := value as Vector2
		return "%.0f, %.0f" % [position.x, position.y]
	return UNKNOWN_TEXT
