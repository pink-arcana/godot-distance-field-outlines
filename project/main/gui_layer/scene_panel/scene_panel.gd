extends Control

const SETTINGS_CHANGE_DELAY := 0.5
const MIN_WIDTH : int = 2
const MAX_WIDTH : int = 2048

const DEMO_TYPE_DISPLAY_NAMES := {
	DemoScene.DemoType.UNSIGNED_DISTANCE_FIELD: "Unsigned Distance Field"
}

const DEFAULT_SCENE_TYPE := DemoScene.SceneType.NODE
const DF_OUTLINE_SCENE_TYPES := [
		DemoScene.SceneType.COMPOSITOR_EFFECT,
		DemoScene.SceneType.NODE,
	]


const TOOLTIP_DEPTH_FADE_REQUIRES_COMPOSITOR := "Depth fade is only available for CompositorEffects."
const TOOLTIP_COMPOSITOR_EFFECT_WEB := "\nTo preview the CompositorEffect, please download \
		the project from the Github repo."
const TOOLTIP_DEPTH_FADE_INCOMPATIBLE := "Depth fade is not compatible with outline effects."

const TOOLTIP_REQUIRES_FORWARD_PLUS := "CompositorEffect is not available for \
		web builds.\n To preview the CompositorEffect, please download \
		the project from the Github repo."
const SCENE_TYPE_TOOLTIPS := {
		DemoScene.SceneType.BASE: "View scene with no post-processing effects.",
		DemoScene.SceneType.NODE: "View scene with Node-based outlines.",
		DemoScene.SceneType.COMPOSITOR_EFFECT: "View scene with CompositorEffect outlines.",
	}

@export var demo_scenes : Array[DemoScene]

var tooltip_depth_fade_requires_compositor : String

var prev_demo_scene : DemoScene
var demo_scene : DemoScene
var demo_scene_type := DemoScene.SceneType.NONE


@onready var demo_type_button: OptionButton = %DemoTypeButton
@onready var scene_button: OptionButton = %SceneButton
@onready var scene_type_buttons := {
		DemoScene.SceneType.BASE : %BaseButton,
		DemoScene.SceneType.COMPOSITOR_EFFECT : %CEButton,
		DemoScene.SceneType.NODE : %NodeButton,
	}
@onready var scene_description_label: RichTextLabel = %SceneDescriptionLabel

@onready var outline_settings_container: Control = %OutlineSettingsContainer
@onready var reset_settings_button: Button = %ResetSettingsButton
@onready var effect_button: OptionButton = %EffectButton
@onready var white_background_button: CheckBox = %WhiteBackgroundButton
@onready var width_slider: HSlider = %WidthSlider
@onready var width_label: Label = %WidthLabel
@onready var width_fade_checkbox: IconCheckBox = %WidthFadeCheckbox
@onready var alpha_fade_checkbox: IconCheckBox = %AlphaFadeCheckbox



func _ready() -> void:
	tooltip_depth_fade_requires_compositor = TOOLTIP_DEPTH_FADE_REQUIRES_COMPOSITOR
	if OS.has_feature("web"):
		tooltip_depth_fade_requires_compositor += TOOLTIP_COMPOSITOR_EFFECT_WEB

	setup_buttons()
	Events.scene_loaded.connect(_on_Events_scene_loaded)
	Events.settings_changed.connect(_on_Events_settings_changed)

	load_first_scene.call_deferred()


func load_first_scene() -> void:
	# Load the first scene of first type in the demo scenes array
	_on_DemoTypeButton_item_selected(0)
	#var button : Button
	#if Demo.forward_plus_rendering:
		#button = scene_type_buttons[DemoScene.SceneType.COMPOSITOR_EFFECT]
	#else:
		#button = scene_type_buttons[DemoScene.SceneType.NONE]
	#button.button_pressed = true
	_on_SceneButton_item_selected(0)
	Demo.load_default_settings_for_scene()


