class_name InteractionController
extends Node

signal interaction_attempted(result: Dictionary)

const OUTCOME_SUCCESS := &"success"
const OUTCOME_NO_TARGET := &"no_target"
const OUTCOME_NOT_INTERACTABLE := &"not_interactable"
const OUTCOME_OUT_OF_RANGE := &"out_of_range"

var _picking_controller: Node
var _selection_controller: Node
var _proximity_controller: Node
var _highlight_controller: Node
var _last_interactable_target: Node


func configure(
	picking_controller: Node,
	selection_controller: Node,
	proximity_controller: Node,
	highlight_controller: Node = null
) -> Dictionary:
	if picking_controller == null:
		return _failure("InteractionController requires a picking controller.")
	if not picking_controller.has_method("get_hovered_target"):
		return _failure("InteractionController picking controller must expose get_hovered_target.")
	if selection_controller == null:
		return _failure("InteractionController requires a selection controller.")
	if not selection_controller.has_method("get_selected_target"):
		return _failure("InteractionController selection controller must expose get_selected_target.")
	if proximity_controller == null:
		return _failure("InteractionController requires a proximity controller.")
	if not proximity_controller.has_method("is_entity_nearby"):
		return _failure("InteractionController proximity controller must expose is_entity_nearby.")
	if highlight_controller != null and not highlight_controller.has_method("set_highlight_input"):
		return _failure("InteractionController highlight controller must expose set_highlight_input.")

	_picking_controller = picking_controller
	_selection_controller = selection_controller
	_proximity_controller = proximity_controller
	_highlight_controller = highlight_controller
	_clear_last_interactable_highlight()
	return _success()


func attempt_interaction(cursor_target: Variant = null) -> Dictionary:
	var target := resolve_target(cursor_target)
	if target == null:
		return _emit_result(_build_result(OUTCOME_NO_TARGET, null, "No interaction target."))

	var interactable := target.get_node_or_null("InteractableComponent")
	if interactable == null or not bool(interactable.call("is_interactable")):
		_set_interactable_highlight(target, false)
		return _emit_result(_build_result(
			OUTCOME_NOT_INTERACTABLE,
			target,
			"%s is not interactable." % _get_display_name(target)
		))

	if _proximity_controller == null or not bool(_proximity_controller.call("is_entity_nearby", target)):
		_set_interactable_highlight(target, false)
		return _emit_result(_build_result(
			OUTCOME_OUT_OF_RANGE,
			target,
			"%s is out of range." % _get_display_name(target)
		))

	_set_interactable_highlight(target, true)
	return _emit_result(_build_result(
		OUTCOME_SUCCESS,
		target,
		"Interacted with %s." % _get_display_name(target),
		true
	))


func resolve_target(cursor_target: Variant = null) -> Node:
	if cursor_target is Node:
		return cursor_target as Node
	if _picking_controller != null:
		var hovered: Variant = _picking_controller.call("get_hovered_target")
		if hovered is Node:
			return hovered as Node
	if _selection_controller != null:
		var selected: Variant = _selection_controller.call("get_selected_target")
		if selected is Node:
			return selected as Node
	return null


func get_last_interactable_target() -> Node:
	if _last_interactable_target != null and is_instance_valid(_last_interactable_target):
		return _last_interactable_target
	return null


func _set_interactable_highlight(target: Node, enabled: bool) -> void:
	if _highlight_controller == null:
		return
	if _last_interactable_target != null \
			and is_instance_valid(_last_interactable_target) \
			and _last_interactable_target != target:
		_highlight_controller.call("set_highlight_input", _last_interactable_target, &"interactable", false)
	_last_interactable_target = target if enabled else null
	_highlight_controller.call("set_highlight_input", target, &"interactable", enabled)


func _clear_last_interactable_highlight() -> void:
	if _highlight_controller != null and _last_interactable_target != null and is_instance_valid(_last_interactable_target):
		_highlight_controller.call("set_highlight_input", _last_interactable_target, &"interactable", false)
	_last_interactable_target = null


func _build_result(outcome: StringName, target: Node, message: String, ok := false) -> Dictionary:
	var result := {
		"ok": ok,
		"outcome": outcome,
		"has_target": target != null,
		"target": target,
		"display_name": _get_display_name(target),
		"message": message,
	}
	if target != null:
		result["entity_id"] = _get_entity_id(target)
	return result


func _emit_result(result: Dictionary) -> Dictionary:
	interaction_attempted.emit(result.duplicate(true))
	print(result.message)
	return result


func _get_entity_id(target: Node) -> String:
	var identity := target.get_node_or_null("IdentityComponent")
	return String(identity.call("get_entity_id")) if identity != null else ""


func _get_display_name(target: Node) -> String:
	if target == null:
		return ""
	var identity := target.get_node_or_null("IdentityComponent")
	if identity != null:
		var display_name := String(identity.call("get_display_name"))
		if not display_name.is_empty():
			return display_name
	return target.name


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
