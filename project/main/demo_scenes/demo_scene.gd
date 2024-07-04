class_name DemoScene
extends Resource

enum DemoType {
	NONE,
	UNSIGNED_DISTANCE_FIELD,
}

enum SceneType {
	NONE,
	BASE,
	COMPOSITOR_EFFECT,
	NODE,
}

var _scene_type_path_properties := {
	SceneType.BASE : "base_scene_path",
	SceneType.COMPOSITOR_EFFECT : "compositor_effect_scene_path",
	SceneType.NODE : "node_scene_path",
}

@export var demo_type : DemoType

@export_file var base_scene_path : String
@export_file var compositor_effect_scene_path : String
@export_file var node_scene_path : String

@export var display_name : String
@export_multiline var description : String

@export_multiline var outline_palette : String
@export_multiline var background_palette : String

@export var default_settings : DFOutlineSettings


func get_scene_types() -> Array[SceneType]:
	var scene_types : Array[SceneType] = []
	for scene_type in _scene_type_path_properties:
		var scene_path := _get_scene_path(scene_type)

		# Use is_absolute_path() as quick but imperfect way to
		# ensure it's a path. If file itself is missing, it will fail later.
		if scene_path.is_absolute_path():
			scene_types.append(scene_type)
	return scene_types


func has_scene_type(p_type : SceneType) -> bool:
	return p_type in get_scene_types()


func get_packed_scene(p_type : SceneType) -> PackedScene:
	var scene_path := _get_scene_path(p_type)
	if not scene_path:
		return null
	return load(scene_path)


func get_palette(p_property_name : String) -> PackedColorArray:
	var palette_string : String
	match p_property_name:
		"outline_color":
			palette_string = outline_palette
		"background_color":
			palette_string = background_palette

	var colors : PackedColorArray = []
	for s in palette_string.split(");("):
		var color := Color.WHITE
		s = s.trim_prefix("(").trim_suffix(")")
		var value_string_splits := s.split(",")

		for i in value_string_splits.size():
			var value := float(value_string_splits[i])
			match i:
				0:
					color.r = value
				1:
					color.g = value
				2:
					color.b = value
				3:
					color.a = value
		colors.append(color)
	return colors


func _get_scene_path(p_type : SceneType) -> String:
	var property : String = _scene_type_path_properties.get(p_type, "")
	if not property:
		return ""
	return get(property)