func setup_buttons() -> void:
	demo_type_button.clear()
	for demo_type : DemoScene.DemoType in DEMO_TYPE_DISPLAY_NAMES:
		demo_type_button.add_item(
				DEMO_TYPE_DISPLAY_NAMES[demo_type],
				demo_type,
		)
	demo_type_button.item_selected.connect(_on_DemoTypeButton_item_selected)

	scene_button.item_selected.connect(_on_SceneButton_item_selected)

	scene_description_label.meta_clicked.connect(Events.website_requested.emit)

	for scene_type : DemoScene.SceneType in scene_type_buttons:
		var button : Button = scene_type_buttons[scene_type]
		button.pressed.connect(_on_SceneTypeButton_pressed.bind(scene_type))

	reset_settings_button.pressed.connect(_on_ResetSettings_button_pressed)

	effect_button.clear()
	for effect_id : DFOutlineSettings.EffectID in DemoTexts.EffectDisplayNames:
		effect_button.add_item(DemoTexts.EffectDisplayNames[effect_id], effect_id)
	effect_button.item_selected.connect(_on_EffectButton_item_selected)

	white_background_button.toggled.connect(_on_WhiteBackgroundButton_toggled)
	width_slider.value_changed.connect(_on_WidthSlider_value_changed)

	alpha_fade_checkbox.toggled.connect(_on_DepthFadeCheckbox_pressed)
	width_fade_checkbox.toggled.connect(_on_DepthFadeCheckbox_pressed)


func _on_DemoTypeButton_item_selected(p_idx : int) -> void:
	var demo_type := demo_type_button.get_item_id(p_idx) as DemoScene.DemoType
	scene_button.clear()
	for scene : DemoScene in demo_scenes:
		if scene.demo_type == demo_type:
			scene_button.add_item(scene.display_name)


func update_scene_type_buttons() -> DemoScene.SceneType:
	var available_types := demo_scene.get_scene_types()
	var current_scene_type := DemoScene.SceneType.NONE

	for scene_type : DemoScene.SceneType in scene_type_buttons:
		var button : Button = scene_type_buttons[scene_type]
		button.disabled = false

		var available = available_types.has(scene_type)
		button.visible = available

		if available:
			var tooltip : String = SCENE_TYPE_TOOLTIPS.get(scene_type, "")
			button.tooltip_text = tooltip

			if scene_type == DemoScene.SceneType.COMPOSITOR_EFFECT:
				if not Demo.forward_plus_rendering:
					button.disabled = true
					button.tooltip_text = TOOLTIP_REQUIRES_FORWARD_PLUS

		if button.visible && not button.disabled:
			if button.button_pressed:
				current_scene_type = scene_type
		else:
			button.set_pressed_no_signal(false)

	if current_scene_type == DemoScene.SceneType.NONE:
		var default_button : Button = scene_type_buttons[DEFAULT_SCENE_TYPE]
		if default_button.visible && not default_button.disabled:
			default_button.set_pressed_no_signal(true)
			current_scene_type = DEFAULT_SCENE_TYPE

	return current_scene_type


func update_controls_from_settings() -> void:
	width_slider.set_value_no_signal(Demo.settings.outline_width)
	width_label.text = str(Demo.settings.outline_width)

	var idx := effect_button.get_item_index(Demo.settings.outline_effect)
	effect_button.select(idx)

	white_background_button.set_pressed_no_signal(Demo.settings.use_background_color)

	var allow_depth := true
	if Demo.scene_type != DemoScene.SceneType.COMPOSITOR_EFFECT:
		allow_depth = false
		alpha_fade_checkbox.tooltip_text = tooltip_depth_fade_requires_compositor
		width_fade_checkbox.tooltip_text = tooltip_depth_fade_requires_compositor
	elif Demo.settings.outline_effect != DFOutlineSettings.EffectID.NONE:
		allow_depth = false
		alpha_fade_checkbox.tooltip_text = TOOLTIP_DEPTH_FADE_INCOMPATIBLE
		width_fade_checkbox.tooltip_text = TOOLTIP_DEPTH_FADE_INCOMPATIBLE
	else:
		alpha_fade_checkbox.tooltip_text = "Fade outline opacity by depth."
		width_fade_checkbox.tooltip_text = "Fade outline width by depth."

	alpha_fade_checkbox.set_checkbox_disabled(not allow_depth)
	width_fade_checkbox.set_checkbox_disabled(not allow_depth)

	if alpha_fade_checkbox.disabled:
		alpha_fade_checkbox.button_pressed = false
	else:
		alpha_fade_checkbox.set_pressed_no_signal(
				Demo.settings.depth_fade_mode in [
						DFOutlineSettings.DepthFadeMode.ALPHA,
						DFOutlineSettings.DepthFadeMode.ALPHA_AND_WIDTH,
				])

	if width_fade_checkbox.disabled:
		width_fade_checkbox.button_pressed = false
	else:
		width_fade_checkbox.set_pressed_no_signal(
				Demo.settings.depth_fade_mode in [
						DFOutlineSettings.DepthFadeMode.WIDTH,
						DFOutlineSettings.DepthFadeMode.ALPHA_AND_WIDTH,
				])



