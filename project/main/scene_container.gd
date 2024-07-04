extends Node

const SETTINGS_CHANGE_DELAY := 0.1
const DEBUG_PRINT_SETTINGS_UPDATES := true

var demo_scene_node : Node = null
var df_outline_object : Object = null

func _ready() -> void:
	Events.scene_change_requested.connect(_on_Events_scene_change_requested)


func load_scene(
		p_demo_scene : DemoScene,
		p_scene_type : DemoScene.SceneType,
	) -> void:

	df_outline_object = null

	if demo_scene_node:
		demo_scene_node.hide()
		demo_scene_node.queue_free()
		await demo_scene_node.tree_exited

	var demo_changed := (Demo.demo_scene != p_demo_scene)

	Demo.demo_scene = p_demo_scene
	Demo.scene_type = p_scene_type

	if demo_changed:
		Demo.load_default_settings_for_scene()

	var next_scene_packed = p_demo_scene.get_packed_scene(p_scene_type)
	if not next_scene_packed:
		push_error("Error loading scene.")
		return

	demo_scene_node = next_scene_packed.instantiate()
	demo_scene_node.ready.connect(_on_scene_loaded)
	add_child(demo_scene_node)


func _on_scene_loaded() -> void:
	update_df_outline_object()

	if df_outline_object:
		Demo.jf_calc = df_outline_object.get("jf_calc")
		df_outline_object.set("outline_settings", Demo.settings)
	else:
		Demo.jf_calc = null


	var camera_gimbal : CameraGimbal = get_tree().get_first_node_in_group("CameraGimbal")
	if camera_gimbal:
		camera_gimbal.gimbal_input_capture_changed.connect(
				func(value : bool):
					Events.gimbal_input_capture_changed.emit(value)
		)

	Events.scene_loaded.emit(Demo.demo_scene, Demo.scene_type, Demo.jf_calc)


# Sets current_df_outline_object to either DFOutlineNode or DFOutlineCE resource
func update_df_outline_object() -> void:
	df_outline_object = null

	if not demo_scene_node:
		return

	var camera := get_tree().get_first_node_in_group("DFCamera") as Camera3D
	if camera:
		for effect in camera.compositor.compositor_effects:
			if effect is DFOutlineCE:
				df_outline_object = effect
				return

	var node := get_tree().get_first_node_in_group("DFNode") as Node
	if node:
		df_outline_object = node


func _on_Events_scene_change_requested(
		p_demo_scene : DemoScene,
		p_scene_type : DemoScene.SceneType,
	) -> void:

	load_scene(p_demo_scene, p_scene_type)
