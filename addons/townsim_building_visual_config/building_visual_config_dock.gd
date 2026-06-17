@tool
class_name BuildingVisualConfigDock
extends VBoxContainer

const BuildingVisualConfigStoreScript := preload("res://addons/townsim_building_visual_config/building_visual_config_store.gd")
const BuildingVisualPreviewScript := preload("res://addons/townsim_building_visual_config/building_visual_preview.gd")

var _store: BuildingVisualConfigStore
var _building_options: OptionButton
var _profile_options: OptionButton
var _anchor_options: OptionButton
var _y_sort_options: OptionButton
var _offset_x: SpinBox
var _offset_y: SpinBox
var _bounds_x: SpinBox
var _bounds_y: SpinBox
var _bounds_width: SpinBox
var _bounds_height: SpinBox
var _validation_label: Label
var _status_label: Label
var _save_button: Button
var _preview: BuildingVisualPreview

var _current_definition: Dictionary = {}
var _current_profile: Dictionary = {}
var _loading_controls := false


func _ready() -> void:
	_store = BuildingVisualConfigStoreScript.new()
	_build_ui()
	_reload_data()


func _build_ui() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var split := HBoxContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)

	var controls := VBoxContainer.new()
	controls.custom_minimum_size = Vector2(390, 0)
	controls.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(controls)

	_building_options = _add_options_row(controls, "Building")
	_profile_options = _add_options_row(controls, "Profile")
	_anchor_options = _add_options_row(controls, "Anchor")
	_y_sort_options = _add_options_row(controls, "Y-sort")
	_offset_x = _add_spinbox_row(controls, "Offset X", -4096.0, 4096.0)
	_offset_y = _add_spinbox_row(controls, "Offset Y", -4096.0, 4096.0)
	_bounds_x = _add_spinbox_row(controls, "Bounds X", -4096.0, 4096.0)
	_bounds_y = _add_spinbox_row(controls, "Bounds Y", -4096.0, 4096.0)
	_bounds_width = _add_spinbox_row(controls, "Bounds W", 1.0, 8192.0)
	_bounds_height = _add_spinbox_row(controls, "Bounds H", 1.0, 8192.0)

	var button_row := HBoxContainer.new()
	controls.add_child(button_row)
	var reload_button := Button.new()
	reload_button.text = "Reload"
	reload_button.pressed.connect(_reload_data)
	button_row.add_child(reload_button)
	_save_button = Button.new()
	_save_button.text = "Save"
	_save_button.pressed.connect(_save_pressed)
	button_row.add_child(_save_button)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_child(_status_label)
	_validation_label = Label.new()
	_validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_validation_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	controls.add_child(_validation_label)

	var preview_panel := PanelContainer.new()
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(preview_panel)
	_preview = BuildingVisualPreviewScript.new()
	preview_panel.add_child(_preview)

	_building_options.item_selected.connect(_building_selected)
	_profile_options.item_selected.connect(_profile_selected)
	_anchor_options.item_selected.connect(func(_index: int) -> void: _controls_changed())
	_y_sort_options.item_selected.connect(func(_index: int) -> void: _controls_changed())
	for spinbox in [_offset_x, _offset_y, _bounds_x, _bounds_y, _bounds_width, _bounds_height]:
		spinbox.value_changed.connect(func(_value: float) -> void: _controls_changed())


func _add_options_row(parent: Control, label_text: String) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(82, 0)
	row.add_child(label)
	var options := OptionButton.new()
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(options)
	return options


func _add_spinbox_row(parent: Control, label_text: String, min_value: float, max_value: float) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(82, 0)
	row.add_child(label)
	var spinbox := SpinBox.new()
	spinbox.min_value = min_value
	spinbox.max_value = max_value
	spinbox.step = 1.0
	spinbox.rounded = true
	spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spinbox)
	return spinbox


func _reload_data() -> void:
	_loading_controls = true
	_status_label.text = ""
	_validation_label.text = ""
	_building_options.clear()
	_profile_options.clear()
	_anchor_options.clear()
	_y_sort_options.clear()

	var load_result: Dictionary = _store.load_data()
	if not load_result.ok:
		_status_label.text = String(load_result.error)
		_loading_controls = false
		_update_enabled_state()
		return

	for anchor in _store.get_supported_anchors():
		_anchor_options.add_item(anchor)
	for y_sort_origin in _store.get_supported_y_sort_origins():
		_y_sort_options.add_item(y_sort_origin)
	for definition in _store.get_definitions():
		_add_option_with_metadata(_building_options, "%s (%s)" % [definition.get("display_name", definition.id), definition.id], String(definition.id))
	for profile in _store.get_visual_profiles():
		_add_option_with_metadata(_profile_options, String(profile.id), String(profile.id))

	_loading_controls = false
	if _building_options.item_count > 0:
		_building_selected(_building_options.selected)
	else:
		_current_definition = {}
		_current_profile = {}
		_update_preview_and_validation()


func _building_selected(index: int) -> void:
	if _loading_controls:
		return
	var definition_id := _option_metadata(_building_options, index)
	var definition_result: Dictionary = _store.get_definition(definition_id)
	if not definition_result.ok:
		_status_label.text = String(definition_result.error)
		return
	_current_definition = definition_result.definition
	var profile_id := String(_current_definition.get("visual_profile_id", ""))
	_select_option_by_metadata(_profile_options, profile_id)
	_load_current_profile(profile_id)
	_update_controls_from_profile()