# ---------------------------------------------------------------------------
# SIGNALS
# ---------------------------------------------------------------------------


func _on_WidthSlider_value_changed(p_value : float) -> void:
	Demo.update_settings({"outline_width": p_value})
	width_label.text = str(p_value)


func _on_WhiteBackgroundButton_toggled(p_toggled_on : bool) -> void:
	Demo.update_settings({"use_background_color": p_toggled_on})


func _on_EffectButton_item_selected(p_idx : int) -> void:
	var effect_id := effect_button.get_item_id(p_idx) as DFOutlineSettings.EffectID
	Demo.update_settings({"outline_effect": effect_id})
	Demo.load_default_settings_for_effect()


func _on_DepthFadeCheckbox_pressed(_toggled_on : bool) -> void:
	var width_value = width_fade_checkbox.button_pressed
	var alpha_value = alpha_fade_checkbox.button_pressed
	var depth_setting : DFOutlineSettings.DepthFadeMode
	if width_value && alpha_value:
		depth_setting = DFOutlineSettings.DepthFadeMode.ALPHA_AND_WIDTH
	elif width_value:
		depth_setting = DFOutlineSettings.DepthFadeMode.WIDTH
	elif alpha_value:
		depth_setting = DFOutlineSettings.DepthFadeMode.ALPHA
	else:
		depth_setting = DFOutlineSettings.DepthFadeMode.NONE
	Demo.update_settings({"depth_fade_mode": depth_setting})


func _on_ResetSettings_button_pressed() -> void:
	Demo.load_default_settings_for_effect()


func _on_SceneButton_item_selected(p_idx : int) -> void:
	if p_idx < 0 or p_idx >= demo_scenes.size():
		return

	var next_scene : DemoScene = demo_scenes[p_idx]
	if next_scene == demo_scene:
		return

	prev_demo_scene = demo_scene
	demo_scene = next_scene
	demo_scene_type = update_scene_type_buttons()
	#prints("loading", next_scene, DemoScene.SceneType.keys()[demo_scene_type])
	Events.scene_change_requested.emit(next_scene, demo_scene_type)


func _on_SceneTypeButton_pressed(p_scene_type : DemoScene.SceneType) -> void:
	if Demo.scene_type == p_scene_type:
		return
	demo_scene_type = p_scene_type
	Events.scene_change_requested.emit(demo_scene, demo_scene_type)


func _on_Events_scene_loaded(
		p_demo_scene : DemoScene,
		p_scene_type : DemoScene.SceneType,
		_jf_calc : JFCalculator,
	) -> void:

	demo_scene = p_demo_scene
	demo_scene_type = p_scene_type
	update_scene_type_buttons()

	scene_description_label.text = demo_scene.description

	if demo_scene_type in DF_OUTLINE_SCENE_TYPES:
		outline_settings_container.show()
		update_controls_from_settings()
	else:
		outline_settings_container.hide()


func _on_Events_settings_changed() -> void:
	update_controls_from_settings()
