class_name SelectionController
extends Node

signal selection_changed(snapshot: Dictionary)

const EMPTY_SELECTION_SNAPSHOT := {
	"has_target": false,
}

var _selected_target: Node
var _selected_component: Node
var _selection_snapshot: Dictionary = EMPTY_SELECTION_SNAPSHOT.duplicate(true)


func apply_picked_target(picked_target: Variant) -> Dictionary:
	if picked_target == null:
		clear_selection()
		return _success({"selected": false})
	if not picked_target is Node:
		clear_selection()
		return _failure("Picked target must be a Node or null.")

	var target := picked_target as Node
	if not _is_selectable_target(target):
		clear_selection()
		return _success({"selected": false})

	return select_target(target)


func select_target(target: Node) -> Dictionary:
	if target == null:
		clear_selection()
		return _failure("Selected target cannot be null.")
	if not _has_required_entity_contract(target):
		clear_selection()
		return _failure("Selected target does not expose the required entity contract.")
	if not _target_reports_selectable(target):
		clear_selection()
		return _success({"selected": false})
	if target == _selected_target:
		return _success({"selected": true, "unchanged": true})

	_disconnect_selected_target()
	if _selected_component != null:
		_selected_component.call("deselect")
	_selected_target = target
	_selected_component = target.get_node_or_null("SelectableComponent")
	_selected_component.call("select")
	if not _selected_target.tree_exiting.is_connected(_on_selected_target_tree_exiting):
		_selected_target.tree_exiting.connect(_on_selected_target_tree_exiting)
	_update_snapshot_and_emit()
	return _success({"selected": true})


func clear_selection() -> bool:
	if _selected_target == null and not bool(_selection_snapshot.get("has_target", false)):
		return false

	_disconnect_selected_target()
	if _selected_component != null:
		_selected_component.call("deselect")
	_selected_target = null
	_selected_component = null
	_update_snapshot_and_emit()
	return true


func refresh_selected_target() -> void:
	if _selected_target == null:
		return
	if not _selected_target.is_inside_tree() or not _is_selectable_target(_selected_target):
		clear_selection()


func get_selected_target() -> Node:
	refresh_selected_target()
	return _selected_target


func get_selection_snapshot() -> Dictionary:
	refresh_selected_target()
	return _selection_snapshot.duplicate(true)


func _on_selected_target_tree_exiting() -> void:
	clear_selection()


func _update_snapshot_and_emit() -> void:
	_selection_snapshot = _build_selection_snapshot(_selected_target)
	selection_changed.emit(_selection_snapshot.duplicate(true))
	if bool(_selection_snapshot.get("has_target", false)):
		print("Selection changed: %s | %s | %s" % [
			_selection_snapshot.entity_id,
			_selection_snapshot.display_name,
			_selection_snapshot.entity_type,
		])
	else:
		print("Selection cleared")


func _build_selection_snapshot(target: Node) -> Dictionary:
	if target == null:
		return EMPTY_SELECTION_SNAPSHOT.duplicate(true)

	return {
		"has_target": true,
		"entity_id": _get_entity_id(target),
		"entity_type": _get_entity_type(target),
		"display_name": _get_display_name(target),
		"selectable": _target_reports_selectable(target),
		"interactable": _target_reports_interactable(target),
	}


func _is_selectable_target(target: Node) -> bool:
	return _has_required_entity_contract(target) and _target_reports_selectable(target)


func _has_required_entity_contract(target: Node) -> bool:
	return target != null \
		and target.get_node_or_null("IdentityComponent") != null \
		and target.get_node_or_null("SelectableComponent") != null


func _target_reports_selectable(target: Node) -> bool:
	var selectable := target.get_node_or_null("SelectableComponent")
	return selectable != null and bool(selectable.call("can_select"))


func _target_reports_interactable(target: Node) -> bool:
	var interactable := target.get_node_or_null("InteractableComponent")
	return interactable != null and bool(interactable.call("is_interactable"))


func _get_entity_id(target: Node) -> String:
	var identity := target.get_node_or_null("IdentityComponent")
	return String(identity.call("get_entity_id")) if identity != null else ""


func _get_entity_type(target: Node) -> String:
	var identity := target.get_node_or_null("IdentityComponent")
	return String(identity.call("get_entity_type")) if identity != null else ""


func _get_display_name(target: Node) -> String:
	var identity := target.get_node_or_null("IdentityComponent")
	return String(identity.call("get_display_name")) if identity != null else ""


func _disconnect_selected_target() -> void:
	if _selected_target != null and is_instance_valid(_selected_target):
		if _selected_target.tree_exiting.is_connected(_on_selected_target_tree_exiting):
			_selected_target.tree_exiting.disconnect(_on_selected_target_tree_exiting)


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
