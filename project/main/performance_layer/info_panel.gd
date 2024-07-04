class_name PerformanceInfoPanel
extends PanelContainer

const EMPTY := "---"

@onready var context_container: GridContainer = %ContextContainer

func _ready() -> void:
	reset()


func reset() -> void:
	for child in context_container.get_children():
		child.hide()
		child.queue_free()


func update_from_context(p_context : Dictionary) -> void:
	reset()

	var context := p_context

	var total_passes : int = 0
	if Demo.jf_calc:
		total_passes = 2 + context.jf_calc.get_step_offsets().size()

	context["max_passes"] = total_passes
	context["demo"] = Demo.demo_scene.display_name

	var effect_id := Demo.settings.outline_effect
	context["effect"] = DemoTexts.EffectDisplayNames.get(
			Demo.settings.outline_effect,
			str(effect_id),
	)

	var hidden_keys : PackedStringArray = [
			"jf_calc",
			"demo_scene",
			"scene_type",
	]

	for key in context:
		if key in hidden_keys:
			continue

		var display_label := Label.new()
		display_label.text = str(key).replace("_", " ").capitalize()
		display_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		context_container.add_child(display_label)

		var value_label := Label.new()
		value_label.text = str(context[key])
		value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		value_label.theme_type_variation = "BoldLabel"
		context_container.add_child(value_label)
