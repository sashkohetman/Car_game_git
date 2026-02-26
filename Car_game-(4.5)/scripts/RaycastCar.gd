extends RigidBody3D
class_name RaycastCar

@export var wheels: Array[RaycastWheel]

@onready var total_wheels : int = wheels.size() 
@export var engine: CarEngine

@export_group("Car Physics")
@export var body_mass := 1500.0
@export var engine_braking := 0.1  # no gas = decelerate

@export_group("Engine & Transmission") 
@export var gear_ratios: Array[float] = [-3.5, 0, 3.5, 2.1, 1.45, 1.18, 0.94] # Eclipse 5-speed
@export var final_drive := 4.3
@export var current_gear : int = 1 
@export var drivetrain_efficiency := 1.0       # Differential ratio

var current_rpm := 0.0

@export_group("Aerodynamics")
@export var downforce_strength := 0.3
@export var air_resistance := 0.02
@export var aero_offset_z = -0.2
@export var drag_coeff = 0.0005

@export_group("Steering Settings")
@export var tire_max_turn_degrees := 30.0
@export var tire_turn_speed := 3.5
@export var steering_sensitivity_curve: Curve
@export var control_car := true

@export_group("Weight Distribution")
@export var static_center_of_mass_offset := Vector3(0, -0.5, 0)
@export var anti_roll_stiffness := 0.5 # Запобігає надмірному нахилу в поворотах
@export var dynamic_weight_shift := 0.2

@export_group("Braking System")
@export_range(0.0, 1.0) var brake_bias := 0.6 # 0.6 = stable, 0.4 = oversteer
@export var abs_enabled := true # isn't a thing for now


@export_group("Air Control")
@export var air_pitch_force := 2.5
@export var air_roll_force := 1.25

@export_group("Effects")
@export var skid_marks: Array[GPUParticles3D]
@export var skid_marks_threshold := 10.0 # sensetivity of producing skid marks

#Speedometer stuff
var timer = Timer
var speed_update_interval := 0.1
var time_since_last_speed_update := 0.0


var hand_break := false
var is_slipping := false
var current_speed_kmh := 0.0
var rpm_filter_speed := 0.0
signal speed_changed(new_speed: float)
var motor_input : float = 0.0

func _get_point_velocity(point: Vector3) -> Vector3:
	return linear_velocity + angular_velocity.cross(point - to_global(center_of_mass))


func _unhandled_input(event: InputEvent) -> void:
	if not control_car: return
	
	if event.is_action_pressed("shift up"):
		# Не даємо вийти за межі масиву (макс індекс 6)
		current_gear = clampi(current_gear + 1, 0, gear_ratios.size() - 1)
		
	if event.is_action_pressed("shift down"):
		# Не даємо впасти нижче 0
		current_gear = clampi(current_gear - 1, 0, gear_ratios.size() - 1)


func update_engine_rpm(delta: float):
	if not engine: return
	var local_velocity = global_basis.inverse() * linear_velocity
	var forward_speed = abs(local_velocity.z)
	
	# ПРЯМИЙ ДОСТУП: без "- 1"
	var gear_ratio = gear_ratios[current_gear] 
	
	var wheel_rpm = (forward_speed / 0.33) * 9.549
	var transmission_rpm = wheel_rpm * abs(gear_ratio) * final_drive
	
	var clutch_min_rpm = engine.idle_rpm + (motor_input * 1000.0)
	var target_rpm : float = max(transmission_rpm, clutch_min_rpm)
	engine.rpm = lerp(engine.rpm, clamp(target_rpm, engine.idle_rpm, engine.max_rpm), 0.15)

func calculate_engine_force() -> float:
	if not engine or current_gear == 1: return 0.0 # Нейтралка не дає сили
	
	# ПРЯМИЙ ДОСТУП: без "- 1"
	var total_ratio = gear_ratios[current_gear] * final_drive
	var torque = engine.get_torque_at_rpm(engine.rpm)
	
	# Сила буде від'ємною автоматично на задній передачі (ratio = -3.5)
	var wheel_force = (torque * total_ratio * drivetrain_efficiency) / 0.33
	return wheel_force * motor_input

		
func _physics_process(delta: float) -> void:
	# 1. Оновлення двигуна
	update_engine_rpm(delta)
	motor_input = Input.get_action_strength("accelerate")
	print(motor_input, " motor input")
	var brake_input = Input.get_action_strength("brake")
	current_speed_kmh = linear_velocity.length() * 3.6
	if wheels.is_empty(): return 

	# 2. Розрахунок сили двигуна
	var engine_power = calculate_engine_force()
	if engine.rpm >= engine.max_rpm - 50:
		engine_power = 0.0
	
	if hand_break:
		engine_power *= 0.3 # Те, що раніше робив final_accel

	# 3. Оновлення коліс
	var is_grounded = false
	for i in range(wheels.size()):
		var wheel = wheels[i]
		
		# Передаємо силу та гальма
		if wheel.is_motor:
			wheel.engine_force = engine_power / 2.0 # Припускаємо 2 ведучих колеса
		
		wheel.is_braking = brake_input > 0.1
		wheel.apply_wheel_physics(self)
		wheel.apply_steering(self, delta)
		
		if wheel.is_colliding():
			is_grounded = true
			# Логіка слідів (використовуємо індекс i замість id)
			if i < skid_marks.size():
				var wheel_v = _get_point_velocity(wheel.global_position)
				var lateral_velocity = wheel.global_basis.x.dot(wheel_v)
				var forward_v = wheel.global_basis.z.dot(wheel_v)
				
				var is_sliding = abs(lateral_velocity) > skid_marks_threshold
				var is_slipping = (hand_break and abs(forward_v) > 1.0)
				
				skid_marks[i].global_position = wheel.get_collision_point() + Vector3.UP * 0.01
				skid_marks[i].emitting = is_sliding or is_slipping
		elif i < skid_marks.size():
			skid_marks[i].emitting = false

	# 4. Аеродинаміка
	var speed_ms = linear_velocity.length()
	# Використовуйте дуже маленьке значення для air_resistance (наприклад, 0.001)
	var drag_force_mag = pow(speed_ms, 2) * air_resistance 
	var drag_vector = -linear_velocity.normalized() * drag_force_mag
	apply_central_force(drag_vector)

	# 5. Downforce та керування в повітрі
	if is_grounded:
		var forward_speed = global_basis.z.dot(linear_velocity)
		var downforce_mag = abs(forward_speed) * downforce_strength * mass
		var downforce_vec = -global_basis.y * downforce_mag
		# Застосовуємо силу в точці аеродинамічного зміщення (спойлер)
		apply_force(downforce_vec, global_basis * Vector3(0, 0, aero_offset_z))
	else:
		var pitch = Input.get_axis("brake", "accelerate") * air_pitch_force
		var roll = Input.get_axis("turn left", "turn right") * air_roll_force
		apply_torque(global_basis.x * pitch * mass * delta)
		apply_torque(global_basis.z * roll * mass * delta)

	# 6. UI та дебаг
	time_since_last_speed_update += delta
	if time_since_last_speed_update >= speed_update_interval:
		speed_changed.emit(current_speed_kmh)
		time_since_last_speed_update = 0.0
	# У RaycastCar.gd
	print("DEBUG: Engine Power = ", engine_power) # ДОДАЙТЕ ЦЕ
	for wheel in wheels:
		if wheel.is_motor:
			wheel.engine_force = engine_power / 2.0
