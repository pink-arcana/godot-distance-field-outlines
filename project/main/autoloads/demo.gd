extends Node

var default_settings : DFOutlineSettings = preload("res://main/demo_scenes/default_settings.tres")

var settings : DFOutlineSettings
var demo_scene : DemoScene
var scene_type : DemoScene.SceneType
var jf_calc : JFCalculator

var forward_plus_rendering : bool


func _ready() -> void:
	settings = default_settings.duplicate()
	var rendering_method : String = ProjectSettings.get_setting_with_override(
			"rendering/renderer/rendering_method",
	)
	forward_plus_rendering = (rendering_method == "forward_plus")


func update_settings(p_dict : Dictionary) -> void:
	settings.merge_settings_dictionary(p_dict)
	Events.settings_changed.emit()


func load_default_settings_for_scene() -> void:
	_load_default_settings(default_settings.outline_effect)


func load_default_settings_for_effect() -> void:
	_load_default_settings(settings.outline_effect)


func _load_default_settings(p_effect : DFOutlineSettings.EffectID) -> void:
	settings.merge_settings(default_settings)
	if demo_scene && demo_scene.default_settings:
		settings.merge_settings(demo_scene.default_settings)
	settings.outline_effect = p_effect
	settings.merge_settings_dictionary(DefaultSettings.EffectDefaults.get(p_effect, {}))
	Events.settings_changed.emit()
