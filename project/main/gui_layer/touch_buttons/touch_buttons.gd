extends MarginContainer



func _ready() -> void:
	Events.touch_buttons_requested.connect(_on_Events_touch_buttons_requested)


func _on_Events_touch_buttons_requested(p_value : bool) -> void:
	visible = p_value
	# preset gets lost after one toggle on/off
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
