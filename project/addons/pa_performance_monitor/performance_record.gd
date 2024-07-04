class_name PerformanceRecord
extends RefCounted

# Adapted from Debug Menu plugin
# https://github.com/godot-extended-libraries/godot-debug-menu
# (MIT license Copyright © 2023-present Hugo Locurcio and contributors)

enum Type {
	TOTAL,
	CPU,
	GPU,
}

var _context : Dictionary

var _sum_func := func avg(accum: float, number: float) -> float: return accum + number

var _max_frame_count : int
var _stop_at_max : bool

var _frame_history := {
	Type.TOTAL: [] as Array[float],
	Type.CPU: [] as Array[float],
	Type.GPU: [] as Array[float],
}

var pad_decimal_count : int = 2

func _init(p_max_frame_count : int = 150, p_stop_at_max : bool = false, p_context := {}) -> void:
	_max_frame_count = p_max_frame_count
	_stop_at_max = p_stop_at_max
	_context = p_context


func add_frame(p_total : float, p_cpu : float, p_gpu : float) -> void:
	if _frame_history[Type.TOTAL].size() >= _max_frame_count:
		if _stop_at_max:
			return
		for arr : Array[float] in _frame_history.values():
			arr.pop_front()

	_frame_history[Type.TOTAL].append(p_total)
	_frame_history[Type.CPU].append(p_cpu)
	_frame_history[Type.GPU].append(p_gpu)


func get_average(p_type : Type) -> float:
	var arr : Array[float] = _frame_history[p_type]
	return arr.reduce(_sum_func) / arr.size()


func get_min(p_type : Type) -> float:
	var arr : Array[float] = _frame_history[p_type]
	return arr.min()


func get_max(p_type : Type) -> float:
	var arr : Array[float] = _frame_history[p_type]
	return arr.max()


func get_average_string(p_type : Type) -> String:
	var f := get_average(p_type)
	return str(f).pad_decimals(pad_decimal_count)


func get_min_string(p_type : Type) -> String:
	var f := get_min(p_type)
	return str(f).pad_decimals(pad_decimal_count)


func get_max_string(p_type : Type) -> String:
	var f := get_max(p_type)
	return str(f).pad_decimals(pad_decimal_count)


func get_frames_per_second() -> float:
	return 1000.0 / get_average(Type.TOTAL)


func get_context() -> Dictionary:
	var context := _context.duplicate()
	context["total_frames"] = _frame_history[Type.TOTAL].size()
	return context
