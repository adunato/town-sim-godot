@tool
class_name SpritePreviewDock
extends VBoxContainer

const SpritePreviewImporterScript := preload("res://addons/townsim_sprite_preview/sprite_preview_importer.gd")

var _path_edit: LineEdit
var _select_file_button: Button
var _file_dialog: FileDialog
var _action_options: OptionButton
var _variant_options: OptionButton
var _angle_options: OptionButton
var _play_button: Button
var _previous_button: Button
var _next_button: Button
var _preview: TextureRect
var _frame_label: Label
var _atlas_label: Label
var _error_label: Label
var _timer: Timer

var _model: Variant
var _group: Variant
var _frame_index := 0
var _playing := false


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var split := HBoxContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)

	var controls := VBoxContainer.new()
	controls.custom_minimum_size = Vector2(360, 0)
	controls.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(controls)

	var path_row := HBoxContainer.new()
	controls.add_child(path_row)
	_path_edit = LineEdit.new()
	_path_edit.placeholder_text = "Metadata or manifest JSON path"
	_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_edit.editable = false
	path_row.add_child(_path_edit)
	_select_file_button = Button.new()
	_select_file_button.text = "Select JSON"
	_select_file_button.pressed.connect(_browse_pressed)
	path_row.add_child(_select_file_button)

	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.title = "Select Blender Sprite Metadata or Manifest JSON"
	_file_dialog.filters = PackedStringArray(["*.json ; JSON files"])
	_file_dialog.file_selected.connect(_file_selected)
	add_child(_file_dialog)

	_action_options = _add_labeled_options(controls, "Action")
	_variant_options = _add_labeled_options(controls, "Variant")
	_angle_options = _add_labeled_options(controls, "Angle")
	_action_options.item_selected.connect(func(_index: int) -> void: _action_changed())
	_variant_options.item_selected.connect(func(_index: int) -> void: _variant_changed())
	_angle_options.item_selected.connect(func(_index: int) -> void: _angle_changed())

	var playback_row := HBoxContainer.new()
	controls.add_child(playback_row)
	_previous_button = Button.new()
	_previous_button.text = "Previous"
	_previous_button.pressed.connect(_previous_frame)
	playback_row.add_child(_previous_button)
	_play_button = Button.new()
	_play_button.text = "Play"
	_play_button.pressed.connect(_toggle_playback)
	playback_row.add_child(_play_button)
	_next_button = Button.new()
	_next_button.text = "Next"
	_next_button.pressed.connect(_next_frame)
	playback_row.add_child(_next_button)

	_frame_label = Label.new()
	_frame_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_child(_frame_label)
	_atlas_label = Label.new()
	_atlas_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_child(_atlas_label)
	_error_label = Label.new()
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_child(_error_label)

	var preview_panel := PanelContainer.new()
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(preview_panel)

	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(420, 260)
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_panel.add_child(_preview)

	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_timer_advanced)
	add_child(_timer)
	_update_enabled_state()


func _browse_pressed() -> void:
	_file_dialog.popup_centered_ratio(0.75)


func _file_selected(path: String) -> void:
	_path_edit.text = path
	_load_selected_path()


func _add_labeled_options(parent: Control, label_text: String) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(64, 0)
	row.add_child(label)
	var options := OptionButton.new()
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(options)
	return options


func _load_selected_path() -> void:
	var importer = SpritePreviewImporterScript.new()
	_model = importer.import_path(_path_edit.text.strip_edges())
	_playing = false
	_play_button.text = "Play"
	_frame_index = 0
	_populate_from_model()


func _populate_from_model() -> void:
	_action_options.clear()
	_variant_options.clear()
	_angle_options.clear()
	_group = null
	_error_label.text = ""
	if _model == null:
		_update_enabled_state()
		return
	if _model.has_errors():
		var messages: Array[String] = []
		for error in _model.errors:
			messages.append(error.describe())
		_error_label.text = "\n".join(messages)
		_update_enabled_state()
		return
	for action in _model.get_actions():
		_action_options.add_item(action)
	_action_changed()
	_update_enabled_state()


func _action_changed() -> void:
	_variant_options.clear()
	_angle_options.clear()
	if _model == null or _action_options.item_count == 0:
		_angle_changed()
		return
	var action := _action_options.get_item_text(_action_options.selected)
	for variant in _model.get_variants(action):
		_variant_options.add_item(variant)
	_variant_changed()


func _variant_changed() -> void:
	_angle_options.clear()
	if _model == null or _action_options.item_count == 0:
		_angle_changed()
		return
	if _variant_options.item_count == 0:
		_angle_changed()
		return
	var action := _action_options.get_item_text(_action_options.selected)
	var variant := _variant_options.get_item_text(_variant_options.selected)
	for angle in _model.get_angles(action, variant):
		_angle_options.add_item(angle)
	_angle_changed()


func _angle_changed() -> void:
	_group = null
	_frame_index = 0
	if _model == null or _action_options.item_count == 0 or _variant_options.item_count == 0 or _angle_options.item_count == 0:
		_show_current_frame()
		return
	var action := _action_options.get_item_text(_action_options.selected)
	var variant := _variant_options.get_item_text(_variant_options.selected)
	var angle := _angle_options.get_item_text(_angle_options.selected)
	_group = _model.find_group(action, variant, angle)
	_show_current_frame()


func _toggle_playback() -> void:
	_playing = not _playing
	_play_button.text = "Pause" if _playing else "Play"
	if _playing:
		_schedule_next_frame()
	else:
		_timer.stop()


func _previous_frame() -> void:
	if _group == null or _group.frames.is_empty():
		return
	_playing = false
	_play_button.text = "Play"
	_timer.stop()
	_frame_index = posmod(_frame_index - 1, _group.frames.size())
	_show_current_frame()


func _next_frame() -> void:
	if _group == null or _group.frames.is_empty():
		return
	_playing = false
	_play_button.text = "Play"
	_timer.stop()
	_frame_index = (_frame_index + 1) % _group.frames.size()
	_show_current_frame()


func _timer_advanced() -> void:
	if not _playing or _group == null or _group.frames.is_empty():
		return
	_frame_index = (_frame_index + 1) % _group.frames.size()
	_show_current_frame()
	_schedule_next_frame()


func _schedule_next_frame() -> void:
	if _group == null or _group.frames.is_empty():
		return
	var frame: Variant = _group.frames[_frame_index]
	_timer.start(maxf(float(frame.duration_ms) / 1000.0, 0.001))


func _show_current_frame() -> void:
	if _group == null or _group.frames.is_empty():
		_preview.texture = null
		_frame_label.text = "No preview loaded."
		_atlas_label.text = ""
		_update_enabled_state()
		return
	_frame_index = clampi(_frame_index, 0, _group.frames.size() - 1)
	var frame: Variant = _group.frames[_frame_index]
	_preview.texture = frame.texture
	_frame_label.text = "Action: %s | Variant: %s | Angle: %s | Frame: %d/%d | Source frame: %s | Duration: %d ms" % [
		_group.action_name,
		_group.variant,
		_group.angle_label,
		_frame_index + 1,
		_group.frames.size(),
		str(frame.source_blender_frame) if frame.source_blender_frame >= 0 else "unknown",
		frame.duration_ms,
	]
	_atlas_label.text = "Atlas: %s" % _group.atlas_path
	_update_enabled_state()


func _update_enabled_state() -> void:
	var has_group: bool = _group != null and not _group.frames.is_empty()
	_play_button.disabled = not has_group
	_previous_button.disabled = not has_group
	_next_button.disabled = not has_group
