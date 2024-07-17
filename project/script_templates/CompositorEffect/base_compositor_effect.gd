@tool
extends BaseCompositorEffect


func _get_workgroup_size() -> int:
	return 16


# Called from _init().
func _initialize_resource() -> void:
	pass


# Called on render thread after _init().
func _initialize_render() -> void:
	pass


# Called at beginning of _render_callback(), after updating render variables.
# Use this function to setup textures or uniforms that do not depend on the view.
func _render_setup() -> void:
	pass


# Called for each view. Run the compute shaders from here.
func _render_view(p_view : int) -> void:
	pass


func _render_size_changed() -> void:
	pass