extends Label


func _ready() -> void:
	resized.connect(_on_resized)
	_on_resized()

func _on_resized() -> void:
	pivot_offset = get_rect().get_center()
