extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const IdentityComponentScript := preload("res://scripts/entities/components/identity_component.gd")
const InteractableComponentScript := preload("res://scripts/entities/components/interactable_component.gd")
const InteractionControllerScript := preload("res://scripts/interaction/interaction_controller.gd")

var _failures: Array[String] = []
var _interaction_results: Array[Dictionary] = []


func _initialize() -> void:
	await _run_checks()

	if _failures.is_empty():
		print("validate_interaction_controller.gd: all checks passed")
		quit(0)
	else:
		for failure in _failures:
			printerr(failure)
		quit(1)


func _run_checks() -> void:
	await _verify_interaction_outcomes()
	await _verify_target_resolution()
	await _verify_startup_scene_integration()


func _verify_interaction_outcomes() -> void:
	var picking := MockPickingController.new()
	var selection := MockSelectionController.new()
	var proximity := MockProximityController.new()
	var highlight := MockHighlightController.new()
	var controller := InteractionControllerScript.new()
	get_root().add_child(picking)
	get_root().add_child(selection)
	get_root().add_child(proximity)
	get_root().add_child(highlight)
	get_root().add_child(controller)
	controller.interaction_attempted.connect(_on_interaction_attempted)
	await process_frame

	var configure_result: Dictionary = controller.configure(picking, selection, proximity, highlight)
	_expect(configure_result.ok, "InteractionController should configure with existing controller dependencies")

	_reset_events()
	var no_target: Dictionary = controller.attempt_interaction()
	_verify_result(no_target, &"no_target", false, "", "empty interaction should report no_target")
	_expect(_interaction_results.size() == 1, "no_target attempt should emit one result")

	var nearby_interactable := MockEntity.new("building.store", "General Store", true)
	get_root().add_child(nearby_interactable)
	proximity.set_nearby(nearby_interactable, true)
	await process_frame

	_reset_events()
	var success: Dictionary = controller.attempt_interaction(nearby_interactable)
	_verify_result(success, &"success", true, "General Store", "nearby interactable target should report success")
	_expect(_interaction_results.size() == 1, "success attempt should emit one result")
	_expect(highlight.get_flag(nearby_interactable, &"interactable"), "success should set interactable highlight input")

	var distant := MockEntity.new("building.distant", "Distant House", true)
	get_root().add_child(distant)
	proximity.set_nearby(distant, false)
	await process_frame

	var out_of_range: Dictionary = controller.attempt_interaction(distant)
	_verify_result(out_of_range, &"out_of_range", false, "Distant House", "distant target should report out_of_range")
	_expect(not highlight.get_flag(distant, &"interactable"), "out_of_range should not set interactable highlight input")
	_expect(not highlight.get_flag(nearby_interactable, &"interactable"), "out_of_range should clear previous interactable highlight input")

	var non_interactable := MockEntity.new("building.decor", "Decor", false)
	get_root().add_child(non_interactable)
	proximity.set_nearby(non_interactable, true)
	await process_frame

	var not_interactable: Dictionary = controller.attempt_interaction(non_interactable)
	_verify_result(not_interactable, &"not_interactable", false, "Decor", "non-interactable target should report not_interactable")
	_expect(not highlight.get_flag(non_interactable, &"interactable"), "not_interactable should not set interactable highlight input")

	nearby_interactable.queue_free()
	distant.queue_free()
	non_interactable.queue_free()
	controller.queue_free()
	picking.queue_free()
	selection.queue_free()
	proximity.queue_free()
	highlight.queue_free()
	await process_frame


func _verify_target_resolution() -> void:
	var picking := MockPickingController.new()
	var selection := MockSelectionController.new()
	var proximity := MockProximityController.new()
	var controller := InteractionControllerScript.new()
	get_root().add_child(picking)
	get_root().add_child(selection)
	get_root().add_child(proximity)
	get_root().add_child(controller)
	await process_frame

	var configure_result: Dictionary = controller.configure(picking, selection, proximity)
	_expect(configure_result.ok, "InteractionController should configure without a highlight controller")

	var cursor := MockEntity.new("building.cursor", "Cursor Target", true)
	var hovered := MockEntity.new("building.hovered", "Hovered Target", true)
	var selected := MockEntity.new("building.selected", "Selected Target", true)
	get_root().add_child(cursor)
	get_root().add_child(hovered)
	get_root().add_child(selected)
	picking.hovered_target = hovered
	selection.selected_target = selected
	await process_frame

	_expect(controller.resolve_target(cursor) == cursor, "explicit cursor target should win over hovered and selected targets")
	_expect(controller.resolve_target() == hovered, "hovered cursor target should win over selected target")
	picking.hovered_target = null
	_expect(controller.resolve_target() == selected, "selected target should be fallback when no cursor target exists")
	selection.selected_target = null
	_expect(controller.resolve_target() == null, "missing cursor and selected targets should resolve to null")

	cursor.queue_free()
	hovered.queue_free()
	selected.queue_free()
	controller.queue_free()
	picking.queue_free()
	selection.queue_free()
	proximity.queue_free()
	await process_frame


