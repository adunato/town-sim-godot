class_name HighlightController
extends Node

const CapabilityResolverScript := preload("res://scripts/entities/capability_resolver.gd")

const INPUT_SELECTED := &"selected"
const INPUT_HOVERED := &"hovered"
const INPUT_INTERACTABLE := &"interactable"
const INPUT_NEARBY := &"nearby"
const INPUT_DEBUG_OVERRIDE := &"debug_override"

const STATE_DEFAULT := &"default"
const STATE_NEARBY := &"nearby"
const STATE_INTERACTABLE := &"interactable"
const STATE_HOVERED := &"hovered"
const STATE_SELECTED := &"selected"
const STATE_DEBUG_OVERRIDE := &"debug_override"

const INPUT_FLAGS: Array[StringName] = [
	INPUT_SELECTED,
	INPUT_HOVERED,
	INPUT_INTERACTABLE,
	INPUT_NEARBY,
	INPUT_DEBUG_OVERRIDE,
]

const PRIORITY_ORDER: Array[StringName] = [
	INPUT_DEBUG_OVERRIDE,
	INPUT_SELECTED,
	INPUT_HOVERED,
	INPUT_INTERACTABLE,
	INPUT_NEARBY,
]

const STATE_COLOURS := {
	STATE_NEARBY: {
		"fill": Color(0.36, 0.70, 0.52, 1.0),
		"outline": Color(0.09, 0.35, 0.22, 1.0),
		"outline_width": 3.0,
	},
	STATE_INTERACTABLE: {
		"fill": Color(0.93, 0.79, 0.30, 1.0),
		"outline": Color(0.42, 0.27, 0.04, 1.0),
		"outline_width": 3.0,
	},
	STATE_HOVERED: {
		"fill": Color(0.44, 0.72, 0.96, 1.0),
		"outline": Color(0.05, 0.25, 0.48, 1.0),
		"outline_width": 4.0,
	},
	STATE_SELECTED: {
		"fill": Color(0.95, 0.62, 0.28, 1.0),
		"outline": Color(0.45, 0.13, 0.02, 1.0),
		"outline_width": 5.0,
	},
	STATE_DEBUG_OVERRIDE: {
		"fill": Color(0.96, 0.35, 0.72, 1.0),
		"outline": Color(0.35, 0.02, 0.20, 1.0),
		"outline_width": 5.0,
	},
}

var _buildings_owner: Node
var _selection_controller: Node
var _picking_controller: Node
var _diagnostics: Array[String] = []
var _selected_building: Node
var _hovered_building: Node


func configure(buildings_owner: Node, selection_controller: Node, picking_controller: Node) -> Dictionary:
	if buildings_owner == null:
		return _failure("HighlightController requires a buildings owner.")
	if selection_controller == null:
		return _failure("HighlightController requires a selection controller.")
	if picking_controller == null:
		return _failure("HighlightController requires a picking controller.")
	_buildings_owner = buildings_owner
	_selection_controller = selection_controller
	_picking_controller = picking_controller
	_diagnostics.clear()
	_register_current_buildings()
	_connect_controller_signals()
	_apply_selection_target(_selection_controller.call("get_selected_target") as Node)
	_apply_hovered_target(_picking_controller.call("get_hovered_target") as Node)
	return _success()


func set_highlight_input(building: Node, input_flag: StringName, enabled: bool) -> Dictionary:
	if building == null:
		return _failure("HighlightController cannot set '%s' because building is null." % input_flag)
	if not INPUT_FLAGS.has(input_flag):
		return _failure("HighlightController input flag '%s' is not approved." % input_flag)

	var register_result := _ensure_registered(building)
	if not register_result.ok:
		return register_result

	var highlightable := CapabilityResolverScript.get_highlightable(building)
	return highlightable.call("set_highlight_input", input_flag, enabled)


func get_resolved_highlight_state(building: Node) -> StringName:
	if building == null:
		return STATE_DEFAULT
	var highlightable := CapabilityResolverScript.get_highlightable(building)
	if highlightable == null:
		return STATE_DEFAULT
	return highlightable.call("get_resolved_highlight_state")


