extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const IdentityComponentScript := preload("res://scripts/entities/components/identity_component.gd")
const PickableComponentScript := preload("res://scripts/entities/components/pickable_component.gd")
const SelectableComponentScript := preload("res://scripts/entities/components/selectable_component.gd")
const InteractableComponentScript := preload("res://scripts/entities/components/interactable_component.gd")
const PickingControllerScript := preload("res://scripts/entities/picking_controller.gd")
const SelectionControllerScript := preload("res://scripts/entities/selection_controller.gd")

var _failures: Array[String] = []
var _hover_snapshots: Array[Dictionary] = []


func _initialize() -> void:
	await _run_checks()

	if _failures.is_empty():
		print("validate_hover_and_picking.gd: all checks passed")
		quit(0)
	else:
		for failure in _failures:
			printerr(failure)
		quit(1)


func _run_checks() -> void:
	await _verify_picking_contract()
	await _verify_main_scene_integration()


func _verify_picking_contract() -> void:
	var owner := Node.new()
	get_root().add_child(owner)
	var first := MockBuildingEntity.new("building.first", "First", Rect2(Vector2(10, 10), Vector2(20, 20)), true, true)
	var second := MockBuildingEntity.new("building.second", "Second", Rect2(Vector2(15, 15), Vector2(20, 20)), true, false)
	owner.add_child(first)
	owner.add_child(second)

	var picker := PickingControllerScript.new()
	get_root().add_child(picker)
	var configure_result: Dictionary = picker.configure(owner)
	_expect(configure_result.ok, "PickingController should configure with buildings owner")
	picker.hover_changed.connect(_on_hover_changed)
	await process_frame

	var first_only_result: Dictionary = picker.pick_at_world_point(Vector2(12, 12))
	_verify_target_result(first_only_result, first, "building.first", "First", true, true)

	var overlap_result: Dictionary = picker.pick_at_world_point(Vector2(16, 16))
	_verify_target_result(overlap_result, second, "building.second", "Second", true, false)

	var empty_result: Dictionary = picker.pick_at_world_point(Vector2(100, 100))
	_verify_empty_result(empty_result)

	_reset_hover_events()
	var hover_result: Dictionary = picker.update_hover_from_result(first_only_result)
	_expect(hover_result.ok and hover_result.changed, "hovering first entity should report a change")
	_expect(picker.get_hovered_target() == first, "hovered target should be first entity")
	_expect(_hover_snapshots.size() == 1, "hovering first entity should emit one hover snapshot")
	_verify_target_result(_hover_snapshots[0], first, "building.first", "First", true, true)

	var duplicate_hover_result: Dictionary = picker.update_hover_from_result(first_only_result)
	_expect(duplicate_hover_result.ok and not duplicate_hover_result.changed, "repeating same hover should not report a change")
	_expect(_hover_snapshots.size() == 1, "repeating same hover should not emit another snapshot")

	var clear_hover_result: Dictionary = picker.update_hover_from_result(empty_result)
	_expect(clear_hover_result.ok and clear_hover_result.changed, "empty pick should clear hover")
	_expect(picker.get_hovered_target() == null, "empty pick should leave no hovered target")
	_expect(_hover_snapshots.size() == 2, "clearing hover should emit one clear snapshot")
	_verify_empty_result(_hover_snapshots[1])

	var before_ui_consumed_hover := picker.get_hovered_target()
	var before_ui_consumed_count := _hover_snapshots.size()
	_simulate_ui_consumed_input()
	_expect(picker.get_hovered_target() == before_ui_consumed_hover, "UI-consumed input should not change hover when no unhandled call is made")
	_expect(_hover_snapshots.size() == before_ui_consumed_count, "UI-consumed input should not emit hover changes")

	var default_screen_result: Dictionary = picker.pick_at_screen_position(Vector2(12, 12))
	_verify_target_result(default_screen_result, first, "building.first", "First", true, true)

	picker.queue_free()
	owner.queue_free()
	await process_frame


