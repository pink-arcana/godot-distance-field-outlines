@tool
class_name DFNodeSubViewport
extends SubViewport
### Adds a duplicate of the provided Camera3D as a child of this SubViewport
### and give it the specified cull mask.
### Dynamically update this SubViewport's size
### to match the Scene Camera's Viewport's size.


@export var camera_3D : Camera3D
@export_flags_3d_render var cull_mask

var viewport_camera : Camera3D
var remote_transform : RemoteTransform3D

func _ready() -> void:
	if camera_3D:
		setup(camera_3D)


func setup(p_camera : Camera3D) -> void:
	var scene_camera := p_camera
	if not scene_camera:
		return

	var scene_viewport := scene_camera.get_viewport()
	if not scene_viewport.size_changed.is_connected(update_size_from_viewport):
		scene_viewport.size_changed.connect(update_size_from_viewport.bind(scene_viewport))
	update_size_from_viewport(scene_viewport)

	if viewport_camera:
		viewport_camera.queue_free()

	viewport_camera = scene_camera.duplicate()
	add_child(viewport_camera)
	viewport_camera.current = true

	if remote_transform:
		remote_transform.queue_free()

	remote_transform = RemoteTransform3D.new()
	scene_camera.add_child(remote_transform)
	remote_transform.remote_path = remote_transform.get_path_to(viewport_camera)


func update_size_from_viewport(p_viewport : Viewport) -> void:
	size = p_viewport.size
