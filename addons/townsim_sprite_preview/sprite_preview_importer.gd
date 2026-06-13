class_name SpritePreviewImporter
extends RefCounted

const SpritePreviewErrorScript := preload("res://addons/townsim_sprite_preview/sprite_preview_error.gd")
const SpritePreviewFrameScript := preload("res://addons/townsim_sprite_preview/sprite_preview_frame.gd")
const SpritePreviewGroupScript := preload("res://addons/townsim_sprite_preview/sprite_preview_group.gd")
const SpritePreviewModelScript := preload("res://addons/townsim_sprite_preview/sprite_preview_model.gd")
const SUPPORTED_MANIFEST_SCHEMA := "townsim-depth-angle-atlas-v1"


func import_path(json_path: String) -> Variant:
	var model = SpritePreviewModelScript.new()
	model.source_path = ProjectSettings.globalize_path(json_path)
	var document := _load_json_document(model.source_path, model)
	if model.has_errors():
		return model
	if not document is Dictionary:
		model.add_error(SpritePreviewErrorScript.new(model.source_path, "", "Selected JSON root must be an object."))
		return model
	if document.has("schema_version"):
		_import_manifest(model.source_path, document, model)
	elif document.has("frames") and document.has("meta"):
		_import_metadata(model.source_path, document, model)
	else:
		model.add_error(SpritePreviewErrorScript.new(model.source_path, "", "Unsupported JSON shape. Expected TOOL-005 metadata, TOOL-008 variant metadata, or TOOL-008 variant manifest."))
	if model.groups.is_empty() and not model.has_errors():
		model.add_error(SpritePreviewErrorScript.new(model.source_path, "", "Import produced no preview animation groups."))
	return model


func _load_json_document(path: String, model: Variant) -> Variant:
	if not FileAccess.file_exists(path):
		model.add_error(SpritePreviewErrorScript.new(path, "", "JSON file does not exist."))
		return null
	var text := FileAccess.get_file_as_string(path)
	var parser := JSON.new()
	var error := parser.parse(text)
	if error != OK:
		model.add_error(SpritePreviewErrorScript.new(path, "json", "Invalid JSON: %s at line %d." % [parser.get_error_message(), parser.get_error_line()]))
		return null
	return parser.data


func _import_manifest(manifest_path: String, document: Dictionary, model: Variant) -> void:
	var schema_version := str(document.get("schema_version", ""))
	if schema_version != SUPPORTED_MANIFEST_SCHEMA:
		model.add_error(SpritePreviewErrorScript.new(manifest_path, "schema_version", "Unsupported manifest schema version '%s'." % schema_version))
		return
	var exported_atlases := document.get("exported_atlases")
	if not exported_atlases is Array:
		model.add_error(SpritePreviewErrorScript.new(manifest_path, "exported_atlases", "Manifest must contain an exported_atlases array."))
		return
	for index in range(exported_atlases.size()):
		var entry: Variant = exported_atlases[index]
		if not entry is Dictionary:
			model.add_error(SpritePreviewErrorScript.new(manifest_path, "exported_atlases[%d]" % index, "Manifest atlas entry must be an object."))
			continue
		var metadata_value := _first_string(entry, ["metadata_path", "atlas_metadata_path", "metadata", "json_path"])
		if metadata_value == "":
			model.add_error(SpritePreviewErrorScript.new(manifest_path, "exported_atlases[%d].metadata_path" % index, "Manifest atlas entry must identify a metadata JSON path."))
			continue
		var metadata_path := _resolve_path(manifest_path, metadata_value)
		var metadata_document := _load_json_document(metadata_path, model)
		if metadata_document is Dictionary:
			_import_metadata(metadata_path, metadata_document, model)


