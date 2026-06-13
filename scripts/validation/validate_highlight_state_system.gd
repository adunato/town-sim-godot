extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const IdentityComponentScript := preload("res://scripts/entities/components/identity_component.gd")
const PickableComponentScript := preload("res://scripts/entities/components/pickable_component.gd")
const SelectableComponentScript := preload("res://scripts/entities/components/selectable_component.gd")
const HighlightableComponentScript := preload("res://scripts/entities/components/highlightable_component.gd")
const InteractableComponentScript := preload("res://scripts/entities/components/interactable_component.gd")
const HighlightControllerScript := preload("res://scripts/entities/highlight_controller.gd")
const PickingControllerScript := preload("res://scripts/entities/picking_controller.gd")
const SelectionControllerScript := preload("res://scripts/entities/selection_controller.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	await _run_checks()

	if _failures.is_empty():
		print("validate_highlight_state_system.gd: all checks passed")
		quit(0)
	else:
		for failure in _failures:
			printerr(failure)
		quit(1)


func _run_checks() -> void:
	await _verify_controller_contract()
	await _verify_selection_and_hover_wiring()
	await _verify_missing_visual_diagnostic()
	await _verify_main_scene_integration()


func _verify_controller_contract() -> void:
	var owner := Node.new()
	var selection := SelectionControllerScript.new()
	var picker := PickingControllerScript.new()
	var building := MockBuildingEntity.new("building.first", "First")
	get_root().add_child(owner)
	get_root().add_child(selection)
	get_root().add_child(picker)
	owner.add_child(building)
	await process_frame

	var picker_result: Dictionary = picker.configure(owner)
	_expect(picker_result.ok, "picking controller should configure in highlight fixture")

	var controller := HighlightControllerScript.new()
	get_root().add_child(controller)
	var configure_result: Dictionary = controller.configure(owner, selection, picker)
	_expect(configure_result.ok, "HighlightController should configure with buildings, selection, and picking")
	_expect(controller.has_method("set_highlight_input"), "HighlightController should expose set_highlight_input")
	_expect(controller.has_method("get_resolved_highlight_state"), "HighlightController should expose get_resolved_highlight_state")
	_expect(controller.get_resolved_highlight_state(building) == &"default", "resolver should return default when no flags are active")
	_expect(building.visual.fill_color == building.visual.default_fill_color, "default state should use the building default fill")

	_expect(controller.set_highlight_input(building, &"nearby", true).ok, "nearby input should be accepted")
	_expect(controller.get_resolved_highlight_state(building) == &"nearby", "nearby should resolve when it is the only active flag")

	_expect(controller.set_highlight_input(building, &"interactable", true).ok, "interactable input should be accepted")
	_expect(controller.get_resolved_highlight_state(building) == &"interactable", "interactable should override nearby")

	_expect(controller.set_highlight_input(building, &"hovered", true).ok, "hovered input should be accepted")
	_expect(controller.get_resolved_highlight_state(building) == &"hovered", "hovered should override interactable")

	_expect(controller.set_highlight_input(building, &"selected", true).ok, "selected input should be accepted")
	_expect(controller.get_resolved_highlight_state(building) == &"selected", "selected should override hovered")

	_expect(controller.set_highlight_input(building, &"debug_override", true).ok, "debug override input should be accepted")
	_expect(controller.get_resolved_highlight_state(building) == &"debug_override", "debug override should be highest priority")

	_expect(controller.set_highlight_input(building, &"debug_override", false).ok, "debug override input should clear")
	_expect(controller.get_resolved_highlight_state(building) == &"selected", "selected should return after debug override clears")

	for input_flag in [&"selected", &"hovered", &"interactable", &"nearby"]:
		_expect(controller.set_highlight_input(building, input_flag, false).ok, "%s input should clear" % input_flag)
	_expect(controller.get_resolved_highlight_state(building) == &"default", "state should return to default after all flags clear")
	_expect(building.visual.fill_color == building.visual.default_fill_color, "visual should return to default fill after all flags clear")

	controller.queue_free()
	owner.queue_free()
	selection.queue_free()
	picker.queue_free()
	await process_frame


func _verify_selection_and_hover_wiring() -> void:
	var owner := Node.new()
	var selection := SelectionControllerScript.new()
	var picker := PickingControllerScript.new()
	var selected := MockBuildingEntity.new("building.selected", "Selected")
	var hovered := MockBuildingEntity.new("building.hovered", "Hovered")
	get_root().add_child(owner)
	get_root().add_child(selection)
	get_root().add_child(picker)
	owner.add_child(selected)
	owner.add_child(hovered)
	await process_frame

	_expect(picker.configure(owner).ok, "picking controller should configure for wiring fixture")
	var controller := HighlightControllerScript.new()
	get_root().add_child(controller)
	_expect(controller.configure(owner, selection, picker).ok, "HighlightController should configure for wiring fixture")

	selection.apply_picked_target(selected)
	_expect(controller.get_resolved_highlight_state(selected) == &"selected", "selected signal should set selected highlight input")
	_expect(selected.visual.fill_color != selected.visual.default_fill_color, "selected visual should change from default")

	picker.update_hover_from_result(_picking_result(hovered))
	_expect(controller.get_resolved_highlight_state(selected) == &"selected", "selected building should keep selected encoding while another building is hovered")
	_expect(controller.get_resolved_highlight_state(hovered) == &"hovered", "hover signal should set hovered highlight input")
	_expect(hovered.visual.fill_color != hovered.visual.default_fill_color, "hovered visual should change from default")

	selection.apply_picked_target(null)
	_expect(controller.get_resolved_highlight_state(selected) == &"default", "clearing selection should clear selected input")
	_expect(selected.visual.fill_color == selected.visual.default_fill_color, "cleared selected building should return to default visual")

	picker.update_hover_from_result({"has_target": false})
	_expect(controller.get_resolved_highlight_state(hovered) == &"default", "clearing hover should clear hovered input")
	_expect(hovered.visual.fill_color == hovered.visual.default_fill_color, "cleared hovered building should return to default visual")

	controller.queue_free()
	owner.queue_free()
	selection.queue_free()
	picker.queue_free()
	await process_frame


func _verify_missing_visual_diagnostic() -> void:
	var owner := Node.new()
	var selection := SelectionControllerScript.new()
	var picker := PickingControllerScript.new()
	var missing_visual := MissingVisualBuildingEntity.new("building.missing")
	get_root().add_child(owner)
	get_root().add_child(selection)
	get_root().add_child(picker)
	owner.add_child(missing_visual)
	await process_frame

	_expect(picker.configure(owner).ok, "picking controller should configure for missing visual fixture")
	var controller := HighlightControllerScript.new()
	get_root().add_child(controller)
	var configure_result: Dictionary = controller.configure(owner, selection, picker)
	_expect(configure_result.ok, "missing visual diagnostics should not prevent controller configuration")
	var set_result: Dictionary = controller.set_highlight_input(missing_visual, &"selected", true)
	_expect(not set_result.ok, "setting highlight on missing visual target should fail")
	var diagnostics: Array[String] = controller.get_diagnostics()
	_expect(not diagnostics.is_empty(), "missing visual target should record a diagnostic")
	_expect(diagnostics[0].contains("building.missing"), "missing visual diagnostic should name the building")

	controller.queue_free()
	owner.queue_free()
	selection.queue_free()
	picker.queue_free()
	await process_frame


func _verify_main_scene_integration() -> void:
	var scene := MainScene.instantiate()
	get_root().add_child(scene)
	await process_frame
	await physics_frame

	_expect(scene.has_node("World/HighlightController"), "startup scene should contain World/HighlightController")
	_expect(scene.has_node("World/SelectionController"), "startup scene should contain World/SelectionController")
	_expect(scene.has_node("World/PickingController"), "startup scene should contain World/PickingController")
	_expect(scene.has_node("World/Buildings"), "startup scene should contain World/Buildings")
	if not scene.has_node("World/HighlightController") or not scene.has_node("World/Buildings"):
		scene.queue_free()
		await process_frame
		return

	var controller := scene.get_node("World/HighlightController")
	_expect(controller.has_method("set_highlight_input"), "startup HighlightController should expose set_highlight_input")
	_expect(controller.has_method("get_resolved_highlight_state"), "startup HighlightController should expose get_resolved_highlight_state")

	var buildings := scene.get_node("World/Buildings")
	var entities: Array[Node] = buildings.call("get_building_entities")
	_expect(not entities.is_empty(), "startup scene should create generated buildings for highlight validation")
	if entities.is_empty():
		scene.queue_free()
		await process_frame
		return

	var target := entities[0]
	var highlightable := target.get_node_or_null("HighlightableComponent")
	_expect(highlightable != null, "generated building should expose HighlightableComponent")

	_expect(controller.set_highlight_input(target, &"debug_override", true).ok, "startup controller should set debug_override directly")
	_expect(controller.get_resolved_highlight_state(target) == &"debug_override", "startup controller should resolve direct debug_override input")
	_expect(controller.set_highlight_input(target, &"debug_override", false).ok, "startup controller should clear debug_override directly")
	_expect(controller.get_resolved_highlight_state(target) == &"default", "startup controller should return target to default")

	scene.queue_free()
	await process_frame
	await process_frame


func _picking_result(target: Node) -> Dictionary:
	var identity := target.get_node_or_null("IdentityComponent")
	var pickable := target.get_node_or_null("PickableComponent")
	var selectable := target.get_node_or_null("SelectableComponent")
	var interactable := target.get_node_or_null("InteractableComponent")
	return {
		"has_target": true,
		"target": target,
		"entity_id": identity.call("get_entity_id"),
		"entity_type": identity.call("get_entity_type"),
		"display_name": identity.call("get_display_name"),
		"selectable": selectable.call("is_selectable"),
		"interactable": interactable.call("is_interactable"),
		"world_rect": pickable.call("get_world_rect"),
	}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


class MockVisual:
	extends Node2D

	var default_fill_color := Color(0.20, 0.30, 0.40, 1.0)
	var fill_color := default_fill_color

	func set_highlight_color(fill: Color, _outline: Color, _outline_width: float) -> void:
		fill_color = fill

	func reset_highlight() -> void:
		fill_color = default_fill_color


class MockBuildingEntity:
	extends Node

	var visual := MockVisual.new()
	var _entity_id: String
	var _display_name: String

	func _init(entity_id: String, display_name: String) -> void:
		_entity_id = entity_id
		_display_name = display_name
		add_child(visual)
		var identity := IdentityComponentScript.new()
		identity.name = "IdentityComponent"
		add_child(identity)
		identity.configure(_entity_id, "building", _display_name)
		var pickable := PickableComponentScript.new()
		pickable.name = "PickableComponent"
		add_child(pickable)
		pickable.configure(Rect2(Vector2.ZERO, Vector2(20, 20)))
		var selectable_component := SelectableComponentScript.new()
		selectable_component.name = "SelectableComponent"
		add_child(selectable_component)
		selectable_component.configure(true)
		var highlightable := HighlightableComponentScript.new()
		highlightable.name = "HighlightableComponent"
		add_child(highlightable)
		highlightable.configure(visual)
		var interactable_component := InteractableComponentScript.new()
		interactable_component.name = "InteractableComponent"
		add_child(interactable_component)
		interactable_component.configure(true)


class MissingVisualBuildingEntity:
	extends Node

	var _entity_id: String

	func _init(entity_id: String) -> void:
		_entity_id = entity_id
		var identity := IdentityComponentScript.new()
		identity.name = "IdentityComponent"
		add_child(identity)
		identity.configure(_entity_id, "building", "Missing Visual")
		var pickable := PickableComponentScript.new()
		pickable.name = "PickableComponent"
		add_child(pickable)
		pickable.configure(Rect2(Vector2.ZERO, Vector2(20, 20)))
		var selectable_component := SelectableComponentScript.new()
		selectable_component.name = "SelectableComponent"
		add_child(selectable_component)
		selectable_component.configure(true)
		var interactable_component := InteractableComponentScript.new()
		interactable_component.name = "InteractableComponent"
		add_child(interactable_component)
		interactable_component.configure(true)
