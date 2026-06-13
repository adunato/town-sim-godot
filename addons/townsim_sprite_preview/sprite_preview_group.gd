class_name SpritePreviewGroup
extends RefCounted

var action_name: String = ""
var angle_label: String = ""
var angle_degrees: float = 0.0
var variant: String = ""
var atlas_path: String = ""
var animation_name: String = ""
var frames: Array = []
var sprite_frames: SpriteFrames


func _init(
	group_action_name: String,
	group_angle_label: String,
	group_angle_degrees: float,
	group_variant: String,
	group_atlas_path: String
) -> void:
	action_name = group_action_name
	angle_label = group_angle_label
	angle_degrees = group_angle_degrees
	variant = group_variant
	atlas_path = group_atlas_path
	animation_name = _build_animation_name()
	sprite_frames = SpriteFrames.new()
	sprite_frames.remove_animation(&"default")
	sprite_frames.add_animation(StringName(animation_name))
	sprite_frames.set_animation_loop(StringName(animation_name), true)


func add_frame(frame: Variant) -> void:
	frames.append(frame)
	var duration_seconds := maxf(float(frame.duration_ms) / 1000.0, 0.001)
	sprite_frames.add_frame(StringName(animation_name), frame.texture, duration_seconds)


func _build_animation_name() -> String:
	return "%s__%s__%s" % [action_name, variant, angle_label]
