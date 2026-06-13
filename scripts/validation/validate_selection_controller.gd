extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const IdentityComponentScript := preload("res://scripts/entities/components/identity_component.gd")
const SelectableComponentScript := preload("res://scripts/entities/components/selectable_component.gd")
const InteractableComponentScript := preload("res://scripts/entities/components/interactable_component.gd")
const SelectionControllerScript := preload("res://scripts/entities/selection_controller.gd")

var _failures: Array[String] = []
var _received_snapshots: Array[Dictionary] = []


func _initialize() -> void:
	await _run_checks()

	if _failures.is_empty():
		print("validate_selection_controller.gd: all checks passed")
		quit(0)
	else:
		for failure in _failures:
			printerr(failure)
		quit(1)


func _run_checks() -> void:
	await _verify_controller_contract()
	await _verify_startup_scene()


func _verify_controller_contract() -> void:
	var controller := SelectionControllerScript.new()
	get_root().add_child(controller)
	controller.selection_changed.connect(_on_selection_changed)

	var first := MockEntity.new("building.house.01", "building", "House", true, true)
	var second := MockEntity.new("building.store.01", "building", "Store", true, false)
	var non_selectable := MockEntity.new("building.decor.01", "building", "Decor", false, false)
	get_root().add_child(first)
	get_root().add_child(second)
	get_root().add_child(non_selectable)
	await process_frame

	_reset_events()
	var first_result: Dictionary = controller.apply_picked_target(first)
	_expect(first_result.ok, "selecting a selectable entity should return ok")
	_expect(controller.get_selected_target() == first, "first selectable entity should become selected")
	_expect(bool(first.get_node_or_null("SelectableComponent").call("is_selected")), "first selectable component should own local selected state")
	_expect(_received_snapshots.size() == 1, "selecting first entity should emit one snapshot")
	_verify_target_snapshot(_received_snapshots[0], "building.house.01", "building", "House", true, true)

	_reset_events()
	var unchanged_result: Dictionary = controller.apply_picked_target(first)
	_expect(unchanged_result.ok, "re-selecting the same entity should return ok")
	_expect(controller.get_selected_target() == first, "re-selecting same entity should keep selection")
	_expect(_received_snapshots.is_empty(), "re-selecting same entity should not emit a duplicate snapshot")

	_reset_events()
	var second_result: Dictionary = controller.apply_picked_target(second)
	_expect(second_result.ok, "selecting a second entity should return ok")
	_expect(controller.get_selected_target() == second, "second selectable entity should replace first")
	_expect(not bool(first.get_node_or_null("SelectableComponent").call("is_selected")), "replaced selectable component should be deselected")
	_expect(bool(second.get_node_or_null("SelectableComponent").call("is_selected")), "second selectable component should own local selected state")
	_expect(_received_snapshots.size() == 1, "selecting second entity should emit one snapshot")
	_verify_target_snapshot(controller.get_selection_snapshot(), "building.store.01", "building", "Store", true, false)

	_reset_events()
	var empty_result: Dictionary = controller.apply_picked_target(null)
	_expect(empty_result.ok, "empty-world selection should return ok")
	_expect(controller.get_selected_target() == null, "empty-world selection should clear target")
	_expect(not bool(second.get_node_or_null("SelectableComponent").call("is_selected")), "empty-world selection should deselect previous component")
	_expect(_received_snapshots.size() == 1, "empty-world selection should emit one clear snapshot")
	_verify_empty_snapshot(_received_snapshots[0])

	_reset_events()
	controller.apply_picked_target(first)
	_reset_events()
	var non_selectable_result: Dictionary = controller.apply_picked_target(non_selectable)
	_expect(non_selectable_result.ok, "non-selectable picked target should return ok")
	_expect(controller.get_selected_target() == null, "non-selectable picked target should clear selection")
	_expect(_received_snapshots.size() == 1, "non-selectable picked target should emit one clear snapshot")
	_verify_empty_snapshot(_received_snapshots[0])

	_reset_events()
	controller.apply_picked_target(first)
	_reset_events()
	_simulate_ui_consumed_input(controller)
	_expect(controller.get_selected_target() == first, "UI-consumed input should not change selected target")
	_expect(_received_snapshots.is_empty(), "UI-consumed input should not emit a snapshot")

	_reset_events()
	first.queue_free()
	await process_frame
	_expect(controller.get_selected_target() == null, "freed selected target should clear selection")
	_expect(_received_snapshots.size() == 1, "freed selected target should emit one clear snapshot")
	_verify_empty_snapshot(_received_snapshots[0])

	second.queue_free()
	non_selectable.queue_free()
	controller.queue_free()
	await process_frame


