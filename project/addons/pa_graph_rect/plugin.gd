@tool
extends EditorPlugin


func _enter_tree() -> void:
	add_custom_type(
		"GraphRect",
		"Control",
		preload("res://addons/pa_graph_rect/graph_rect/graph_rect.gd"),
		preload("res://addons/pa_graph_rect/graph_rect/graph_rect.svg"),
	)


func _exit_tree() -> void:
	remove_custom_type("GraphRect")
