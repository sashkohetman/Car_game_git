extends Control



var torque_color =Color.CORNFLOWER_BLUE
var hp_color = Color.INDIAN_RED
var grid_color = Color(0.2, 0.2, 0.2, 1.0)

func _draw() -> void:
	var size := get_size()
	draw_grid(size)
	
	var torque_points = PackedVector2Array()
	
	for rpm in range(0, int(CarEngine.max_rpm) + 1, 100):
		var torque = calculate_torque_logic(rpm)
		var hp = 1
