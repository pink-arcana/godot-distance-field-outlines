@tool
class_name CameraGimbal
extends Node3D

# Adapted from KidsCanCode: Camera Gimbal
# https://kidscancode.org/godot_recipes/3.x/3d/camera_gimbal/

signal gimbal_input_capture_changed(value : bool)

const DEBUG_PRINT_CAMERA_DISTANCE := false
const RESTORE_MOUSE_TIME := 1000 # milliseconds

const INPUT_ACTIONS := [
		"camera_rotate_left",
		"camera_rotate_right",
		"camera_rotate_up",
		"camera_rotate_down",
		"camera_zoom_in",
		"camera_zoom_out",
]

@export var disable_input : bool = false

@export var default_y_rotation := 0.0
@export var default_x_rotation := 0.0
@export var default_zoom := 1.0
@export var min_zoom := 0.8
@export var max_zoom := 7.5
@export var reset_camera : bool = false :
	set(value):
		reset_transforms()

var rotation_speed := PI/2.0
var mouse_sensitivity := 0.0007

var max_zoom_speed_keyboard := 8.0
var max_zoom_speed_mouse_scroll := 2.0
var zoom_acceleration := 2.0
var zoom_deceleration := 0.1

var invert_y := false
var invert_x := false

var angular_input_velocity := Vector2.ZERO
var angular_velocity := Vector2.ZERO

var zoom_input_velocity := 0.0
var zoom_velocity := 0.0

var mouse_movement := Vector2.ZERO

var last_mouse_pos := Vector2.INF
var last_mouse_capture_time : int = -1

var mouse_input_captured := false
var keyboard_input_captured := false
var input_captured := false :
	set(value):
		if input_captured == value:
			return
		input_captured = value
		gimbal_input_capture_changed.emit(value)

@onready var gimbal_y: Node3D = %GimbalY
@onready var gimbal_x: Node3D = %GimbalX


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(false)
		set_process_input(false)
		set_physics_process(false)

	reset_transforms()


func reset_transforms() -> void:
	angular_velocity = Vector2.ZERO
	zoom_velocity = 0.0

	gimbal_y.transform = Transform3D.IDENTITY
	gimbal_x.transform = Transform3D.IDENTITY

	gimbal_y.rotation.y = deg_to_rad(default_y_rotation)
	gimbal_x.rotation.x = deg_to_rad(default_x_rotation)
	gimbal_y.scale = Vector3(default_zoom, default_zoom, default_zoom)


func _unhandled_input(p_event: InputEvent) -> void:
	if disable_input:
		return

	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if p_event is InputEventMouseMotion:
			mouse_movement += p_event.screen_relative

	if p_event is InputEventMouseButton:
		match p_event.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_toggle_mouse_captured(p_event.pressed)
			MOUSE_BUTTON_WHEEL_UP:
				if p_event.pressed:
					#prints("final_xform", get_tree().root.get_final_transform())
					zoom_input_velocity += -max_zoom_speed_mouse_scroll
			MOUSE_BUTTON_WHEEL_DOWN:
				if p_event.pressed:
					zoom_input_velocity += max_zoom_speed_mouse_scroll

	if OS.is_debug_build() && p_event.is_action("debug_print_camera_transform"):
		if p_event.pressed:
			debug_print_transform()


# Trying input in _physics_process since it is capped,
# and _process is uncapped.
func _process(p_delta: float) -> void:
	if disable_input:
		return

	_update_input_capture_state()

	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_update_angular_velocity_from_mouse_movement()
	else:
		_update_angular_velocity_from_input_axis(p_delta)

	gimbal_y.rotate_object_local(Vector3.UP, angular_velocity.y)
	gimbal_x.rotate_object_local(Vector3.RIGHT, angular_velocity.x)

	# Stop vertical rotation at top and bottom
	gimbal_x.rotation.x = clampf(gimbal_x.rotation.x, -PI/2.0 + 0.25, PI/2.0 - 0.25)

	# If no zoom input was created for mouse scroll, get zoom input
	# from keyboard.
	if is_zero_approx(zoom_input_velocity):
		var zoom_input_axis := Input.get_axis("camera_zoom_in", "camera_zoom_out")
		zoom_input_velocity = zoom_input_axis * max_zoom_speed_keyboard * p_delta

	_update_zoom(p_delta)
	angular_velocity = Vector2.ZERO
	zoom_input_velocity = 0.0
	mouse_movement = Vector2.ZERO


func _update_angular_velocity_from_mouse_movement() -> void:
	# Moving the mouse in x axis rotates the camera left-right around the y axis.
	var horizontal_movement : float = mouse_movement.x
	var horizontal_dir := 1.0 if invert_x else -1.0
	angular_velocity.y = horizontal_dir * horizontal_movement * mouse_sensitivity

	# Moving the mouse in y axis rotates the camera up-down around the x axis.
	# Clamped to prevent large mouse movements causing wild camera changes.
	var vertical_movement := clampf(mouse_movement.y, -30.0, 30.0)
	var vertical_dir := 1.0 if invert_y else -1.0
	angular_velocity.x = vertical_dir * vertical_movement * mouse_sensitivity


func _update_angular_velocity_from_input_axis(p_delta : float) -> void:
	var horizontal_axis := Input.get_axis("camera_rotate_left", "camera_rotate_right")
	angular_velocity.y = horizontal_axis * rotation_speed * p_delta

	var vertical_axis := Input.get_axis("camera_rotate_up", "camera_rotate_down")
	angular_velocity.x = vertical_axis * rotation_speed * p_delta


func _update_zoom(p_delta : float) -> void:
	if is_zero_approx(zoom_input_velocity):
		zoom_velocity = move_toward(zoom_velocity, 0.0, zoom_deceleration * p_delta)
	else:
		zoom_velocity = lerp(
				zoom_velocity,
				zoom_input_velocity,
				zoom_acceleration * p_delta,
			)

	var zoom_scale : Vector3 = gimbal_y.scale + zoom_velocity * Vector3.ONE
	zoom_scale = zoom_scale.clampf(min_zoom, max_zoom)

	# Used to debug depth buffer.
	if DEBUG_PRINT_CAMERA_DISTANCE && zoom_scale != gimbal_y.scale:
		prints("camera distance:", get_viewport().get_camera_3d().global_position.distance_to(global_position))

	gimbal_y.scale = zoom_scale


func _toggle_mouse_captured(p_value : bool) -> void:
	if p_value:
		last_mouse_pos = get_viewport().get_mouse_position()
		last_mouse_capture_time = Time.get_ticks_msec()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		if (Time.get_ticks_msec() - last_mouse_capture_time) < RESTORE_MOUSE_TIME:
			if not is_inf(last_mouse_pos.x):
				# Adjust position to account for viewport content scale.
				Input.warp_mouse(last_mouse_pos * get_viewport().get_screen_transform())
		last_mouse_capture_time = -1
	mouse_input_captured = p_value


func _update_input_capture_state() -> void:
	keyboard_input_captured = false
	if Input.is_anything_pressed():
		for action_name in INPUT_ACTIONS:
			if Input.is_action_pressed(action_name):
				keyboard_input_captured = true
				break
	input_captured = keyboard_input_captured or mouse_input_captured


func debug_print_transform() -> void:
	print()
	print("Camera Gimbal:")
	prints("y_rotation", rad_to_deg(gimbal_y.rotation.y))
	prints("x_rotation", rad_to_deg(gimbal_x.rotation.x))
	prints("zoom", gimbal_y.scale.x)
	print()
