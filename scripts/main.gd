extends Node

const GridMapModelScript := preload("res://scripts/map/grid_map_model.gd")
const BuildingDataRegistryScript := preload("res://scripts/buildings/building_data_registry.gd")
const TerrainGeneratorScript := preload("res://scripts/terrain/terrain_generator.gd")

@onready var _debug_overlay := $World/DebugOverlay
@onready var _terrain_renderer := $World/Terrain
@onready var _map_renderer := $World/Map
@onready var _player := $World/Player
@onready var _buildings := $World/Buildings
@onready var _picking_controller := $World/PickingController
@onready var _selection_controller := $World/SelectionController
@onready var _highlight_controller := $World/HighlightController
@onready var _proximity_controller := $World/ProximityController
@onready var _interaction_controller := $World/InteractionController
@onready var _game_hud := $UI/GameHud
@onready var _debug_readout := $UI/DebugReadout

var _map_model: RefCounted
var _pending_interaction_target: Node


func _ready() -> void:
	_ensure_debug_input_actions()
	_ensure_movement_input_actions()
	_ensure_selection_input_actions()
	_map_model = GridMapModelScript.new()

	var load_result: Dictionary = _map_model.load_from_file()
	if not load_result.ok:
		push_error(load_result.error)
		return

	_configure_terrain()
	_map_renderer.set_map_model(_map_model)
	_configure_building_entities()
	_configure_picking()
	_configure_highlights()
	_place_player_at_spawn()
	_configure_proximity()
	_configure_interaction()
	_configure_hud()
	_configure_player_camera()
	_debug_overlay.set_map_model(_map_model)
	_debug_readout.set_seed(_map_model.seed)
	_debug_overlay.debug_state_changed.connect(_debug_readout.set_overlay_state)
	_debug_overlay.debug_state_changed.connect(_game_hud.set_debug_state)
	_debug_readout.set_overlay_state(_debug_overlay.is_overlay_enabled(), _debug_overlay.current_mode, _debug_overlay.get_legend_entries())
	_game_hud.set_debug_state(_debug_overlay.is_overlay_enabled(), _debug_overlay.current_mode, _debug_overlay.get_legend_entries())


func _configure_terrain() -> void:
	var generator := TerrainGeneratorScript.new()
	var generate_result: Dictionary = generator.load_and_generate()
	if not generate_result.ok:
		push_error("Unable to configure terrain renderer: %s" % generate_result.error)
		return

	var render_result: Dictionary = _terrain_renderer.set_terrain_data(generate_result.terrain_data)
	if not render_result.ok:
		push_error("Unable to configure terrain renderer: %s" % render_result.error)


func _configure_building_entities() -> void:
	if not _map_renderer.get_placement_error().is_empty():
		push_error("Unable to configure building entities: %s" % _map_renderer.get_placement_error())
		return

	var registry := BuildingDataRegistryScript.new()
	var definitions_result: Dictionary = registry.load_definitions()
	if not definitions_result.ok:
		push_error("Unable to configure building entities: %s" % definitions_result.error)
		return
	var visual_profiles_result: Dictionary = registry.load_visual_profiles()
	if not visual_profiles_result.ok:
		push_error("Unable to configure building entities: %s" % visual_profiles_result.error)
		return

	var entity_result: Dictionary = _buildings.build_from_instances(_map_model, registry, _map_renderer.get_building_instances())
	if not entity_result.ok:
		push_error("Unable to configure building entities: %s" % entity_result.error)


func _configure_picking() -> void:
	var picking_result: Dictionary = _picking_controller.configure(_buildings)
	if not picking_result.ok:
		push_error("Unable to configure picking: %s" % picking_result.error)


func _configure_highlights() -> void:
	var highlight_result: Dictionary = _highlight_controller.configure(_buildings, _selection_controller, _picking_controller)
	if not highlight_result.ok:
		push_error("Unable to configure highlights: %s" % highlight_result.error)


func _configure_proximity() -> void:
	var proximity_result: Dictionary = _proximity_controller.configure(_player, _buildings, _highlight_controller, _debug_overlay)
	if not proximity_result.ok:
		push_error("Unable to configure proximity: %s" % proximity_result.error)


func _configure_interaction() -> void:
	var interaction_result: Dictionary = _interaction_controller.configure(
		_picking_controller,
		_selection_controller,
		_proximity_controller,
		_highlight_controller
	)
	if not interaction_result.ok:
		push_error("Unable to configure interaction: %s" % interaction_result.error)


func _configure_hud() -> void:
	_game_hud.set_selection_snapshot(_selection_controller.get_selection_snapshot())
	_selection_controller.selection_changed.connect(_game_hud.set_selection_snapshot)
	_interaction_controller.interaction_attempted.connect(_on_interaction_attempted)
	_game_hud.clear_selection_requested.connect(_selection_controller.clear_selection)
	_game_hud.debug_toggle_requested.connect(_debug_overlay.toggle_overlay)
	_game_hud.interaction_context_requested.connect(_open_selected_interaction_context)
	_game_hud.inspect_interaction_requested.connect(_inspect_pending_interaction_target)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug_overlay") or _is_key_pressed(event, KEY_F3):
		_debug_overlay.toggle_overlay()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cycle_debug_overlay") or _is_key_pressed(event, KEY_F4):
		_debug_overlay.cycle_mode()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("select_entity") or _is_left_mouse_pressed(event):
		_apply_selection_input(event)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact_entity") or _is_right_mouse_pressed(event):
		_open_interaction_context_from_input(event)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		_picking_controller.update_hover_at_screen_position(event.position)


