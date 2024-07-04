extends Button

var camera_gimbal : CameraGimbal

func _ready() -> void:
	Events.scene_loaded.connect(_on_Events_scene_loaded)


func _pressed() -> void:
	if camera_gimbal:
		camera_gimbal.reset_transforms()


func _on_Events_scene_loaded(
		_demo_scene : DemoScene,
		_scene_type : DemoScene.SceneType,
		_jf_calc : JFCalculator,
	) -> void:

	camera_gimbal = get_tree().get_first_node_in_group("CameraGimbal")
	visible = true if camera_gimbal else false
