extends CanvasLayer

@export var engine: CarEngine

var max_value := 500
func _ready() -> void:
	var tq_panel := $TqHp_panel
	var steps = 10
	for i in range(steps + 1):
		var lbl = Label.new()
		var val = max_value - (i * (max_value / steps))
		lbl.text = str(val)
		
		lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tq_panel.add_child(lbl)
	pass
