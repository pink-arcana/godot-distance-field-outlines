@tool
class_name JFCalculator
extends RefCounted

signal changed

const EXPAND_SYMMETRICALLY := true
const EXPAND_ONE_DIRECTION := false

## Whether we expand the outline on both sides of our original seed.
## This changes the texel distance needed to get our desired width.
var _expand_symmetrically : bool

## The size of the screen texture we are drawing outlines to.
var _render_size := Vector2i.ZERO

## Diagonal distance of render_size.
## Used as denominator for normalizing distances.
var _render_max_dist : float = 0.0

## The largest dimension of our render_size, used for calculating
## the JFA steps needed to cover a square area that will encompass our render_size.
var _render_max_dimension : int

## Cached input data for debugging.
var _input_outline_width : float
var _input_viewport_size : Vector2i

## The outline width we want to draw, normalized [0-1].
var _outline_width_n : float = 0.0

## The outline width in texels that we want to draw
## for our given render_size.
var _render_outline_width : float = 0

## The distance in texels from our initial seed
## to draw render_outline_width.
var _dist_from_seed : float

## The nearest power of 2 to dist_from_seed.
var _jf_max_offset : int = 0

## The number of JFA steps needed to cover our entire render_size.
var _jf_step_count : int = 0

## The offsets for each JFA pass, in order
var _step_offsets : PackedInt32Array

var _all_step_offsets : PackedInt32Array

var debug_print_values := false


func _init(p_expand_symmetrically := EXPAND_SYMMETRICALLY) -> void:
	_expand_symmetrically = p_expand_symmetrically


# Returns true if value is changed.
func set_render_size(p_size : Vector2i) -> bool:
	# If either component is zero, both should be zero. Disallow negative sizes.
	var size : Vector2i = Vector2i.ZERO if p_size.x <= 0 or p_size.y <= 0 else p_size
	if size == _render_size:
		return false
	_render_size = size
	_render_max_dist = _get_diagonal_distance(size)
	_render_max_dimension = maxi(size.x, size.y)
	_jf_step_count = ceil(log(_render_max_dimension)/log(2))
	_update()
	return true


func set_outline_width(p_outline_width : float, p_viewport_size : Vector2i) -> void:
	if p_outline_width == _input_outline_width && p_viewport_size == _input_viewport_size:
		return

	_input_outline_width = p_outline_width
	_input_viewport_size = p_viewport_size

	if p_viewport_size == Vector2i.ZERO:
		_outline_width_n = 0.0
	else:
		_outline_width_n = p_outline_width / _get_diagonal_distance(p_viewport_size)

	_update()


# Returns only the offsets required for the given outline size.
func get_step_offsets() -> PackedInt32Array:
	return _step_offsets

# Returns all the offsets for the render size.
func get_all_step_offsets() -> PackedInt32Array:
	return _all_step_offsets


func get_max_offset() -> int:
	return max(_jf_max_offset, 1)


func get_outline_distance() -> float:
	return _dist_from_seed


func get_distance_denominator() -> float:
	# Using a denominator based on the width,
	# allows us to preserve precison at smaller widths.
	return get_max_offset() + 10.0


func get_debug_dict() -> Dictionary:
	var dict := {}
	for property_dict in get_property_list():
		var property_name : StringName = property_dict["name"]
		if not property_name.begins_with("_"):
			continue
		var property_value = get(property_name)
		dict[property_name] = property_value

	dict["distance_denominator"] = get_distance_denominator()
	dict["max_offset"] = get_max_offset()

	return dict


func print_debug_dict() -> void:
	print()
	print("-------------------------")
	print("JFCalculator")
	var debug_dict := get_debug_dict()
	for key in debug_dict:
		var value = debug_dict[key]
		print(key, " = ", value)
	print("-------------------------")
	print()


func _update() -> void:
	_render_outline_width = (_outline_width_n * _render_max_dist)

	if _expand_symmetrically:
		_dist_from_seed = max((_render_outline_width)/2.0, 0.0)
	else:
		_dist_from_seed = max((_render_outline_width), 0.0)

	_jf_max_offset = nearest_po2(ceili(_dist_from_seed))
	_update_step_offsets()

	if debug_print_values:
		print_debug_dict()

	changed.emit()


func _update_step_offsets() -> void:
	_step_offsets.clear()
	_all_step_offsets.clear()

	var max_offset : int = get_max_offset()

	# JFA steps start with furthest distance offset based on our the render size,
	# then move closer.
	for i in _jf_step_count:
		var offset := int(pow(2, _jf_step_count - i - 1))
		var last_step : bool = (i == _jf_step_count - 1)

		_all_step_offsets.append(offset)

		# Always run the last step. It creates the distance field.
		if last_step or offset <= max_offset:
			_step_offsets.append(offset)


func _get_diagonal_distance(p_size : Vector2i) -> float:
	return sqrt(pow(p_size.x, 2) + pow(p_size.y, 2))
