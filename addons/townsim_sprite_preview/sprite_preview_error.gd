class_name SpritePreviewError
extends RefCounted

var path: String = ""
var field: String = ""
var message: String = ""


func _init(error_path: String = "", error_field: String = "", error_message: String = "") -> void:
	path = error_path
	field = error_field
	message = error_message


func describe() -> String:
	var parts: Array[String] = []
	if path != "":
		parts.append(path)
	if field != "":
		parts.append(field)
	parts.append(message)
	return " | ".join(parts)