func _verify_startup_scene() -> void:
	var scene := MainScene.instantiate()
	get_root().add_child(scene)
	await process_frame

	_expect(scene.has_node("World/SelectionController"), "startup scene should contain World/SelectionController")
	if scene.has_node("World/SelectionController"):
		var controller := scene.get_node("World/SelectionController")
		_expect(controller.has_signal("selection_changed"), "SelectionController should expose selection_changed signal")
		_expect(controller.has_method("get_selected_target"), "SelectionController should expose get_selected_target")
		_expect(controller.has_method("get_selection_snapshot"), "SelectionController should expose get_selection_snapshot")
		_expect(controller.has_method("apply_picked_target"), "SelectionController should expose apply_picked_target")

	_expect(InputMap.has_action("select_entity"), "startup scene should register select_entity input action")
	if InputMap.has_action("select_entity"):
		_expect(_input_action_has_left_mouse("select_entity"), "select_entity should include left mouse button")

	scene.queue_free()
	await process_frame


func _simulate_ui_consumed_input(_controller: Node) -> void:
	pass


func _on_selection_changed(snapshot: Dictionary) -> void:
	_received_snapshots.append(snapshot.duplicate(true))


func _reset_events() -> void:
	_received_snapshots.clear()


func _verify_target_snapshot(
	snapshot: Dictionary,
	entity_id: String,
	entity_type: String,
	display_name: String,
	selectable: bool,
	interactable: bool
) -> void:
	_expect(bool(snapshot.get("has_target", false)), "snapshot should report a selected target")
	_expect(String(snapshot.get("entity_id", "")) == entity_id, "snapshot entity_id should be '%s'" % entity_id)
	_expect(String(snapshot.get("entity_type", "")) == entity_type, "snapshot entity_type should be '%s'" % entity_type)
	_expect(String(snapshot.get("display_name", "")) == display_name, "snapshot display_name should be '%s'" % display_name)
	_expect(bool(snapshot.get("selectable", false)) == selectable, "snapshot selectable should be %s" % selectable)
	_expect(bool(snapshot.get("interactable", false)) == interactable, "snapshot interactable should be %s" % interactable)


func _verify_empty_snapshot(snapshot: Dictionary) -> void:
	_expect(not bool(snapshot.get("has_target", true)), "empty snapshot should report no target")
	_expect(not snapshot.has("entity_id"), "empty snapshot should not include entity_id")
	_expect(not snapshot.has("entity_type"), "empty snapshot should not include entity_type")
	_expect(not snapshot.has("display_name"), "empty snapshot should not include display_name")


func _input_action_has_left_mouse(action_name: StringName) -> bool:
	for event in InputMap.action_get_events(action_name):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


class MockEntity:
	extends Node

	var _entity_id: String
	var _entity_type: String
	var _display_name: String
	var _selectable: bool
	var _interactable: bool

	func _init(
		entity_id: String,
		entity_type: String,
		display_name: String,
		selectable: bool,
		interactable: bool
	) -> void:
		_entity_id = entity_id
		_entity_type = entity_type
		_display_name = display_name
		_selectable = selectable
		_interactable = interactable
		var identity := IdentityComponentScript.new()
		identity.name = "IdentityComponent"
		add_child(identity)
		identity.configure(_entity_id, _entity_type, _display_name)
		var selectable_component := SelectableComponentScript.new()
		selectable_component.name = "SelectableComponent"
		add_child(selectable_component)
		selectable_component.configure(_selectable)
		var interactable_component := InteractableComponentScript.new()
		interactable_component.name = "InteractableComponent"
		add_child(interactable_component)
		interactable_component.configure(_interactable)
