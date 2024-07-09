extends MarginContainer

const PLACEHOLDER_GROUP := "TouchButtonPlaceholder"

var placeholder : Control

func _ready() -> void:
	Events.touch_buttons_requested.connect(_on_Events_touch_buttons_requested)

	placeholder = get_tree().get_first_node_in_group(PLACEHOLDER_GROUP)
	if not placeholder:
		printerr("Could not find TouchButtonPlaceholder")
		return

	placeholder.minimum_size_changed.connect(update_position.call_deferred)
	get_tree().root.size_changed.connect(update_position.call_deferred)
	visibility_changed.connect(update_position.call_deferred)



func update_position() -> void:
	if not visible:
		return
	scale = Vector2.ONE / get_tree().root.content_scale_factor
	update_minimum_size()
	await RenderingServer.frame_post_draw
	var pos_end := placeholder.get_global_rect().end
	global_position = pos_end - get_rect().size


func _on_Events_touch_buttons_requested(p_value : bool) -> void:
	visible = p_value
	# preset gets lost after one toggle on/off
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
