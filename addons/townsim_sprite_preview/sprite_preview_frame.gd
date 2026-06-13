class_name SpritePreviewFrame
extends RefCounted

var texture: AtlasTexture
var region: Rect2i
var duration_ms: int = 0
var source_blender_frame: int = -1
var action_name: String = ""
var angle_label: String = ""
var angle_degrees: float = 0.0
var variant: String = ""


func _init(
	frame_texture: AtlasTexture,
	frame_region: Rect2i,
	frame_duration_ms: int,
	frame_source_blender_frame: int,
	frame_action_name: String,
	frame_angle_label: String,
	frame_angle_degrees: float,
	frame_variant: String
) -> void:
	texture = frame_texture
	region = frame_region
	duration_ms = frame_duration_ms
	source_blender_frame = frame_source_blender_frame
	action_name = frame_action_name
	angle_label = frame_angle_label
	angle_degrees = frame_angle_degrees
	variant = frame_variant
