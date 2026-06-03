class_name HighlightableComponent
extends Node

const INPUT_SELECTED := &"selected"
const INPUT_HOVERED := &"hovered"
const INPUT_INTERACTABLE := &"interactable"
const INPUT_NEARBY := &"nearby"
const INPUT_DEBUG_OVERRIDE := &"debug_override"

const STATE_DEFAULT := &"default"
const STATE_NEARBY := &"nearby"
const STATE_INTERACTABLE := &"interactable"
const STATE_HOVERED := &"hovered"
const STATE_SELECTED := &"selected"
const STATE_DEBUG_OVERRIDE := &"debug_override"

const INPUT_FLAGS: Array[StringName] = [
	INPUT_SELECTED,
	INPUT_HOVERED,
	INPUT_INTERACTABLE,
	INPUT_NEARBY,
	INPUT_DEBUG_OVERRIDE,
]

const PRIORITY_ORDER: Array[StringName] = [
	INPUT_DEBUG_OVERRIDE,
	INPUT_SELECTED,
	INPUT_HOVERED,
	INPUT_INTERACTABLE,
	INPUT_NEARBY,
]

const STATE_COLOURS := {
	STATE_NEARBY: {
		"fill": Color(0.36, 0.70, 0.52, 1.0),
		"outline": Color(0.09, 0.35, 0.22, 1.0),
		"outline_width": 3.0,
	},
	STATE_INTERACTABLE: {
		"fill": Color(0.93, 0.79, 0.30, 1.0),
		"outline": Color(0.42, 0.27, 0.04, 1.0),
		"outline_width": 3.0,
	},
	STATE_HOVERED: {
		"fill": Color(0.44, 0.72, 0.96, 1.0),
		"outline": Color(0.05, 0.25, 0.48, 1.0),
		"outline_width": 4.0,
	},
	STATE_SELECTED: {
		"fill": Color(0.95, 0.62, 0.28, 1.0),
		"outline": Color(0.45, 0.13, 0.02, 1.0),
		"outline_width": 5.0,
	},
	STATE_DEBUG_OVERRIDE: {
		"fill": Color(0.96, 0.35, 0.72, 1.0),
		"outline": Color(0.35, 0.02, 0.20, 1.0),
		"outline_width": 5.0,
	},
}

var _visual_target: Node
var _input_state: Dictionary = {}
var _resolved_state := STATE_DEFAULT


func configure(visual_target: Node) -> Dictionary:
	if visual_target == null:
		return _failure("HighlightableComponent requires a visual target.")
	if not visual_target.has_method("set_highlight_color"):
		return _failure("HighlightableComponent visual target must expose set_highlight_color.")
	if not visual_target.has_method("reset_highlight"):
		return _failure("HighlightableComponent visual target must expose reset_highlight.")
	_visual_target = visual_target
	_input_state.clear()
	return _apply_resolved_state()


func set_highlight_input(input_flag: StringName, enabled: bool) -> Dictionary:
	if not INPUT_FLAGS.has(input_flag):
		return _failure("HighlightableComponent input flag '%s' is not approved." % input_flag)
	if enabled:
		_input_state[input_flag] = true
	else:
		_input_state.erase(input_flag)
	return _apply_resolved_state()


func get_resolved_highlight_state() -> StringName:
	return _resolved_state


func get_highlight_inputs() -> Dictionary:
	return _input_state.duplicate(true)


func resolve_highlight_state(input_state: Dictionary) -> StringName:
	for input_flag in PRIORITY_ORDER:
		if bool(input_state.get(input_flag, false)):
			return input_flag
	return STATE_DEFAULT


func _apply_resolved_state() -> Dictionary:
	_resolved_state = resolve_highlight_state(_input_state)
	if _visual_target == null:
		return _failure("HighlightableComponent has no visual target.")
	if _resolved_state == STATE_DEFAULT:
		_visual_target.call("reset_highlight")
		return _success({"resolved_state": _resolved_state})

	var colour_data: Dictionary = STATE_COLOURS[_resolved_state]
	_visual_target.call(
		"set_highlight_color",
		colour_data.fill,
		colour_data.outline,
		float(colour_data.outline_width)
	)
	return _success({"resolved_state": _resolved_state})


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