func _import_metadata(metadata_path: String, document: Dictionary, model: Variant) -> void:
	var frames := document.get("frames")
	var meta := document.get("meta")
	if not frames is Array:
		model.add_error(SpritePreviewErrorScript.new(metadata_path, "frames", "Metadata must contain a frames array."))
		return
	if not meta is Dictionary:
		model.add_error(SpritePreviewErrorScript.new(metadata_path, "meta", "Metadata must contain a meta object."))
		return
	if not meta.has("frameTags") or not meta["frameTags"] is Array:
		model.add_error(SpritePreviewErrorScript.new(metadata_path, "meta.frameTags", "Metadata must contain a meta.frameTags array."))
		return
	var townsim: Dictionary = meta.get("townsim", {})
	if not townsim is Dictionary:
		model.add_error(SpritePreviewErrorScript.new(metadata_path, "meta.townsim", "Metadata meta.townsim must be an object when present."))
		return
	var atlas_value := _metadata_atlas_path(meta, townsim)
	if atlas_value == "":
		model.add_error(SpritePreviewErrorScript.new(metadata_path, "meta.image", "Metadata must identify a companion PNG atlas path."))
		return
	var atlas_path := _resolve_path(metadata_path, atlas_value)
	var atlas_texture := _load_texture(atlas_path, model)
	if atlas_texture == null:
		return
	var atlas_size := atlas_texture.get_size()
	var variant := str(townsim.get("variant", "diffuse"))
	if variant == "":
		variant = "diffuse"
	var default_action := str(townsim.get("action", ""))
	var built_frames: Array = []
	for index in range(frames.size()):
		var frame := _build_frame(metadata_path, frames[index], index, atlas_texture, atlas_size, default_action, variant, model)
		if frame != null:
			built_frames.append(frame)
	if model.has_errors():
		return
	_build_groups_from_tags(metadata_path, meta["frameTags"], built_frames, default_action, variant, atlas_path, model)


func _build_frame(
	metadata_path: String,
	frame_record: Variant,
	index: int,
	atlas_texture: Texture2D,
	atlas_size: Vector2,
	default_action: String,
	default_variant: String,
	model: Variant
) -> Variant:
	if not frame_record is Dictionary:
		model.add_error(SpritePreviewErrorScript.new(metadata_path, "frames[%d]" % index, "Frame record must be an object."))
		return null
	var frame_rect_value: Variant = frame_record.get("frame")
	if not frame_rect_value is Dictionary:
		model.add_error(SpritePreviewErrorScript.new(metadata_path, "frames[%d].frame" % index, "Frame record must contain a frame rectangle object."))
		return null
	var rect := _parse_rect(metadata_path, "frames[%d].frame" % index, frame_rect_value, model)
	if rect.size.x <= 0 or rect.size.y <= 0:
		return null
	if rect.position.x + rect.size.x > int(atlas_size.x) or rect.position.y + rect.size.y > int(atlas_size.y):
		model.add_error(SpritePreviewErrorScript.new(metadata_path, "frames[%d].frame" % index, "Frame rectangle %s is outside atlas bounds %dx%d." % [str(rect), int(atlas_size.x), int(atlas_size.y)]))
		return null
	var frame_townsim: Dictionary = frame_record.get("townsim", {})
	if not frame_townsim is Dictionary:
		frame_townsim = {}
	var atlas_frame := AtlasTexture.new()
	atlas_frame.atlas = atlas_texture
	atlas_frame.region = Rect2(rect)
	var duration_ms := int(frame_record.get("duration", 0))
	if duration_ms <= 0:
		model.add_error(SpritePreviewErrorScript.new(metadata_path, "frames[%d].duration" % index, "Frame duration must be a positive integer."))
		return null
	var angle_label := str(frame_townsim.get("angle_label", frame_townsim.get("angle_degrees", "")))
	if angle_label == "":
		angle_label = "unknown"
	var angle_degrees := float(frame_townsim.get("angle_degrees", 0.0))
	var source_blender_frame := int(frame_townsim.get("source_blender_frame", -1))
	var action_name := str(frame_townsim.get("action", default_action))
	if action_name == "":
		action_name = "unknown_action"
	var variant := str(frame_townsim.get("variant", default_variant))
	if variant == "":
		variant = "diffuse"
	return SpritePreviewFrameScript.new(atlas_frame, rect, duration_ms, source_blender_frame, action_name, angle_label, angle_degrees, variant)


