extends RigidBody3D
class_name RaycastCar

@export var wheels: Array[RaycastWheel]

# Додаємо це назад! Саме цього рядка не вистачало для помилки
@onready var total_wheels : int = wheels.size() 

@export_group("Car Physics")
@export var acceleration = 20000.0
@export var max_speed := 200.0
@export var body_mass := 1500.0
@export var engine_braking := 0.1  # Наскільки сильно машина сама гальмує без газу

@export_group("Aerodynamics")
@export var downforce_strength := 1.2
@export var air_resistance := 0.02

@export_group("Steering Settings")
@export var tire_max_turn_degrees := 30.0
@export var tire_turn_speed := 3.0
@export var steering_sensitivity_curve: Curve

@export_group("Weight Distribution")
@export var static_center_of_mass_offset := Vector3(0, -0.5, 0)
@export var anti_roll_stiffness := 0.5 # Запобігає надмірному нахилу в поворотах
@export var dynamic_weight_shift := 0.2 

@export_group("Braking System")
@export_range(0.0, 1.0) var brake_bias := 0.6 # 0.6 = стабільність, 0.4 = надлишкова повертаність
@export var abs_enabled := true # Якщо хочеш, щоб колеса не блокувалися повністю


@export_group("Air Control")
@export var air_pitch_force := 5.0
@export var air_roll_force := 2.5

@export_group("Effects")
@export var skid_marks: Array[GPUParticles3D]
@export var skid_marks_threshold := 10.0

var timer = Timer
var speed_update_interval := 0.1
var time_since_last_speed_update := 0.0

var motor_input := 0 
var hand_break := false
var is_slipping := false
var current_speed_kmh := 0.0
signal speed_changed(new_speed: float)


func _get_point_velocity(point: Vector3) -> Vector3:
	return linear_velocity + angular_velocity.cross(point - to_global(center_of_mass))

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("handbreak"):
		hand_break = true
		is_slipping = true
	elif event.is_action_released("handbreak"):
		hand_break = false
	if event.is_action_pressed("accelerate"):
		motor_input = 1
	elif event.is_action_released("accelerate"):
		motor_input = 0
	#if event.is_action_pressed("decelerate"):
		#motor_input = -1
	#elif event.is_action_released("decelerate"):
		#motor_input = 0

		

	
		
func _physics_process(delta: float) -> void:
	current_speed_kmh = linear_velocity.length() * 3.6
	
	if wheels.is_empty(): return 

	# 1. Динамічне зміщення центру мас
	if motor_input > 0:
		center_of_mass.z = -dynamic_weight_shift 
	else:
		center_of_mass.z = 0.0
	
	# 2. Оновлення коліс
	var is_grounded = false
	var id := 0
	for wheel in wheels:
		wheel.apply_wheel_physics(self)
		wheel.apply_steering(self, delta)
		wheel.is_braking = Input.is_action_pressed("brake")
		
		if wheel.is_colliding():
			is_grounded = true
			
			# Сліди
			var wheel_v = _get_point_velocity(wheel.global_position)
			var lateral_velocity = wheel.global_basis.x.dot(wheel_v)
			var forward_v = wheel.global_basis.z.dot(wheel_v)
			
			var is_sliding_sideways = abs(lateral_velocity) > skid_marks_threshold
			var is_slipping_forward = (hand_break and abs(forward_v) > 1.0) 

			if id < skid_marks.size():
				skid_marks[id].global_position = wheel.get_collision_point() + Vector3.UP * 0.01
				skid_marks[id].emitting = is_sliding_sideways or is_slipping_forward
		else:
			if id < skid_marks.size():
				skid_marks[id].emitting = false
		id += 1 

	# 3. Аеродинаміка (опір повітря) - працює завжди
	var air_drag_force = -linear_velocity.normalized() * linear_velocity.length_squared() * air_resistance
	apply_central_force(air_drag_force)

	# 4. Сили, що залежать від контакту з землею
	var forward_speed = global_basis.z.dot(linear_velocity) # Оголошуємо ТУТ, щоб бачили всі блоки нижче

	if is_grounded:
		# Притискна сила
		var downforce = -global_basis.y * abs(forward_speed) * downforce_strength * mass
		apply_central_force(downforce)
		
		# Гальмування двигуном
		if motor_input == 0:
			var engine_brake_force = -global_basis.z * forward_speed * engine_braking * mass
			apply_central_force(engine_brake_force)
	else:
		# Керування в повітрі
		var pitch = Input.get_axis("accelerate", "brake") * air_pitch_force
		var roll = Input.get_axis("turn left", "turn right") * air_roll_force
		apply_torque(global_basis.x * pitch * mass)
		apply_torque(global_basis.z * roll * mass)

	# 5. UI Таймер
	time_since_last_speed_update += delta
	if time_since_last_speed_update >= speed_update_interval:
		speed_changed.emit(current_speed_kmh)
		get_tree().call_group("ui_layer", "update_speed_display", current_speed_kmh)
		time_since_last_speed_update = 0.0
