extends PanelContainer

@export var top_panel : Control
@export var scroll_container : ScrollContainer
@export var scroll_contents_container : Container
@export var contents_container : Container


var max_height := 960


func _ready() -> void:
	# Will update when window resized or content scale changed.
	get_tree().root.size_changed.connect(update_scroll)

	# Will update when this container is resized.
	resized.connect(update_scroll)

	update_scroll()


func update_scroll() -> void:
	var total_size :=  contents_container.get_combined_minimum_size() * get_tree().root.content_scale_factor
	total_size += top_panel.get_combined_minimum_size() * get_tree().root.content_scale_factor

	if total_size.y < max_height:
		#print("total size y < max_height, removing scroll")
		if size_flags_vertical & SIZE_EXPAND:
			size_flags_vertical -= SIZE_EXPAND
		scroll_container.hide()
		if not contents_container.get_parent() == self:
			contents_container.reparent(self, false)
	else:
		#print("total size y > max_height, adding scroll")
		scroll_container.show()
		scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
		if not size_flags_vertical & SIZE_EXPAND:
			size_flags_vertical += SIZE_EXPAND
		if not contents_container.get_parent() == scroll_contents_container:
			contents_container.reparent(scroll_contents_container)