func _profile_selected(index: int) -> void:
	if _loading_controls:
		return
	var profile_id := _option_metadata(_profile_options, index)
	if _current_definition.is_empty():
		return
	_current_definition.visual_profile_id = profile_id
	_load_current_profile(profile_id)
	_update_controls_from_profile()


func _load_current_profile(profile_id: String) -> void:
	var profile_result: Dictionary = _store.get_visual_profile(profile_id)
	if profile_result.ok:
		_current_profile = profile_result.visual_profile
	else:
		_current_profile = {}
		_status_label.text = String(profile_result.error)


func _update_controls_from_profile() -> void:
	_loading_controls = true
	_select_option_by_text(_anchor_options, String(_current_profile.get("anchor", "")))
	_select_option_by_text(_y_sort_options, String(_current_profile.get("y_sort_origin", "")))
	var offset: Dictionary = _current_profile.get("pixel_offset", {"x": 0, "y": 0})
	_offset_x.value = int(offset.get("x", 0))
	_offset_y.value = int(offset.get("y", 0))
	var bounds := _current_visual_bounds()
	_bounds_x.value = int(bounds.x)
	_bounds_y.value = int(bounds.y)
	_bounds_width.value = int(bounds.width)
	_bounds_height.value = int(bounds.height)
	_loading_controls = false
	_update_preview_and_validation()


func _controls_changed() -> void:
	if _loading_controls or _current_profile.is_empty():
		return
	_current_profile.anchor = _selected_option_text(_anchor_options)
	_current_profile.y_sort_origin = _selected_option_text(_y_sort_options)
	_current_profile.pixel_offset = {
		"x": int(_offset_x.value),
		"y": int(_offset_y.value),
	}
	_current_profile.visual_bounds = {
		"x": int(_bounds_x.value),
		"y": int(_bounds_y.value),
		"width": int(_bounds_width.value),
		"height": int(_bounds_height.value),
	}
	_update_preview_and_validation()


func _update_preview_and_validation() -> void:
	_preview.set_preview_data(_current_definition, _current_profile)
	var messages := _store.get_validation_messages(_current_definition, _current_profile)
	if messages.is_empty():
		_validation_label.text = "Validation: no profile errors."
		_save_button.disabled = _current_definition.is_empty() or _current_profile.is_empty()
	else:
		_validation_label.text = "Validation:\n- " + "\n- ".join(messages)
		_save_button.disabled = true
	_update_enabled_state()


func _save_pressed() -> void:
	if _current_definition.is_empty() or _current_profile.is_empty():
		return
	var messages := _store.get_validation_messages(_current_definition, _current_profile)
	if not messages.is_empty():
		_status_label.text = "Save blocked until validation errors are fixed."
		return

	var definition_result := _store.apply_definition_profile_id(String(_current_definition.id), String(_current_definition.visual_profile_id))
	if not definition_result.ok:
		_status_label.text = String(definition_result.error)
		return
	var profile_result := _store.apply_visual_profile_fields(String(_current_profile.id), {
		"anchor": _current_profile.anchor,
		"pixel_offset": _current_profile.pixel_offset,
		"y_sort_origin": _current_profile.y_sort_origin,
		"visual_bounds": _current_profile.visual_bounds,
	})
	if not profile_result.ok:
		_status_label.text = String(profile_result.error)
		return

	var save_result := _store.save()
	if not save_result.ok:
		_status_label.text = String(save_result.error)
		return
	_status_label.text = "Saved building visual profile data."
	_reload_data()


func _update_enabled_state() -> void:
	var has_selection := not _current_definition.is_empty() and not _current_profile.is_empty()
	for options in [_profile_options, _anchor_options, _y_sort_options]:
		options.disabled = not has_selection
	for spinbox in [_offset_x, _offset_y, _bounds_x, _bounds_y, _bounds_width, _bounds_height]:
		spinbox.editable = has_selection


func _current_visual_bounds() -> Dictionary:
	var bounds: Variant = _current_profile.get("visual_bounds", null)
	if typeof(bounds) == TYPE_DICTIONARY:
		return bounds
	var footprint: Dictionary = _current_definition.get("footprint_cells", {})
	return {
		"x": 0,
		"y": 0,
		"width": int(footprint.get("width", 1)) * 32,
		"height": int(footprint.get("height", 1)) * 32,
	}


func _add_option_with_metadata(options: OptionButton, label: String, metadata: String) -> void:
	options.add_item(label)
	options.set_item_metadata(options.item_count - 1, metadata)


func _option_metadata(options: OptionButton, index: int) -> String:
	if index < 0 or index >= options.item_count:
		return ""
	return String(options.get_item_metadata(index))


func _select_option_by_metadata(options: OptionButton, metadata: String) -> void:
	for index in range(options.item_count):
		if String(options.get_item_metadata(index)) == metadata:
			options.select(index)
			return


func _select_option_by_text(options: OptionButton, text: String) -> void:
	for index in range(options.item_count):
		if options.get_item_text(index) == text:
			options.select(index)
			return


func _selected_option_text(options: OptionButton) -> String:
	if options.item_count == 0 or options.selected < 0:
		return ""
	return options.get_item_text(options.selected)