func _ensure_debug_input_actions() -> void:
	_add_key_action("toggle_debug_overlay", KEY_F3)
	_add_key_action("cycle_debug_overlay", KEY_F4)


func _ensure_movement_input_actions() -> void:
	_add_key_action("move_up", KEY_W)
	_add_key_action("move_down", KEY_S)
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)


func _ensure_selection_input_actions() -> void:
	_add_mouse_button_action("select_entity", MOUSE_BUTTON_LEFT)
	_add_mouse_button_action("interact_entity", MOUSE_BUTTON_RIGHT)


func _place_player_at_spawn() -> void:
	_player.set_map_model(_map_model)
	var spawn_result: Dictionary = _map_model.cell_to_world(_map_model.player_spawn_cell)
	if not spawn_result.ok:
		push_error("Unable to place player at spawn cell %s: %s" % [_map_model.player_spawn_cell, spawn_result.error])
		return

	_player.global_position = spawn_result.world_position


func _configure_player_camera() -> void:
	if not _player.has_node("PlayerCamera"):
		push_error("Unable to configure player camera: PlayerCamera node is missing.")
		return

	var camera := _player.get_node("PlayerCamera")
	if not camera.has_method("configure_for_map"):
		push_error("Unable to configure player camera: PlayerCamera does not expose configure_for_map.")
		return

	var configure_result: Dictionary = camera.call("configure_for_map", _map_model)
	if not configure_result.ok:
		push_error("Unable to configure player camera: %s" % configure_result.error)


func _add_key_action(action_name: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)

	for event in InputMap.action_get_events(action_name):
		if event is InputEventKey and event.keycode == keycode:
			return

	var key_event := InputEventKey.new()
	key_event.keycode = keycode
	InputMap.action_add_event(action_name, key_event)


func _add_mouse_button_action(action_name: StringName, button_index: MouseButton) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)

	for event in InputMap.action_get_events(action_name):
		if event is InputEventMouseButton and event.button_index == button_index:
			return

	var mouse_event := InputEventMouseButton.new()
	mouse_event.button_index = button_index
	InputMap.action_add_event(action_name, mouse_event)


func _apply_selection_input(event: InputEvent) -> void:
	var screen_position := get_viewport().get_mouse_position()
	if event is InputEventMouseButton:
		screen_position = event.position

	var pick_result: Dictionary = _picking_controller.pick_at_screen_position(screen_position)
	if bool(pick_result.get("has_target", false)):
		_selection_controller.apply_picked_target(pick_result.target)
	else:
		_selection_controller.apply_picked_target(null)


func _open_interaction_context_from_input(event: InputEvent) -> void:
	var screen_position := get_viewport().get_mouse_position()
	if event is InputEventMouseButton:
		screen_position = event.position

	var pick_result: Dictionary = _picking_controller.pick_at_screen_position(screen_position)
	_picking_controller.update_hover_from_result(pick_result)
	var cursor_target: Node = _selection_controller.get_selected_target()
	if bool(pick_result.get("has_target", false)):
		cursor_target = pick_result.target
	_open_interaction_context(screen_position, cursor_target)


func _open_selected_interaction_context(screen_position: Vector2) -> void:
	_open_interaction_context(screen_position, _selection_controller.get_selected_target())


func _open_interaction_context(screen_position: Vector2, target: Node) -> void:
	_pending_interaction_target = target
	if target == null:
		_game_hud.set_status_text("No interaction target.")
		return
	_game_hud.show_interaction_context_menu(screen_position, _target_display_name(target), true)


func _inspect_pending_interaction_target() -> void:
	var result: Dictionary = _interaction_controller.attempt_interaction(_pending_interaction_target)
	_game_hud.set_status_text(String(result.get("message", "")))


func _on_interaction_attempted(result: Dictionary) -> void:
	_game_hud.set_status_text(String(result.get("message", "")))


func _target_display_name(target: Node) -> String:
	if target == null:
		return ""
	if target.has_method("get_display_name"):
		return String(target.call("get_display_name"))
	var identity := target.get_node_or_null("IdentityComponent")
	if identity != null and identity.has_method("get_display_name"):
		return String(identity.call("get_display_name"))
	return target.name


func _is_key_pressed(event: InputEvent, keycode: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == keycode


func _is_left_mouse_pressed(event: InputEvent) -> bool:
	return event is InputEventMouseButton \
		and event.pressed \
		and event.button_index == MOUSE_BUTTON_LEFT


func _is_right_mouse_pressed(event: InputEvent) -> bool:
	return event is InputEventMouseButton \
		and event.pressed \
		and event.button_index == MOUSE_BUTTON_RIGHT
