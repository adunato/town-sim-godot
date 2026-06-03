class_name InteractableComponent
extends Node

var _interactable := false


func configure(interactable: bool) -> Dictionary:
	_interactable = interactable
	return _success()


func is_interactable() -> bool:
	return _interactable


func _success(extra: Dictionary = {}) -> Dictionary:
	var result := {"ok": true}
	result.merge(extra, true)
	return result
