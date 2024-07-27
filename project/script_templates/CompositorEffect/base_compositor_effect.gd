@tool
extends BaseCompositorEffect

const SHADER_PATH := ""

# Set 0
# Scene data UBO = 0
# Color image = 1
# Depth sampler = 2
# Normal roughness sampler = 3

# Set 1
const TEXTURE_IMAGE_BINDING := 0

var context := &"Context"

var shader : RID
var shader_pipeline : RID

var texture := &"Texture"
var texture_image : RID
var texture_image_uniform : RID



# Called from _init().
func _initialize_resource() -> void:
	# access_resolved_color = true
	# access_resolved_depth = true
	# needs_normal_roughness = true
	pass


# Called on render thread after _init().
func _initialize_render() -> void:
	# shader = create_shader(SHADER_PATH)
	# shader_pipeline = create_pipeline(shader)
	pass


# Called at beginning of _render_callback(), after updating render variables
# and after _render_size_changed().
# Use this function to setup textures or uniforms.
func _render_setup() -> void:
	# if not render_scene_buffers.has_texture(context, texture):
	# 	create_textures()
	pass


# Called for each view. Run the compute shaders from here.
func _render_view(p_view : int) -> void:
	# var scene_uniform_set : Array[RDUniform] = get_scene_uniform_set(p_view)

	# var uniform_sets : Array[Array] = [
	# 	scene_uniform_set,
	# 	[texture_image_uniform],
	# ]

	# run_compute_shader(
	# 	"ObjectData",
	# 	shader,
	# 	shader_pipeline,
	# 	uniform_sets,
	# )
	pass


# Called before _render_setup() if `render_size` has changed.
func _render_size_changed() -> void:
	render_scene_buffers.clear_context(context)


# func create_textures() -> void:
	# texture_image = create_simple_texture(
	# 		context,
	# 		texture,
	# 		RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
	# )

	# texture_image_uniform = get_image_uniform(texture_image, TEXTURE_IMAGE_BINDING)