func get_diagnostics() -> Array[String]:
	return _diagnostics.duplicate()


func resolve_highlight_state(input_state: Dictionary) -> StringName:
	for input_flag in PRIORITY_ORDER:
		if bool(input_state.get(input_flag, false)):
			return input_flag
	return STATE_DEFAULT


func _register_current_buildings() -> void:
	for building in _get_building_entities():
		_ensure_registered(building)


func _ensure_registered(building: Node) -> Dictionary:
	if building == null:
		return _failure("HighlightController cannot register a null building.")
	var highlightable := CapabilityResolverScript.get_highlightable(building)
	if highlightable == null:
		return _diagnose("HighlightController target '%s' has no HighlightableComponent." % _describe_building(building))
	if not building.tree_exiting.is_connected(_on_registered_building_tree_exiting.bind(building)):
		building.tree_exiting.connect(_on_registered_building_tree_exiting.bind(building))
	return _success()


func _connect_controller_signals() -> void:
	if _selection_controller.has_signal("selection_changed") \
			and not _selection_controller.selection_changed.is_connected(_on_selection_changed):
		_selection_controller.selection_changed.connect(_on_selection_changed)
	if _picking_controller.has_signal("hover_changed") \
			and not _picking_controller.hover_changed.is_connected(_on_hover_changed):
		_picking_controller.hover_changed.connect(_on_hover_changed)


func _on_selection_changed(_snapshot: Dictionary) -> void:
	_apply_selection_target(_selection_controller.call("get_selected_target") as Node)


func _on_hover_changed(_snapshot: Dictionary) -> void:
	_apply_hovered_target(_picking_controller.call("get_hovered_target") as Node)


func _apply_selection_target(next_selected: Node) -> void:
	if next_selected == _selected_building:
		return
	if _selected_building != null and is_instance_valid(_selected_building):
		set_highlight_input(_selected_building, INPUT_SELECTED, false)
	_selected_building = next_selected
	if _selected_building != null:
		set_highlight_input(_selected_building, INPUT_SELECTED, true)


func _apply_hovered_target(next_hovered: Node) -> void:
	if next_hovered == _hovered_building:
		return
	if _hovered_building != null and is_instance_valid(_hovered_building):
		set_highlight_input(_hovered_building, INPUT_HOVERED, false)
	_hovered_building = next_hovered
	if _hovered_building != null:
		set_highlight_input(_hovered_building, INPUT_HOVERED, true)


func _get_building_entities() -> Array[Node]:
	if _buildings_owner == null:
		return []
	if _buildings_owner.has_method("get_building_entities"):
		var owner_entities: Array[Node] = []
		for entity in _buildings_owner.call("get_building_entities"):
			if entity is Node:
				owner_entities.append(entity)
		return owner_entities

	var child_entities: Array[Node] = []
	for child in _buildings_owner.get_children():
		if child is Node:
			child_entities.append(child)
	return child_entities


func _on_registered_building_tree_exiting(building: Node) -> void:
	if building == _selected_building:
		_selected_building = null
	if building == _hovered_building:
		_hovered_building = null


func _describe_building(building: Node) -> String:
	if building == null:
		return "<null>"
	var identity := CapabilityResolverScript.get_identity(building)
	if identity != null:
		var entity_id := String(identity.call("get_entity_id"))
		if not entity_id.is_empty():
			return entity_id
	return building.name


func _diagnose(message: String) -> Dictionary:
	if _diagnostics.has(message):
		return _failure(message)
	_diagnostics.append(message)
	printerr(message)
	return _failure(message)


func _success(extra: Dictionary = {}) -> Dictionary:
	var result := {"ok": true}
	result.merge(extra, true)
	return result


func _failure(message: String, extra: Dictionary = {}) -> Dictionary:
	var result := {
		"ok": false,
		"error": message,
	}
	result.merge(extra, true)
	return result
