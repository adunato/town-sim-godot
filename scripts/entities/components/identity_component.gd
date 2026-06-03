class_name EntityIdentityComponent
extends Node

var _entity_id := ""
var _entity_type := ""
var _display_name := ""


func configure(entity_id: String, entity_type: String, display_name: String) -> Dictionary:
	if entity_id.is_empty():
		return _failure("IdentityComponent requires a non-empty entity_id.")
	if entity_type.is_empty():
		return _failure("IdentityComponent requires a non-empty entity_type.")
	_entity_id = entity_id
	_entity_type = entity_type
	_display_name = display_name
	return _success()


func get_entity_id() -> String:
	return _entity_id


func get_entity_type() -> String:
	return _entity_type


func get_display_name() -> String:
	return _display_name


func get_snapshot() -> Dictionary:
	return {
		"entity_id": _entity_id,
		"entity_type": _entity_type,
		"display_name": _display_name,
	}


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