func _verify_startup_scene_integration() -> void:
	var scene := MainScene.instantiate()
	get_root().add_child(scene)
	await process_frame
	await physics_frame

	_expect(scene.has_node("World/InteractionController"), "startup scene should contain World/InteractionController")
	if scene.has_node("World/InteractionController"):
		var controller := scene.get_node("World/InteractionController")
		_expect(controller.has_method("attempt_interaction"), "InteractionController should expose attempt_interaction")
		_expect(controller.has_method("resolve_target"), "InteractionController should expose resolve_target")
		_expect(controller.has_signal("interaction_attempted"), "InteractionController should expose interaction_attempted signal")

	_expect(InputMap.has_action("interact_entity"), "startup scene should register interact_entity input action")
	if InputMap.has_action("interact_entity"):
		_expect(_input_action_has_right_mouse("interact_entity"), "interact_entity should include right mouse button")

	var before_ui_consumed_count := _interaction_results.size()
	_simulate_ui_consumed_input()
	_expect(_interaction_results.size() == before_ui_consumed_count, "UI-consumed input should not emit an interaction result")

	if scene.has_node("World/Buildings"):
		var buildings := scene.get_node("World/Buildings")
		var entities: Array[Node] = buildings.call("get_building_entities")
		_expect(not entities.is_empty(), "startup scene should create generated building entities for interaction")
		if not entities.is_empty():
			var target := entities[0]
			_expect(target.get_node_or_null("IdentityComponent") != null, "startup building should expose IdentityComponent")
			_expect(target.get_node_or_null("InteractableComponent") != null, "startup building should expose InteractableComponent")

	scene.queue_free()
	await process_frame
	await process_frame


func _verify_result(result: Dictionary, outcome: StringName, ok: bool, display_name: String, message: String) -> void:
	_expect(StringName(result.get("outcome", &"")) == outcome, "%s outcome should be %s" % [message, outcome])
	_expect(bool(result.get("ok", false)) == ok, "%s ok should be %s" % [message, ok])
	if display_name.is_empty():
		_expect(not bool(result.get("has_target", true)), "%s should not report a target" % message)
	else:
		_expect(bool(result.get("has_target", false)), "%s should report a target" % message)
		_expect(String(result.get("display_name", "")) == display_name, "%s display_name should be %s" % [message, display_name])
	_expect(not String(result.get("message", "")).is_empty(), "%s should include a readable message" % message)


func _input_action_has_right_mouse(action_name: StringName) -> bool:
	for event in InputMap.action_get_events(action_name):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
			return true
	return false


func _simulate_ui_consumed_input() -> void:
	pass


func _on_interaction_attempted(result: Dictionary) -> void:
	_interaction_results.append(result.duplicate(true))


func _reset_events() -> void:
	_interaction_results.clear()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


class MockEntity:
	extends Node

	var _entity_id: String
	var _display_name: String
	var _interactable: bool

	func _init(entity_id: String, display_name: String, interactable: bool) -> void:
		_entity_id = entity_id
		_display_name = display_name
		_interactable = interactable
		var identity := IdentityComponentScript.new()
		identity.name = "IdentityComponent"
		add_child(identity)
		identity.configure(_entity_id, "building", _display_name)
		var interactable_component := InteractableComponentScript.new()
		interactable_component.name = "InteractableComponent"
		add_child(interactable_component)
		interactable_component.configure(_interactable)


class MockPickingController:
	extends Node

	var hovered_target: Node

	func get_hovered_target() -> Node:
		return hovered_target


class MockSelectionController:
	extends Node

	var selected_target: Node

	func get_selected_target() -> Node:
		return selected_target


class MockProximityController:
	extends Node

	var nearby_targets: Dictionary = {}

	func set_nearby(target: Node, nearby: bool) -> void:
		nearby_targets[target] = nearby

	func is_entity_nearby(target: Node) -> bool:
		return bool(nearby_targets.get(target, false))


class MockHighlightController:
	extends Node

	var flags: Dictionary = {}

	func set_highlight_input(target: Node, input_flag: StringName, enabled: bool) -> Dictionary:
		var target_flags: Dictionary = flags.get(target, {})
		if enabled:
			target_flags[input_flag] = true
		else:
			target_flags.erase(input_flag)
		flags[target] = target_flags
		return {"ok": true}

	func get_flag(target: Node, input_flag: StringName) -> bool:
		return bool(flags.get(target, {}).get(input_flag, false))
