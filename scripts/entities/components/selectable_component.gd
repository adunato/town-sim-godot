class_name SelectableComponent
extends Node

var _selectable := false
var _selected := false


func configure(selectable: bool) -> Dictionary:
	_selectable = selectable
	_selected = false
	return _success()


func is_selectable() -> bool:
	return _selectable


func can_select() -> bool:
	return _selectable


func select() -> Dictionary:
	if not _selectable:
		_selected = false
		return _success({"selected": false})
	_selected = true
	return _success({"selected": true})


func deselect() -> Dictionary:
	_selected = false
	return _success({"selected": false})


func is_selected() -> bool:
	return _selected


func _success(extra: Dictionary = {}) -> Dictionary:
	var result := {"ok": true}
	result.merge(extra, true)
	return result
