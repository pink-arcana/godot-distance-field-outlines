extends IconCheckBox


func _ready() -> void:
	super._ready()
	Events.touch_buttons_requested.connect(_on_Events_touch_buttons_requested)
	var toggled_on := DisplayServer.is_touchscreen_available()
	Events.touch_buttons_requested.emit.call_deferred(toggled_on)


func _toggled(p_toggled_on: bool) -> void:
	Events.touch_buttons_requested.emit(p_toggled_on)


func _on_Events_touch_buttons_requested(p_value : bool) -> void:
	set_pressed_no_signal(p_value)