func _verify_main_scene_integration() -> void:
	var scene := MainScene.instantiate()
	get_root().add_child(scene)
	await process_frame
	await physics_frame

	_expect(scene.has_node("World/PickingController"), "startup scene should contain World/PickingController")
	_expect(scene.has_node("World/SelectionController"), "startup scene should contain World/SelectionController")
	_expect(scene.has_node("World/Buildings"), "startup scene should contain World/Buildings")
	if not scene.has_node("World/PickingController") or not scene.has_node("World/SelectionController") or not scene.has_node("World/Buildings"):
		scene.queue_free()
		await process_frame
		return

	var picker := scene.get_node("World/PickingController")
	_expect(picker.has_method("pick_at_screen_position"), "PickingController should expose pick_at_screen_position")
	_expect(picker.has_method("update_hover_at_screen_position"), "PickingController should expose update_hover_at_screen_position")
	_expect(picker.has_signal("hover_changed"), "PickingController should expose hover_changed")

	var buildings := scene.get_node("World/Buildings")
	var entities: Array[Node] = buildings.call("get_building_entities")
	_expect(not entities.is_empty(), "startup scene should create generated building entities for picking")
	if entities.is_empty():
		scene.queue_free()
		await process_frame
		return

	var target := entities[0]
	var pickable := target.get_node_or_null("PickableComponent")
	_expect(pickable != null, "generated building should expose PickableComponent for picking validation")
	if pickable == null:
		scene.queue_free()
		await process_frame
		return
	var world_rect: Rect2 = pickable.call("get_world_rect")
	var screen_position: Vector2 = get_root().get_canvas_transform() * world_rect.get_center()
	var pick_result: Dictionary = picker.call("pick_at_screen_position", screen_position)
	_expect(bool(pick_result.get("has_target", false)), "screen-space pick over generated building should find a target")
	_expect(pick_result.get("target", null) == target, "screen-space pick should return the generated building under the cursor")

	var motion_event := InputEventMouseMotion.new()
	motion_event.position = screen_position
	scene.call("_unhandled_input", motion_event)
	_expect(picker.call("get_hovered_target") == target, "main scene mouse motion should update hovered target")

	var click_event := InputEventMouseButton.new()
	click_event.button_index = MOUSE_BUTTON_LEFT
	click_event.pressed = true
	click_event.position = screen_position
	scene.call("_apply_selection_input", click_event)
	var selection_controller := scene.get_node("World/SelectionController")
	_expect(selection_controller.call("get_selected_target") == target, "left-clicking generated building should select that same building")

	var empty_click := InputEventMouseButton.new()
	empty_click.button_index = MOUSE_BUTTON_LEFT
	empty_click.pressed = true
	empty_click.position = Vector2(-1000, -1000)
	scene.call("_apply_selection_input", empty_click)
	_expect(selection_controller.call("get_selected_target") == null, "left-clicking empty world should clear selection")

	scene.queue_free()
	await process_frame
	await process_frame


func _verify_target_result(
	result: Dictionary,
	target: Node,
	entity_id: String,
	display_name: String,
	selectable: bool,
	interactable: bool
) -> void:
	_expect(bool(result.get("has_target", false)), "picking result should report a target")
	_expect(result.get("target", null) == target, "picking result target should match expected entity")
	_expect(String(result.get("entity_id", "")) == entity_id, "picking result entity_id should be '%s'" % entity_id)
	_expect(String(result.get("entity_type", "")) == "building", "picking result entity_type should be building")
	_expect(String(result.get("display_name", "")) == display_name, "picking result display_name should be '%s'" % display_name)
	_expect(bool(result.get("selectable", false)) == selectable, "picking result selectable should be %s" % selectable)
	_expect(bool(result.get("interactable", false)) == interactable, "picking result interactable should be %s" % interactable)
	_expect(result.get("world_rect", Rect2()) is Rect2, "picking result should include world_rect")


func _verify_empty_result(result: Dictionary) -> void:
	_expect(not bool(result.get("has_target", true)), "empty picking result should report no target")
	_expect(not result.has("target"), "empty picking result should not include target")


func _on_hover_changed(snapshot: Dictionary) -> void:
	_hover_snapshots.append(snapshot.duplicate(true))


func _reset_hover_events() -> void:
	_hover_snapshots.clear()


func _simulate_ui_consumed_input() -> void:
	pass


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


class MockBuildingEntity:
	extends Node

	var _entity_id: String
	var _display_name: String
	var _world_rect: Rect2
	var _selectable: bool
	var _interactable: bool

	func _init(entity_id: String, display_name: String, world_rect: Rect2, selectable: bool, interactable: bool) -> void:
		_entity_id = entity_id
		_display_name = display_name
		_world_rect = world_rect
		_selectable = selectable
		_interactable = interactable
		var identity := IdentityComponentScript.new()
		identity.name = "IdentityComponent"
		add_child(identity)
		identity.configure(_entity_id, "building", _display_name)
		var pickable := PickableComponentScript.new()
		pickable.name = "PickableComponent"
		add_child(pickable)
		pickable.configure(_world_rect)
		var selectable_component := SelectableComponentScript.new()
		selectable_component.name = "SelectableComponent"
		add_child(selectable_component)
		selectable_component.configure(_selectable)
		var interactable_component := InteractableComponentScript.new()
		interactable_component.name = "InteractableComponent"
		add_child(interactable_component)
		interactable_component.configure(_interactable)
