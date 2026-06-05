extends SceneTree

const GameHudScene := preload("res://scenes/ui/game_hud.tscn")
const MainScene := preload("res://scenes/main.tscn")

var _failures: Array[String] = []
var _clear_selection_requests := 0
var _inspect_requests := 0
var _debug_toggle_requests := 0
var _context_requests: Array[Vector2] = []


func _initialize() -> void:
	await _run_checks()

	if _failures.is_empty():
		print("validate_basic_prototype_ui.gd: all checks passed")
		quit(0)
	else:
		for failure in _failures:
			printerr(failure)
		quit(1)


func _run_checks() -> void:
	get_root().size = Vector2i(1024, 768)
	await _verify_hud_selection_states()
	await _verify_details_panel()
	await _verify_context_menu()
	await _verify_status_and_debug()
	await _verify_ui_input_consumption()
	await _verify_startup_scene()


func _verify_hud_selection_states() -> void:
	var hud := _new_hud()
	await process_frame

	_expect(hud.get_selection_field_text(&"Name") == "No selection", "no-selection name should read No selection")
	_expect(hud.get_selection_field_text(&"Type") == "-", "no-selection type should use '-'")
	_expect(hud.get_selection_field_text(&"ID") == "-", "no-selection ID should use '-'")
	_expect(hud.get_selection_field_text(&"Interaction") == "-", "no-selection interaction should use '-'")
	_expect(_button(hud, "DetailsButton").disabled, "Details should be disabled without selection")
	_expect(_button(hud, "InteractButton").disabled, "Interact should be disabled without selection")

	hud.set_selection_snapshot({
		"has_target": true,
		"display_name": "Bakery",
		"entity_type": "building",
		"entity_id": "building.bakery.01",
		"interactable": true,
		"position": Vector2(96.0, 128.0),
	})

	_expect(hud.get_selection_field_text(&"Name") == "Bakery", "selected name should come from snapshot")
	_expect(hud.get_selection_field_text(&"Type") == "building", "selected type should come from snapshot")
	_expect(hud.get_selection_field_text(&"ID") == "building.bakery.01", "selected ID should come from snapshot")
	_expect(hud.get_selection_field_text(&"Interaction") == "Available", "interactable target should read Available")
	_expect(not _button(hud, "DetailsButton").disabled, "Details should be enabled with selection")
	_expect(not _button(hud, "InteractButton").disabled, "Interact should be enabled with selection")

	hud.queue_free()
	await process_frame


func _verify_details_panel() -> void:
	var hud := _new_hud()
	await process_frame
	hud.set_selection_snapshot({
		"has_target": true,
		"display_name": "Bakery",
		"entity_type": "building",
		"entity_id": "building.bakery.01",
		"interactable": true,
		"position": Vector2(96.0, 128.0),
	})
	hud.show_selection_details()
	await process_frame

	_expect(hud.is_details_visible(), "Selection Details should become visible")
	_expect(_label(hud, "SelectionDetailsTitle").text == "Selection Details", "details title should be Selection Details")
	_expect(_label(hud, "PositionValue").text == "96, 128", "details Position should display snapshot position")
	var details_rect: Rect2 = hud.get_details_rect()
	var viewport_width: float = hud.get_viewport_rect().size.x
	_expect(
		is_equal_approx(details_rect.position.x + details_rect.size.x, viewport_width - 12.0),
		"details panel should be fixed at right viewport edge, got rect=%s viewport_width=%s" % [details_rect, viewport_width]
	)

	hud.clear_selection_requested.connect(_on_clear_selection_requested)
	_button(hud, "ClearSelectionButton").pressed.emit()
	_expect(_clear_selection_requests == 1, "Clear Selection should emit one clear_selection_requested signal")
	_expect(not hud.is_details_visible(), "Clear Selection should close details panel")

	hud.queue_free()
	await process_frame


