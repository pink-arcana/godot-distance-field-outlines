@tool
extends EditorPlugin

const MONITOR_NAME := "PerformanceMonitor"
const SNAPSHOT_NAME := "PerformanceSnapshot"

func _enter_tree() -> void:
	add_autoload_singleton(MONITOR_NAME, "res://addons/pa_performance_monitor/performance_monitor.gd")
	add_autoload_singleton(SNAPSHOT_NAME, "res://addons/pa_performance_monitor/performance_snapshot/performance_snapshot.tscn")


func _exit_tree() -> void:
	remove_autoload_singleton(MONITOR_NAME)
	remove_autoload_singleton(SNAPSHOT_NAME)
