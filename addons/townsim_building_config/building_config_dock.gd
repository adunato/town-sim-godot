@tool
class_name BuildingConfigDock
extends VBoxContainer

const BuildingConfigStoreScript := preload("res://addons/townsim_building_config/building_config_store.gd")
const BuildingVisualPreviewScript := preload("res://addons/townsim_building_config/building_visual_preview.gd")

var _store: BuildingConfigStore
var _building_options: OptionButton
var _tabs: TabContainer
var _save_button: Button
var _dirty_label: Label
var _status_label: Label
var _validation_label: Label
var _reload_confirmation: ConfirmationDialog
var _preview: BuildingConfigVisualPreview

var _definition_id: LineEdit
var _display_name: LineEdit
var _footprint_width: SpinBox
var _footprint_height: SpinBox
var _profile_assignment: OptionButton
var _prototype_color: ColorPickerButton
var _selectable: CheckButton
var _interactable: CheckButton

var _profile_id: LineEdit
var _texture_path: LineEdit
var _texture_picker_button: Button
var _texture_file_dialog: FileDialog
var _source_rect_enabled: CheckButton
var _source_rect_fields: Array[SpinBox] = []
var _anchor: OptionButton
var _offset_x: SpinBox
var _offset_y: SpinBox
var _y_sort: OptionButton
var _render_width: SpinBox
var _render_height: SpinBox
var _keep_render_ratio: CheckButton
var _expected_width: SpinBox
var _expected_height: SpinBox
var _bounds_enabled: CheckButton
var _bounds_fields: Array[SpinBox] = []
var _terrain_options: OptionButton

var _current_definition_id := ""
var _current_profile_id := ""
var _loading_controls := false
var _syncing_render_size := false


func _ready() -> void:
	_store = BuildingConfigStoreScript.new()
	_build_ui()
	_reload_data_now()


func get_selected_definition_id() -> String:
	return _current_definition_id


func get_active_tab_title() -> String:
	return _tabs.get_tab_title(_tabs.current_tab) if _tabs != null else ""


func get_tab_count() -> int:
	return _tabs.get_tab_count() if _tabs != null else 0


func is_save_enabled() -> bool:
	return _save_button != null and not _save_button.disabled


func get_validation_text() -> String:
	return _validation_label.text if _validation_label != null else ""


func set_render_width_for_validation(value: int) -> void:
	if _render_width != null:
		_render_width.value = value


func is_render_ratio_locked() -> bool:
	return _keep_render_ratio != null and _keep_render_ratio.button_pressed


func has_texture_picker() -> bool:
	return _texture_picker_button != null and _texture_file_dialog != null


func align_render_size_to_footprint_for_validation() -> void:
	_align_render_size_to_footprint()


func align_bounds_size_to_footprint_for_validation() -> void:
	_align_bounds_size_to_footprint()


func get_render_size_for_validation() -> Vector2i:
	return Vector2i(int(_render_width.value), int(_render_height.value))


func get_bounds_size_for_validation() -> Vector2i:
	return Vector2i(int(_bounds_fields[2].value), int(_bounds_fields[3].value))


func get_definition_footprint_for_validation() -> Vector2i:
	return Vector2i(int(_footprint_width.value), int(_footprint_height.value))


func set_active_tab(index: int) -> void:
	if _tabs != null and index >= 0 and index < _tabs.get_tab_count():
		_tabs.current_tab = index


