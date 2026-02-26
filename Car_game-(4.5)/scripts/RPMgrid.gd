extends Control

# --- Export Variables ---
@export var engine: CarEngine
@export var grid_color := Color(1, 1, 1, 0.2)

# --- Private Variables (State) ---
var tq_scale: float = 500.0
var hp_scale: float = 500.0

# --- Node References ---
@onready var graph_area := $Graph_area
@onready var torque_line = $Graph_area/TorqueLine
@onready var hp_line = $Graph_area/HPLine

func _ready():
	await get_tree().process_frame
	setup_line_styles()
	update_graph()

# --- Visual Styling ---
func setup_line_styles():
	# Use tabs to group property assignments
	torque_line.width = 4.0
	torque_line.default_color = Color.CRIMSON
	torque_line.antialiased = true
	
	hp_line.width = 4.0
	hp_line.default_color = Color.CORNFLOWER_BLUE
	hp_line.antialiased = true

# --- UI Updates ---
func update_y_labels(max_val: float):
	var panel = get_parent().get_parent().get_node("TqHp_panel")
	if not panel: return
	
	var labels = panel.get_children()
	for i in range(labels.size()):
		# Tab-indented logic for calculating step values
		var val = max_val - (i * (max_val / (labels.size() - 1)))
		labels[i].text = str(int(val))

# --- Core Logic ---
func update_graph():
	if not engine or not torque_line or not hp_line: return
	
	# 1. Finding Peaks (Indented Block)
	var max_val_found = 0.1
	for i in range(0, 101):
		var r = lerp(float(engine.idle_rpm), float(engine.max_rpm), i / 100.0)
		var tq = engine.get_torque_at_rpm(r)
		var hp = (tq * r) / 7000.0
		max_val_found = max(max_val_found, max(tq, hp))
	
	# 2. Applying Scale
	tq_scale = max_val_found * 1.1
	hp_scale = tq_scale
	
	update_y_labels(tq_scale)
	torque_line.clear_points()
	hp_line.clear_points()
	
	# 3. Drawing Lines (Indented Loop)
	var w = graph_area.size.x
	var h = graph_area.size.y
	
	for i in range(0, 101):
		var r = lerp(float(engine.idle_rpm), float(engine.max_rpm), i / 100.0)
		var tq = engine.get_torque_at_rpm(r)
		var hp = (tq * r) / 7000.0
		
		var x = (r / engine.max_rpm) * w
		var y_tq = h - (tq / tq_scale) * h
		var y_hp = h - (hp / tq_scale) * h
		
		torque_line.add_point(Vector2(x, y_tq))
		hp_line.add_point(Vector2(x, y_hp))
	
	queue_redraw()

# --- Drawing Grid ---
func _draw() -> void:
	if not engine: return
	
	var w = graph_area.size.x
	var h = graph_area.size.y
	var pos = graph_area.position
	
	# Завантажуємо стандартний шрифт для підписів
	var default_font = ThemeDB.get_fallback_font()
	var font_size = 14
	
	# --- Вертикальні лінії та підписи RPM ---
	for rpm_step in range(0, engine.max_rpm + 1, 1000):
		# Розраховуємо X позицію
		var x = (float(rpm_step) / engine.max_rpm) * w
		
		# 1. Малюємо лінію сітки
		draw_line(pos + Vector2(x, 0), pos + Vector2(x, h), grid_color, 1.0)
		
		# 2. Малюємо текст під лінією
		var text = str(rpm_step)
		var text_size = default_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		
		# Позиція тексту: трохи нижче графіка (h + 20) і по центру лінії (x - half_width)
		var text_pos = pos + Vector2(x - text_size.x / 2, h + 20)
		
		# Малюємо тільки якщо текст не виходить за межі екрана зліва
		if text_pos.x > 0:
			draw_string(default_font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
	
	# Фінальна лінія справа
	draw_line(pos + Vector2(w, 0), pos + Vector2(w, h), grid_color, 1.0)

	# --- Горизонтальні лінії (Torque/HP) ---
	var panel = get_parent().get_parent().get_node_or_null("TqHp_panel")
	if panel:
		var steps = panel.get_child_count() - 1
		for i in range(steps + 1):
			var y = (h / float(steps)) * i
			draw_line(pos + Vector2(0, y), pos + Vector2(w, y), grid_color, 1.0)