func _build_groups_from_tags(
	metadata_path: String,
	frame_tags: Array,
	frames: Array,
	default_action: String,
	default_variant: String,
	atlas_path: String,
	model: Variant
) -> void:
	for index in range(frame_tags.size()):
		var tag: Variant = frame_tags[index]
		if not tag is Dictionary:
			model.add_error(SpritePreviewErrorScript.new(metadata_path, "meta.frameTags[%d]" % index, "Frame tag must be an object."))
			continue
		for field in ["from", "to"]:
			if not tag.has(field):
				model.add_error(SpritePreviewErrorScript.new(metadata_path, "meta.frameTags[%d].%s" % [index, field], "Frame tag range field is required."))
				continue
		var from_index := int(tag.get("from", -1))
		var to_index := int(tag.get("to", -1))
		if from_index < 0 or to_index < from_index or to_index >= frames.size():
			model.add_error(SpritePreviewErrorScript.new(metadata_path, "meta.frameTags[%d]" % index, "Frame tag range %d-%d is outside the imported frame array." % [from_index, to_index]))
			continue
		var tag_townsim: Dictionary = tag.get("townsim", {})
		if not tag_townsim is Dictionary:
			tag_townsim = {}
		var first_frame: Variant = frames[from_index]
		var action_name := str(tag_townsim.get("action", first_frame.action_name if first_frame.action_name != "" else default_action))
		var variant := str(tag_townsim.get("variant", first_frame.variant if first_frame.variant != "" else default_variant))
		if variant == "":
			variant = "diffuse"
		var angle_label := str(tag_townsim.get("angle_label", first_frame.angle_label))
		if angle_label == "":
			angle_label = "unknown"
		var angle_degrees := float(tag_townsim.get("angle_degrees", first_frame.angle_degrees))
		var group = SpritePreviewGroupScript.new(action_name, angle_label, angle_degrees, variant, atlas_path)
		for frame_index in range(from_index, to_index + 1):
			group.add_frame(frames[frame_index])
		if group.frames.is_empty():
			model.add_error(SpritePreviewErrorScript.new(metadata_path, "meta.frameTags[%d]" % index, "Frame tag produced an empty animation group."))
		else:
			model.add_group(group)


func _parse_rect(metadata_path: String, field: String, value: Dictionary, model: Variant) -> Rect2i:
	for key in ["x", "y", "w", "h"]:
		if not value.has(key):
			model.add_error(SpritePreviewErrorScript.new(metadata_path, "%s.%s" % [field, key], "Frame rectangle field is required."))
			return Rect2i()
	var rect := Rect2i(int(value["x"]), int(value["y"]), int(value["w"]), int(value["h"]))
	if rect.position.x < 0 or rect.position.y < 0 or rect.size.x <= 0 or rect.size.y <= 0:
		model.add_error(SpritePreviewErrorScript.new(metadata_path, field, "Frame rectangle must have non-negative position and positive size."))
	return rect


func _metadata_atlas_path(meta: Dictionary, townsim: Dictionary) -> String:
	var townsim_path := _first_string(townsim, ["atlas_png_path", "png_path", "image", "sprite_sheet_png_path"])
	if townsim_path != "":
		return townsim_path
	return str(meta.get("image", ""))


func _load_texture(path: String, model: Variant) -> Texture2D:
	if not FileAccess.file_exists(path):
		model.add_error(SpritePreviewErrorScript.new(path, "", "Companion PNG atlas file does not exist."))
		return null
	var image := Image.new()
	var error := image.load(path)
	if error != OK:
		model.add_error(SpritePreviewErrorScript.new(path, "", "Failed to load companion PNG atlas. Godot error code: %d." % error))
		return null
	return ImageTexture.create_from_image(image)


func _resolve_path(base_json_path: String, value: String) -> String:
	if value == "":
		return ""
	if value.is_absolute_path():
		return ProjectSettings.globalize_path(value)
	var base_dir := base_json_path.get_base_dir()
	return ProjectSettings.globalize_path(base_dir.path_join(value))


func _first_string(source: Dictionary, keys: Array[String]) -> String:
	for key in keys:
		if source.has(key) and str(source[key]) != "":
			return str(source[key])
	return ""