func _build_ui() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var header := HBoxContainer.new()
	add_child(header)
	var building_label := Label.new()
	building_label.text = "Building"
	header.add_child(building_label)
	_building_options = OptionButton.new()
	_building_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_building_options)
	var reload_button := Button.new()
	reload_button.text = "Reload"
	reload_button.pressed.connect(_reload_pressed)
	header.add_child(reload_button)
	_save_button = Button.new()
	_save_button.text = "Save"
	_save_button.pressed.connect(_save_pressed)
	header.add_child(_save_button)
	_dirty_label = Label.new()
	_dirty_label.custom_minimum_size = Vector2(80, 0)
	header.add_child(_dirty_label)

	_tabs = TabContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_tabs)
	_build_definition_tab()
	_build_visual_tab()

	_validation_label = Label.new()
	_validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_validation_label)
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status_label)

	_reload_confirmation = ConfirmationDialog.new()
	_reload_confirmation.title = "Discard unsaved building changes?"
	_reload_confirmation.dialog_text = "Reloading replaces all unsaved Definition and Visual edits with data from disk."
	_reload_confirmation.confirmed.connect(_reload_data_now)
	add_child(_reload_confirmation)

	_building_options.item_selected.connect(_building_selected)


func _build_definition_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Definition"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_child(scroll)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(form)

	_definition_id = _add_line_edit_row(form, "ID", true)
	_display_name = _add_line_edit_row(form, "Display name")
	_footprint_width = _add_spinbox_row(form, "Footprint width", 1, 256)
	_footprint_height = _add_spinbox_row(form, "Footprint height", 1, 256)
	_profile_assignment = _add_options_row(form, "Visual profile")
	_prototype_color = ColorPickerButton.new()
	_add_control_row(form, "Prototype colour", _prototype_color)
	_selectable = CheckButton.new()
	_selectable.text = "Selectable"
	form.add_child(_selectable)
	_interactable = CheckButton.new()
	_interactable.text = "Interactable"
	form.add_child(_interactable)

	_display_name.text_changed.connect(func(_value: String) -> void: _definition_controls_changed())
	_footprint_width.value_changed.connect(func(_value: float) -> void: _definition_controls_changed())
	_footprint_height.value_changed.connect(func(_value: float) -> void: _definition_controls_changed())
	_profile_assignment.item_selected.connect(_profile_assignment_changed)
	_prototype_color.color_changed.connect(func(_value: Color) -> void: _definition_controls_changed())
	_selectable.toggled.connect(func(_value: bool) -> void: _definition_controls_changed())
	_interactable.toggled.connect(func(_value: bool) -> void: _definition_controls_changed())


