@tool
extends EditorPlugin

const SpritePreviewDock := preload("res://addons/townsim_sprite_preview/sprite_preview_dock.gd")

var _dock: Control
var _bottom_button: Button


func _enter_tree() -> void:
	_dock = SpritePreviewDock.new()
	_dock.name = "TownSim Sprite Preview"
	_bottom_button = add_control_to_bottom_panel(_dock, "TownSim Sprite Preview")
	add_tool_menu_item("TownSim Sprite Preview", _show_sprite_preview)
	make_bottom_panel_item_visible(_dock)


func _exit_tree() -> void:
	remove_tool_menu_item("TownSim Sprite Preview")
	if _dock != null:
		remove_control_from_bottom_panel(_dock)
		_dock.queue_free()
		_dock = null
	_bottom_button = null


func _show_sprite_preview() -> void:
	if _dock != null:
		make_bottom_panel_item_visible(_dock)