func _verify_context_menu() -> void:
	var hud := _new_hud()
	await process_frame
	hud.show_interaction_context_menu(Vector2(40.0, 60.0), "Bakery", true)
	await process_frame

	_expect(hud.is_context_menu_visible(), "Interaction context menu should become visible")
	_expect(_label(hud, "InteractionTitle").text == "Interaction", "context title should be Interaction")
	_expect(_label(hud, "TargetValue").text == "Bakery", "context Target should display requested target")
	_expect(_label(hud, "ActionValue").text == "Inspect", "context Action should display Inspect")
	_expect(not _button(hud, "InspectButton").disabled, "Inspect should be enabled when target exists")

	hud.show_interaction_context_menu(Vector2(9999.0, 9999.0), "Bakery", true)
	var menu_rect: Rect2 = hud.get_context_menu_rect()
	var viewport_size: Vector2 = hud.get_viewport_rect().size
	_expect(
		menu_rect.position.x + menu_rect.size.x <= viewport_size.x - 12.0 + 0.1,
		"context menu should clamp inside right viewport edge, got rect=%s viewport=%s" % [menu_rect, viewport_size]
	)
	_expect(
		menu_rect.position.y + menu_rect.size.y <= viewport_size.y - 12.0 + 0.1,
		"context menu should clamp inside bottom viewport edge, got rect=%s viewport=%s" % [menu_rect, viewport_size]
	)

	hud.inspect_interaction_requested.connect(_on_inspect_requested)
	_button(hud, "InspectButton").pressed.emit()
	_expect(_inspect_requests == 1, "Inspect should emit one inspect_interaction_requested signal")
	_expect(not hud.is_context_menu_visible(), "Inspect should close context menu")

	hud.show_interaction_context_menu(Vector2(20.0, 20.0), "Bakery", false)
	_expect(_button(hud, "InspectButton").disabled, "Inspect should be disabled when no target exists")
	_button(hud, "CloseContextButton").pressed.emit()
	_expect(not hud.is_context_menu_visible(), "Close should hide context menu")

	hud.queue_free()
	await process_frame


func _verify_status_and_debug() -> void:
	var hud := _new_hud()
	await process_frame
	_expect(hud.get_status_text() == "Ready", "status should start as Ready")
	hud.set_status_text("Interaction failed: too far away")
	_expect(hud.get_status_text() == "Interaction failed: too far away", "status should update from setter")
	hud.set_debug_state(true)
	_expect(hud.get_debug_button_text() == "Debug: On", "debug button should read Debug: On")
	hud.set_debug_state(false)
	_expect(hud.get_debug_button_text() == "Debug: Off", "debug button should read Debug: Off")
	hud.debug_toggle_requested.connect(_on_debug_toggle_requested)
	_button(hud, "DebugToggleButton").pressed.emit()
	_expect(_debug_toggle_requests == 1, "Debug button should emit debug_toggle_requested")
	hud.queue_free()
	await process_frame


func _verify_ui_input_consumption() -> void:
	var hud := _new_hud()
	await process_frame
	var stop_nodes := [
		"SelectionPanel",
		"SelectionDetails",
		"InteractionContextMenu",
		"DetailsButton",
		"InteractButton",
		"CloseDetailsButton",
		"ClearSelectionButton",
		"InspectButton",
		"CloseContextButton",
		"DebugToggleButton",
		"StatusStrip",
	]
	for node_name in stop_nodes:
		var node := hud.find_child(node_name, true, false) as Control
		_expect(node != null, "%s should exist" % node_name)
		if node != null:
			_expect(node.mouse_filter == Control.MOUSE_FILTER_STOP, "%s should consume mouse input" % node_name)
	hud.queue_free()
	await process_frame


func _verify_startup_scene() -> void:
	var scene := MainScene.instantiate()
	get_root().add_child(scene)
	await process_frame
	await physics_frame

	_expect(scene.has_node("UI/GameHud"), "startup scene should contain UI/GameHud")
	if scene.has_node("UI/GameHud"):
		var hud := scene.get_node("UI/GameHud")
		_expect(hud.has_method("set_selection_snapshot"), "GameHud should expose set_selection_snapshot")
		_expect(hud.has_method("show_interaction_context_menu"), "GameHud should expose show_interaction_context_menu")
		_expect(hud.has_signal("inspect_interaction_requested"), "GameHud should expose inspect_interaction_requested")

	scene.queue_free()
	await process_frame
	await process_frame


func _new_hud() -> Node:
	var viewport := SubViewport.new()
	viewport.name = "HudValidationViewport"
	viewport.size = Vector2i(1024, 768)
	get_root().add_child(viewport)
	var hud := GameHudScene.instantiate()
	viewport.add_child(hud)
	return hud


func _button(root: Node, node_name: String) -> Button:
	return root.find_child(node_name, true, false) as Button


func _label(root: Node, node_name: String) -> Label:
	return root.find_child(node_name, true, false) as Label


func _on_clear_selection_requested() -> void:
	_clear_selection_requests += 1


func _on_inspect_requested() -> void:
	_inspect_requests += 1


func _on_debug_toggle_requested() -> void:
	_debug_toggle_requests += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
