class_name IconCheckBox
extends CheckBox

var unchecked : Texture2D = preload("res://main/theme/icons/toggle_off.png")
var unchecked_hover : Texture2D = preload("res://main/theme/icons/toggle_off_hover.png")
var checked : Texture2D = preload("res://main/theme/icons/toggle_on.png")
var checked_hover : Texture2D = preload("res://main/theme/icons/toggle_on_hover.png")


func _ready() -> void:
	mouse_entered.connect(update_icon.bind(true))
	mouse_exited.connect(update_icon.bind(false))


func update_icon(p_hovered : bool) -> void:
	if p_hovered:
		set("theme_override_icons/checked", checked_hover)
		set("theme_override_icons/unchecked", unchecked_hover)
	else:
		set("theme_override_icons/checked", checked)
		set("theme_override_icons/unchecked", unchecked)