func _build_visual_tab() -> void:
	var split := HBoxContainer.new()
	split.name = "Visual"
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_child(split)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(410, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(scroll)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(form)

	_profile_id = _add_line_edit_row(form, "Profile ID", true)
	_texture_path = _add_line_edit_row(form, "Texture path")
	_texture_picker_button = Button.new()
	_texture_picker_button.text = "Open..."
	_texture_picker_button.tooltip_text = "Choose a project image resource"
	_add_control_row(form, "Texture file", _texture_picker_button)
	_source_rect_enabled = CheckButton.new()
	_source_rect_enabled.text = "Use source rectangle"
	form.add_child(_source_rect_enabled)
	for label_text in ["Source X", "Source Y", "Source width", "Source height"]:
		_source_rect_fields.append(_add_spinbox_row(form, label_text, -8192 if label_text.ends_with("X") or label_text.ends_with("Y") else 1, 8192))
	_anchor = _add_options_row(form, "Anchor")
	_offset_x = _add_spinbox_row(form, "Offset X", -8192, 8192)
	_offset_y = _add_spinbox_row(form, "Offset Y", -8192, 8192)
	_y_sort = _add_options_row(form, "Y-sort origin")
	_render_width = _add_spinbox_row(form, "Render width", 1, 8192)
	_render_height = _add_spinbox_row(form, "Render height", 1, 8192)
	var align_render_button := Button.new()
	align_render_button.text = "Set render size to footprint"
	align_render_button.tooltip_text = "Set render width and height to the building footprint in pixels."
	align_render_button.pressed.connect(_align_render_size_to_footprint)
	form.add_child(align_render_button)
	_keep_render_ratio = CheckButton.new()
	_keep_render_ratio.text = "Lock render aspect ratio"
	_keep_render_ratio.button_pressed = true
	form.add_child(_keep_render_ratio)
	var footprint_help := Label.new()
	footprint_help.text = "Profile footprint must match the Definition tab footprint. It validates profile compatibility."
	footprint_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form.add_child(footprint_help)
	_expected_width = _add_spinbox_row(form, "Profile footprint W", 1, 256)
	_expected_width.tooltip_text = "Logical grid width this visual profile is valid for; must match the building definition."
	_expected_height = _add_spinbox_row(form, "Profile footprint H", 1, 256)
	_expected_height.tooltip_text = "Logical grid height this visual profile is valid for; must match the building definition."
	_bounds_enabled = CheckButton.new()
	_bounds_enabled.text = "Use visual bounds"
	form.add_child(_bounds_enabled)
	for label_text in ["Bounds X", "Bounds Y", "Bounds width", "Bounds height"]:
		_bounds_fields.append(_add_spinbox_row(form, label_text, -8192 if label_text.ends_with("X") or label_text.ends_with("Y") else 1, 8192))
	var align_bounds_button := Button.new()
	align_bounds_button.text = "Set bounds size to footprint"
	align_bounds_button.tooltip_text = "Enable visual bounds and set their width and height to the building footprint in pixels."
	align_bounds_button.pressed.connect(_align_bounds_size_to_footprint)
	form.add_child(align_bounds_button)
	_terrain_options = _add_options_row(form, "Preview terrain")

	var preview_panel := PanelContainer.new()
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(preview_panel)
	_preview = BuildingVisualPreviewScript.new()
	preview_panel.add_child(_preview)

	_texture_path.text_changed.connect(func(_value: String) -> void: _visual_controls_changed())
	_texture_picker_button.pressed.connect(_open_texture_picker)
	_source_rect_enabled.toggled.connect(func(_value: bool) -> void: _visual_controls_changed())
	for spinbox in _source_rect_fields:
		spinbox.value_changed.connect(func(_value: float) -> void: _visual_controls_changed())
	_anchor.item_selected.connect(func(_index: int) -> void: _visual_controls_changed())
	for spinbox in [_offset_x, _offset_y, _expected_width, _expected_height]:
		spinbox.value_changed.connect(func(_value: float) -> void: _visual_controls_changed())
	_render_width.value_changed.connect(_render_width_changed)
	_render_height.value_changed.connect(_render_height_changed)
	_y_sort.item_selected.connect(func(_index: int) -> void: _visual_controls_changed())
	_bounds_enabled.toggled.connect(func(_value: bool) -> void: _visual_controls_changed())
	for spinbox in _bounds_fields:
		spinbox.value_changed.connect(func(_value: float) -> void: _visual_controls_changed())
	_terrain_options.item_selected.connect(func(_index: int) -> void: _update_preview_and_status())

	_texture_file_dialog = FileDialog.new()
	_texture_file_dialog.title = "Select building texture"
	_texture_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_texture_file_dialog.access = FileDialog.ACCESS_RESOURCES
	_texture_file_dialog.filters = PackedStringArray([
		"*.png ; PNG images",
		"*.jpg,*.jpeg ; JPEG images",
		"*.webp ; WebP images",
		"*.svg ; SVG images",
	])
	_texture_file_dialog.file_selected.connect(_texture_file_selected)
	add_child(_texture_file_dialog)


func _add_control_row(parent: Control, label_text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(145, 0)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)


func _add_line_edit_row(parent: Control, label_text: String, read_only := false) -> LineEdit:
	var edit := LineEdit.new()
	edit.editable = not read_only
	_add_control_row(parent, label_text, edit)
	return edit


func _add_options_row(parent: Control, label_text: String) -> OptionButton:
	var options := OptionButton.new()
	_add_control_row(parent, label_text, options)
	return options


func _add_spinbox_row(parent: Control, label_text: String, min_value: int, max_value: int) -> SpinBox:
	var spinbox := SpinBox.new()
	spinbox.min_value = min_value
	spinbox.max_value = max_value
	spinbox.step = 1
	spinbox.rounded = true
	_add_control_row(parent, label_text, spinbox)
	return spinbox


func _reload_pressed() -> void:
	if _store.is_dirty():
		_reload_confirmation.popup_centered()
	else:
		_reload_data_now()


func _reload_data_now() -> void:
	_loading_controls = true
	_status_label.text = ""
	var selected_id := _current_definition_id
	var result: Dictionary = _store.load_data()
	if not result.ok:
		_status_label.text = String(result.error)
		_loading_controls = false
		_update_preview_and_status()
		return
	_populate_static_options()
	_loading_controls = false
	if not selected_id.is_empty() and _select_option_by_metadata(_building_options, selected_id):
		_building_selected(_building_options.selected)
	elif _building_options.item_count > 0:
		_building_options.select(0)
		_building_selected(0)
	else:
		_current_definition_id = ""
		_current_profile_id = ""
	_update_preview_and_status()


func _populate_static_options() -> void:
	_building_options.clear()
	_profile_assignment.clear()
	_anchor.clear()
	_y_sort.clear()
	_terrain_options.clear()
	for definition in _store.get_definitions():
		_add_option(_building_options, "%s (%s)" % [definition.display_name, definition.id], String(definition.id))
	for profile in _store.get_visual_profiles():
		_add_option(_profile_assignment, String(profile.id), String(profile.id))
	for anchor_name in _store.get_supported_anchors():
		_add_option(_anchor, anchor_name, anchor_name)
	for y_sort_name in _store.get_supported_y_sort_origins():
		_add_option(_y_sort, y_sort_name, y_sort_name)
	for material in _store.get_terrain_materials():
		_add_option(_terrain_options, "%s (%s)" % [material.id, material.terrain_type], String(material.id))
	if _terrain_options.item_count > 0:
		_terrain_options.select(0)


func _building_selected(index: int) -> void:
	if _loading_controls:
		return
	_current_definition_id = _option_metadata(_building_options, index)
	_refresh_controls_from_store()


func _refresh_controls_from_store() -> void:
	var definition_result := _store.get_definition(_current_definition_id)
	if not definition_result.ok:
		_status_label.text = String(definition_result.error)
		return
	var definition: Dictionary = definition_result.definition
	_current_profile_id = String(definition.visual_profile_id)
	var profile_result := _store.get_visual_profile(_current_profile_id)
	var profile: Dictionary = profile_result.get("visual_profile", {})

	_loading_controls = true
	_definition_id.text = String(definition.id)
	_display_name.text = String(definition.display_name)
	_footprint_width.value = int(definition.footprint_cells.width)
	_footprint_height.value = int(definition.footprint_cells.height)
	_select_option_by_metadata(_profile_assignment, _current_profile_id)
	_prototype_color.color = Color.from_string(String(definition.prototype_color), Color.WHITE)
	_selectable.button_pressed = bool(definition.selectable)
	_interactable.button_pressed = bool(definition.interactable)
	_profile_id.text = String(profile.get("id", ""))
	_texture_path.text = String(profile.get("texture_path", ""))
	_set_optional_rect_controls(_source_rect_enabled, _source_rect_fields, profile.get("source_rect", null))
	_select_option_by_metadata(_anchor, String(profile.get("anchor", "")))
	_offset_x.value = int(profile.get("pixel_offset", {}).get("x", 0))
	_offset_y.value = int(profile.get("pixel_offset", {}).get("y", 0))
	_select_option_by_metadata(_y_sort, String(profile.get("y_sort_origin", "")))
	_render_width.value = int(profile.get("render_size", {}).get("width", 1))
	_render_height.value = int(profile.get("render_size", {}).get("height", 1))
	_expected_width.value = int(profile.get("expected_footprint_cells", {}).get("width", 1))
	_expected_height.value = int(profile.get("expected_footprint_cells", {}).get("height", 1))
	_set_optional_rect_controls(_bounds_enabled, _bounds_fields, profile.get("visual_bounds", null))
	_loading_controls = false
	_update_preview_and_status()


func _definition_controls_changed() -> void:
	if _loading_controls or _current_definition_id.is_empty():
		return
	_store.update_definition_fields(_current_definition_id, {
		"display_name": _display_name.text,
		"footprint_cells": {"width": int(_footprint_width.value), "height": int(_footprint_height.value)},
		"prototype_color": _prototype_color.color.to_html(false),
		"selectable": _selectable.button_pressed,
		"interactable": _interactable.button_pressed,
	})
	_update_preview_and_status()


func _profile_assignment_changed(index: int) -> void:
	if _loading_controls or _current_definition_id.is_empty():
		return
	var profile_id := _option_metadata(_profile_assignment, index)
	_store.update_definition_fields(_current_definition_id, {"visual_profile_id": profile_id})
	_current_profile_id = profile_id
	_refresh_controls_from_store()


func _visual_controls_changed() -> void:
	if _loading_controls or _current_profile_id.is_empty():
		return
	var source_rect: Variant = null
	if _source_rect_enabled.button_pressed:
		source_rect = _rect_from_controls(_source_rect_fields)
	var visual_bounds: Variant = null
	if _bounds_enabled.button_pressed:
		visual_bounds = _rect_from_controls(_bounds_fields)
	_store.update_visual_profile_fields(_current_profile_id, {
		"texture_path": _texture_path.text,
		"source_rect": source_rect,
		"anchor": _option_metadata(_anchor, _anchor.selected),
		"pixel_offset": {"x": int(_offset_x.value), "y": int(_offset_y.value)},
		"y_sort_origin": _option_metadata(_y_sort, _y_sort.selected),
		"render_size": {"width": int(_render_width.value), "height": int(_render_height.value)},
		"expected_footprint_cells": {"width": int(_expected_width.value), "height": int(_expected_height.value)},
		"visual_bounds": visual_bounds,
	})
	_update_optional_rect_enabled_states()
	_update_preview_and_status()


func _render_width_changed(_value: float) -> void:
	if _loading_controls or _syncing_render_size:
		return
	if _keep_render_ratio.button_pressed:
		_syncing_render_size = true
		_render_height.value = maxf(1.0, round(_render_width.value / _source_aspect_ratio()))
		_syncing_render_size = false
	_visual_controls_changed()


func _render_height_changed(_value: float) -> void:
	if _loading_controls or _syncing_render_size:
		return
	if _keep_render_ratio.button_pressed:
		_syncing_render_size = true
		_render_width.value = maxf(1.0, round(_render_height.value * _source_aspect_ratio()))
		_syncing_render_size = false
	_visual_controls_changed()


func _align_render_size_to_footprint() -> void:
	if _current_definition_id.is_empty():
		return
	_syncing_render_size = true
	_render_width.value = int(_footprint_width.value) * BuildingConfigVisualPreview.DEFAULT_CELL_SIZE
	_render_height.value = int(_footprint_height.value) * BuildingConfigVisualPreview.DEFAULT_CELL_SIZE
	_syncing_render_size = false
	_visual_controls_changed()


func _align_bounds_size_to_footprint() -> void:
	if _current_definition_id.is_empty():
		return
	_loading_controls = true
	_bounds_enabled.button_pressed = true
	_bounds_fields[2].value = int(_footprint_width.value) * BuildingConfigVisualPreview.DEFAULT_CELL_SIZE
	_bounds_fields[3].value = int(_footprint_height.value) * BuildingConfigVisualPreview.DEFAULT_CELL_SIZE
	_loading_controls = false
	_update_optional_rect_enabled_states()
	_visual_controls_changed()


func _source_aspect_ratio() -> float:
	if _source_rect_enabled.button_pressed:
		return maxf(_source_rect_fields[2].value, 1.0) / maxf(_source_rect_fields[3].value, 1.0)
	var path := _texture_path.text
	if path.is_empty() or not ResourceLoader.exists(path, "Texture2D"):
		return maxf(_render_width.value, 1.0) / maxf(_render_height.value, 1.0)
	var texture := ResourceLoader.load(path, "Texture2D") as Texture2D
	if texture == null:
		return maxf(_render_width.value, 1.0) / maxf(_render_height.value, 1.0)
	return maxf(float(texture.get_width()), 1.0) / maxf(float(texture.get_height()), 1.0)


func _open_texture_picker() -> void:
	_texture_file_dialog.current_path = _texture_path.text
	_texture_file_dialog.popup_centered_ratio(0.72)


func _texture_file_selected(path: String) -> void:
	_texture_path.text = path
	_visual_controls_changed()


func _save_pressed() -> void:
	var result := _store.save()
	if not result.ok:
		_status_label.text = String(result.error)
		_update_preview_and_status()
		return
	var reload_result := _store.reload()
	if not reload_result.ok:
		_status_label.text = "Saved, but reload failed: %s" % reload_result.error
		return
	_populate_static_options()
	_status_label.text = "Saved building definitions and visual profiles."
	_refresh_controls_from_store()


func _update_preview_and_status() -> void:
	var definition := _store.get_definition(_current_definition_id).get("definition", {})
	var profile := _store.get_visual_profile(_current_profile_id).get("visual_profile", {})
	var terrain := _selected_terrain_material()
	if _preview != null:
		_preview.set_preview_data(definition, profile, terrain)
	var messages := _store.get_validation_messages()
	_validation_label.text = "Validation: no errors." if messages.is_empty() else "Validation:\n- " + "\n- ".join(messages)
	var has_selection := not _current_definition_id.is_empty()
	var is_dirty := _store.is_dirty()
	_save_button.disabled = not has_selection or not is_dirty or not messages.is_empty()
	if not messages.is_empty():
		_save_button.tooltip_text = "Save blocked until validation errors are fixed."
	elif not is_dirty:
		_save_button.tooltip_text = "No unsaved building changes."
	else:
		_save_button.tooltip_text = "Save building definition and visual profile changes."
	_dirty_label.text = "Unsaved" if _store.is_dirty() else "Saved"


func _selected_terrain_material() -> Dictionary:
	if _terrain_options.item_count == 0 or _terrain_options.selected < 0:
		return {}
	return _store.get_terrain_material(_option_metadata(_terrain_options, _terrain_options.selected)).get("terrain_material", {})


func _set_optional_rect_controls(toggle: CheckButton, fields: Array[SpinBox], value: Variant) -> void:
	toggle.button_pressed = typeof(value) == TYPE_DICTIONARY
	var rect: Dictionary = value if typeof(value) == TYPE_DICTIONARY else {"x": 0, "y": 0, "width": 1, "height": 1}
	for index in range(fields.size()):
		fields[index].value = int(rect.get(["x", "y", "width", "height"][index], 0))
	_update_optional_rect_enabled_states()


func _update_optional_rect_enabled_states() -> void:
	for field in _source_rect_fields:
		field.editable = _source_rect_enabled.button_pressed
	for field in _bounds_fields:
		field.editable = _bounds_enabled.button_pressed


func _rect_from_controls(fields: Array[SpinBox]) -> Dictionary:
	return {
		"x": int(fields[0].value),
		"y": int(fields[1].value),
		"width": int(fields[2].value),
		"height": int(fields[3].value),
	}


func _add_option(options: OptionButton, label: String, metadata: String) -> void:
	options.add_item(label)
	options.set_item_metadata(options.item_count - 1, metadata)


func _option_metadata(options: OptionButton, index: int) -> String:
	if index < 0 or index >= options.item_count:
		return ""
	return String(options.get_item_metadata(index))


func _select_option_by_metadata(options: OptionButton, metadata: String) -> bool:
	for index in range(options.item_count):
		if String(options.get_item_metadata(index)) == metadata:
			options.select(index)
			return true
	return false
