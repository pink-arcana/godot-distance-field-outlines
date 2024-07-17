@tool
class_name DFOutlineSettings
extends Resource

signal outline_width_changed
signal depth_fade_mode_changed

# NOTE: Must sync changes to EffectID with overlay shaders.
enum EffectID {
	NONE = 0,
	BOX_BLUR = 1,
	SMOOTHING = 2,
	SUBPIXEL_AA = 3,
	PADDING = 4,
	INVERTED = 5,
	SKETCH = 6,
	NEON_GLOW = 7,
	RAINBOW_ANIMATION = 8,
	STEPPED_DISTANCE_FIELD = 9,
	RAW_DISTANCE_FIELD = 10,
}

# NOTE: Must sync changes to DepthFadeMode with overlay shaders.
enum DepthFadeMode {
	NONE=0,
	ALPHA=1,
	WIDTH=2,
	ALPHA_AND_WIDTH=3,
}

@export_category("Outline Settings")
## The outline width when displayed in a viewport of
## Outline Viewport Size. Automatically scales to other viewport sizes.
@export var outline_width : float = 8 :
	set(value):
		if outline_width == value:
			return
		outline_width = value
		outline_width_changed.emit()
		changed.emit()

@export var viewport_size := Vector2i(1920, 1080) :
	set(value):
		if viewport_size == value:
			return
		viewport_size = value
		outline_width_changed.emit()
		changed.emit()

## Click to set the Outline Viewport Size to the Viewport Width and Height defined Project Settings.
@export var reset_viewport_size := false :
	set(value):
		# Functions as a button, don't store its value.
		if value:
			viewport_size = Vector2i(
					ProjectSettings.get_setting("display/window/size/viewport_width"),
					ProjectSettings.get_setting("display/window/size/viewport_height"),
				)


@export_subgroup("Extraction")
@export_range(0.0, 10.0, 0.01, "exp") var sobel_threshold : float = 0.05 :
	set(value):
		if sobel_threshold == value:
			return
		sobel_threshold = value
		changed.emit()


@export_subgroup("Overlay")
@export var outline_effect := DFOutlineSettings.EffectID.NONE :
	set(value):
		if outline_effect == value:
			return
		outline_effect = value
		changed.emit()

@export var outline_color := Color.BLACK :
	set(value):
		if outline_color == value:
			return
		outline_color = value
		changed.emit()

@export var background_color := Color.WHITE :
	set(value):
		if background_color == value:
			return
		background_color = value
		changed.emit()

@export var use_background_color : bool = false :
	set(value):
		if use_background_color == value:
			return
		use_background_color = value
		changed.emit()

@export_range(0.5, 10.0, 0.5) var smoothing_distance : float = 1.5 :
	set(value):
		if smoothing_distance == value:
			return
		smoothing_distance = value
		changed.emit()


@export_subgroup("Depth Fade")
@export var depth_fade_mode := DFOutlineSettings.DepthFadeMode.NONE :
	set(value):
		if depth_fade_mode == value:
			return
		depth_fade_mode = value
		depth_fade_mode_changed.emit()
		changed.emit()

@export var depth_fade_start := 4.0 :
	set(value):
		if depth_fade_start == value:
			return
		depth_fade_start = value
		changed.emit()

@export var depth_fade_end :=  40.0 :
	set(value):
		if depth_fade_end == value:
			return
		depth_fade_end = value
		changed.emit()

@export var min_outline_width := 4.0 :
	set(value):
		if min_outline_width == value:
			return
		min_outline_width = value
		outline_width_changed.emit()
		changed.emit()

@export var min_outline_alpha := 0.0 :
	set(value):
		if min_outline_alpha == value:
			return
		min_outline_alpha = value
		changed.emit()


var settings_list : PackedStringArray

func _init() -> void:
	settings_list = PackedStringArray([])
	for property in get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var property_name : String = property["name"]
			settings_list.append(property_name)


func get_settings_dictionary() -> Dictionary:
	var dict := {}
	for property in get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var property_name : String = property["name"]
			dict[property_name] = get(property_name)
	return dict


func merge_settings(p_settings : DFOutlineSettings) -> void:
	merge_settings_dictionary(p_settings.get_settings_dictionary())


func merge_settings_dictionary(p_dict : Dictionary) -> void:
	for property_name in p_dict:
		var value : Variant = p_dict[property_name]
		if not settings_list.has(property_name):
			# This check is for debugging purposes only.
			# set() will fail silently if property_name does not exist.
			printerr("[DFOutlineSettings:merge_settings_dictionary()] Setting not found: %s" \
					% property_name)
			continue
		set(property_name, value)


func _validate_property(p_property: Dictionary) -> void:
	var exclude_properties : PackedStringArray = ["reset_viewport_size", "settings_list"]
	if p_property.name in exclude_properties:
		if p_property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			p_property.usage -= PROPERTY_USAGE_SCRIPT_VARIABLE
