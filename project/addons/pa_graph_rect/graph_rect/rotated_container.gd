extends VBoxContainer

func _ready() -> void:
	resized.connect(_on_resized)
	_on_resized()

func _on_resized() -> void:
	custom_minimum_size = Vector2(get_parent_control().size.y, get_parent_control().size.x)
	pivot_offset = size/2.0
