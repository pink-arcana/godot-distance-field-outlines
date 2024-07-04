class_name PalettePicker
extends Control

const ColorButtonPackedScene : PackedScene = preload( \
		"res://main/gui_layer/scene_panel/palette_picker/color_button.tscn")

var icon_color_properties : PackedStringArray = [
	"theme_override_colors/icon_hover_pressed_color",
	"theme_override_colors/icon_hover_color",
	"theme_override_colors/icon_disabled_color",
	"theme_override_colors/icon_pressed_color",
	"theme_override_colors/icon_focus_color",
	"theme_override_colors/icon_normal_color",
]

@onready var button_container: Control = %ButtonContainer

@export var setting_name : String
var button_colors := {}


func _ready() -> void:
	Events.scene_loaded.connect(_on_Events_scene_loaded)
	Events.settings_changed.connect(_on_Events_settings_changed)

	load_palette_from_demo_scene.call_deferred()


func load_palette_from_demo_scene() -> void:
	if not Demo:
		return
	var demo_scene := Demo.demo_scene
	if not demo_scene:
		return
	var colors := demo_scene.get_palette(setting_name)
	if colors:
		update_colors(colors)
	else:
		update_colors(PackedColorArray([Color.WHITE, Color.BLACK]))


func update_colors(p_colors : PackedColorArray) -> void:
	button_colors.clear()
	for child in button_container.get_children():
		child.hide()
		child.queue_free()

	var button_group := ButtonGroup.new()

	for color in p_colors:
		var button : Button = ColorButtonPackedScene.instantiate()
		for property in icon_color_properties:
			button.set(property, color)
		button.button_group = button_group
		button.pressed.connect(_on_ColorButton_pressed.bind(color))
		button.tooltip_text = tooltip_text
		button_colors[color] = button
		button_container.add_child(button)


func _on_Events_scene_loaded(
		_demo_scene : DemoScene,
		_scene_type : DemoScene.SceneType,
		_jf_calc : JFCalculator,
	) -> void:

	load_palette_from_demo_scene()


func _on_Events_settings_changed() -> void:
	var current_color : Color = Demo.settings.get(setting_name)
	for color in button_colors:
		var button : Button = button_colors[color]
		button.set_pressed_no_signal(color == current_color)


func _on_ColorButton_pressed(p_color : Color) -> void:
	if setting_name == "background_color":
		Demo.update_settings({
					setting_name : p_color,
					"use_background_color": true,
		})
	else:
		Demo.update_settings({setting_name : p_color})
