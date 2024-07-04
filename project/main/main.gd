class_name Main
extends Control

const GUILayerPackedScene : PackedScene = preload("res://main/gui_layer/gui_layer.tscn")
const PerformanceLayerPackedScene : PackedScene = preload("res://main/performance_layer/performance_layer.tscn")

enum State {
	NONE,
	GUI,
	PERFORMANCE,
}

var state := State.NONE :
	set(value):
		if state == value:
			return
		state = value
		update_state_layers()


var state_layer : CanvasLayer = null

func _ready() -> void:
	Events.website_requested.connect(_on_Events_website_requested)
	Events.state_change_requested.connect(_on_Events_state_change_requested)
	Events.test_performance_requested.connect(_on_Events_test_performance_requested)
	state = State.GUI


func update_state_layers() -> void:
	if state_layer:
		state_layer.tree_exited.connect(_finish_update_state_layers)
		state_layer.queue_free()
	else:
		_finish_update_state_layers()


func _finish_update_state_layers() -> void:
	# Need to wait for nodes to be freed (not just exited tree),
	# or their root.size_changed signals may be called
	# when the next layer is loaded.
	await get_tree().process_frame
	match state:
		State.GUI:
			state_layer = GUILayerPackedScene.instantiate()
		State.PERFORMANCE:
			state_layer = PerformanceLayerPackedScene.instantiate()

	state_layer.ready.connect(Events.state_changed.emit.bind(state))
	add_child(state_layer)


func _on_Events_state_change_requested(p_state : State) -> void:
	state = p_state


func _on_Events_website_requested(p_url : Variant) -> void:
	OS.shell_open(str(p_url))


func _on_Events_test_performance_requested() -> void:
	state = State.PERFORMANCE
