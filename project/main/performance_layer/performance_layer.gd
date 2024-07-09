extends CanvasLayer

const DEBUG_QUICK_TESTS := false

@export var base_color := Color.BLACK
@export var node_color := Color.BLACK
@export var ce_color := Color.BLACK

const _WIDTHS : PackedInt32Array = [2,4,8,16,32,64,128,256,512,1024]

var _max_time : float = 0.1

var tests := {
	DemoScene.SceneType.BASE : [0.0],
	DemoScene.SceneType.NODE : _WIDTHS,
	DemoScene.SceneType.COMPOSITOR_EFFECT : _WIDTHS,
}

var current_test_idx := -1
var current_test_width_idx := -1

@onready var info_panel: PerformanceInfoPanel = %InfoPanel
@onready var results_tree: PerformanceTree = %ResultsTree
@onready var graph_rect: GraphRect = %GraphRect
@onready var back_button: Button = %BackButton

@onready var progress_container: Container = %ProgressContainer
@onready var results_container: Container = %ResultsContainer
@onready var graph_rect_container: Container = %GraphRectContainer


func _ready() -> void:
	get_tree().root.content_scale_factor = 1.0

	results_container.hide()
	progress_container.show()
	graph_rect.reparent(progress_container)
	await get_tree().process_frame

	back_button.pressed.connect(_on_BackButton_pressed)

	setup_graph_rect()

	Events.scene_loaded.connect(_on_Events_scene_loaded)
	PerformanceMonitor.recording_completed.connect(_on_PerformanceMonitor_recording_completed)

	if DEBUG_QUICK_TESTS:
		PerformanceMonitor.start_delay_frame_count = 10
		PerformanceMonitor.single_recording_frame_count = 10
	else:
		PerformanceMonitor.start_delay_frame_count = 10
		PerformanceMonitor.single_recording_frame_count = 1000

	request_next_test()




func request_next_test() -> void:
	if current_test_idx == -1:
		current_test_idx = 0
		current_test_width_idx = 0
	else:
		current_test_width_idx += 1

	var scene_type : DemoScene.SceneType = tests.keys()[current_test_idx]
	var width_list : Array = tests[scene_type]
	if current_test_width_idx >= width_list.size():
		current_test_idx += 1
		current_test_width_idx = 0
		if current_test_idx >= tests.size():
			show_results()
			return
		else:
			scene_type = tests.keys()[current_test_idx]
			width_list = tests[scene_type]

	var width : int = width_list[current_test_width_idx]

	Demo.update_settings({"outline_width" : width, "viewport_size": get_viewport().size})
	Events.scene_change_requested.emit(Demo.demo_scene, scene_type)



func _on_Events_scene_loaded(
		p_demo_scene : DemoScene,
		p_scene_type : DemoScene.SceneType,
		p_jf_calc : JFCalculator,
	) -> void:

	var params := {
			"demo_scene" : p_demo_scene,
			"scene_type" : p_scene_type,
			"jf_calc" : p_jf_calc,
		}
	PerformanceMonitor.start_single_recording(params)


func _on_PerformanceMonitor_recording_completed(p_record : PerformanceRecord) -> void:
	info_panel.update_from_context(p_record.get_context())
	var scene_type : DemoScene.SceneType = tests.keys()[current_test_idx]
	if scene_type == DemoScene.SceneType.BASE:
		results_tree.add_baseline(p_record)
	else:
		results_tree.add_record(p_record)
	results_tree.update_minimum_size()
	update_graph(p_record)
	request_next_test()


func show_results() -> void:
	graph_rect.reparent(graph_rect_container)
	results_container.show()
	progress_container.hide()



func _on_BackButton_pressed() -> void:
	Events.state_change_requested.emit(Main.State.GUI)


func setup_graph_rect() -> void:
	graph_rect.set_categories(_WIDTHS)
	# In order to match expected order in graph
	graph_rect.add_series(
			"Node",
			node_color,
			GraphRect.LineStyle.SOLID,
			true,
			DemoScene.SceneType.NODE as int,
	)
	graph_rect.add_series(
			"CompositorEffect",
			ce_color,
			GraphRect.LineStyle.SOLID,
			true,
			DemoScene.SceneType.COMPOSITOR_EFFECT as int,
	)
	graph_rect.add_series(
			"Base",
			base_color,
			GraphRect.LineStyle.DASHED,
			false,
			DemoScene.SceneType.BASE as int,
	)




func update_graph(p_record : PerformanceRecord) -> void:
	var frame_time := p_record.get_average(PerformanceRecord.Type.TOTAL)
	_max_time = maxf(_max_time, frame_time)
	graph_rect.y_max = ceilf(_max_time)

	var jf_calc : JFCalculator = p_record.get_context()["jf_calc"]

	var scene_type : DemoScene.SceneType = tests.keys()[current_test_idx]
	var series_id := scene_type as int

	if scene_type == DemoScene.SceneType.BASE:
		var dict := {}
		for w in _WIDTHS:
			dict[w] = frame_time
		graph_rect.add_values(series_id, dict)
		return

	assert(jf_calc)
	if not jf_calc:
		return
	var width : float = jf_calc.get_debug_dict().get("_render_outline_width", 0.0)
	var width_i := roundi(width)
	assert(_WIDTHS.has(width_i), "render width=%s not found in _WIDTHS" % width_i)
	await get_tree().process_frame
	graph_rect.add_values(series_id, {width_i : frame_time})
