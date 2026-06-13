class_name SpritePreviewModel
extends RefCounted

var source_path: String = ""
var groups: Array = []
var errors: Array = []


func has_errors() -> bool:
	return not errors.is_empty()


func add_error(error: Variant) -> void:
	errors.append(error)


func add_group(group: Variant) -> void:
	groups.append(group)


func get_actions() -> PackedStringArray:
	var values: PackedStringArray = []
	for group in groups:
		if not values.has(group.action_name):
			values.append(group.action_name)
	return values


func get_variants(action_name: String) -> PackedStringArray:
	var values: PackedStringArray = []
	for group in groups:
		if group.action_name == action_name and not values.has(group.variant):
			values.append(group.variant)
	return values


func get_angles(action_name: String, variant: String) -> PackedStringArray:
	var values: PackedStringArray = []
	for group in groups:
		if group.action_name == action_name and group.variant == variant and not values.has(group.angle_label):
			values.append(group.angle_label)
	return values


func find_group(action_name: String, variant: String, angle_label: String) -> Variant:
	for group in groups:
		if group.action_name == action_name and group.variant == variant and group.angle_label == angle_label:
			return group
	return null
