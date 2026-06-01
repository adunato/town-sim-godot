extends Node

const GridMapModelScript := preload("res://scripts/map/grid_map_model.gd")

@onready var _debug_overlay := $World/DebugOverlay
@onready var _map_renderer := $World/Map
@onready var _player := $World/Player
@onready var _debug_readout := $UI/DebugReadout

var _map_model: RefCounted


func _ready() -> void:
	_ensure_debug_input_actions()
	_ensure_movement_input_actions()
	_map_model = GridMapModelScript.new()

	var load_result: Dictionary = _map_model.load_from_file()
	if not load_result.ok:
		push_error(load_result.error)
		return

	_map_renderer.set_map_model(_map_model)
	_place_player_at_spawn()
	_debug_overlay.set_map_model(_map_model)
	_debug_readout.set_seed(_map_model.seed)
	_debug_overlay.debug_state_changed.connect(_debug_readout.set_overlay_state)
	_debug_readout.set_overlay_state(_debug_overlay.is_overlay_enabled(), _debug_overlay.current_mode, _debug_overlay.get_legend_entries())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug_overlay") or _is_key_pressed(event, KEY_F3):
		_debug_overlay.toggle_overlay()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cycle_debug_overlay") or _is_key_pressed(event, KEY_F4):
		_debug_overlay.cycle_mode()
		get_viewport().set_input_as_handled()


func _ensure_debug_input_actions() -> void:
	_add_key_action("toggle_debug_overlay", KEY_F3)
	_add_key_action("cycle_debug_overlay", KEY_F4)


func _ensure_movement_input_actions() -> void:
	_add_key_action("move_up", KEY_W)
	_add_key_action("move_down", KEY_S)
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)


func _place_player_at_spawn() -> void:
	_player.set_map_model(_map_model)
	var spawn_result: Dictionary = _map_model.cell_to_world(_map_model.player_spawn_cell)
	if not spawn_result.ok:
		push_error("Unable to place player at spawn cell %s: %s" % [_map_model.player_spawn_cell, spawn_result.error])
		return

	_player.global_position = spawn_result.world_position


func _add_key_action(action_name: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)

	for event in InputMap.action_get_events(action_name):
		if event is InputEventKey and event.keycode == keycode:
			return

	var key_event := InputEventKey.new()
	key_event.keycode = keycode
	InputMap.action_add_event(action_name, key_event)


func _is_key_pressed(event: InputEvent, keycode: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == keycode
