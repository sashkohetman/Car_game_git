extends RigidBody3D
class_name RaycastCar

@export var wheels: Array[RaycastWheel]

@onready var total_wheels : int = wheels.size() 

@export_group("Car Physics")
@export var acceleration = 20000.0
@export var max_speed := 200.0
@export var body_mass := 1500.0
@export var engine_braking := 0.1  # no gas = decelerate

@export_group("Engine & Transmission")
@export var engine_torque_curve: Curve       # Torque curve (x: RPM/MaxRPM, y: Torque)
@export var max_torque := 450.0              # Peak torque in Nm
@export var max_rpm := 7000.0                # Redline
@export var idle_rpm := 900.0                # RPM when not pressing gas
@export var gear_ratios: Array[float] = [3.4, 2.1, 1.45, 1.1, 0.9] # Eclipse 5-speed
@export var final_drive := 4.1               # Differential ratio

var current_rpm := 0.0
var current_gear := 1 # 0 = Reverse, 1-5 = Forward

@export_group("Aerodynamics")
@export var downforce_strength := 0.3
@export var air_resistance := 0.02
@export var aero_offset_z = -0.2

@export_group("Steering Settings")
@export var tire_max_turn_degrees := 30.0
@export var tire_turn_speed := 3.0
@export var steering_sensitivity_curve: Curve

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
	if event.is_action_pressed("shift_up"):
		current_gear = clampi(current_gear + 1, 1, gear_ratios.size())
	if event.is_action_pressed("shift_down"):
		current_gear = clampi(current_gear - 1, 1, gear_ratios.size())

func calculate_engine_force() -> float:
	if wheels.is_empty(): return 0.0
	
	# --- SAFETY CHECK ---
	if not engine_torque_curve:
		# If curve is missing, return a basic value or log a warning
		# push_warning("Engine Torque Curve is missing!")
		return motor_input * max_torque * 5.0 
	
	# ... rest of the code ...
	var rpm_normalized = current_rpm / max_rpm
	var torque_factor = engine_torque_curve.sample_baked(rpm_normalized)
	
	# Total force calculation
	var wheel_force = (motor_input * max_torque * torque_factor * gear_ratios[current_gear - 1] * final_drive) / 0.33
	
	return wheel_force
	
		
func _physics_process(delta: float) -> void:
	current_speed_kmh = linear_velocity.length() * 3.6
	
	if wheels.is_empty(): return 

	# 1. Dynamic center of mass shift
	if motor_input > 0:
		center_of_mass.z = -dynamic_weight_shift 
	else:
		center_of_mass.z = 0.0
	
	# 2. Wheels update
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

	# 3. Aeordynamics
	var air_drag_force = -linear_velocity.normalized() * linear_velocity.length_squared() * air_resistance
	apply_central_force(air_drag_force)

	# 4. Force, that depends if the wheel collides
	var forward_speed = global_basis.z.dot(linear_velocity) # Оголошуємо ТУТ, щоб бачили всі блоки нижче
	var final_accel = acceleration

	if hand_break:
		# Reduce engine power by 70% if handbrake is on
		final_accel *= 0.3 

	# using global_basis.y, to press the car down
	var down_direction = -global_basis.y 

	if is_grounded:
		var downforce_mag = abs(forward_speed) * downforce_strength * mass
		var downforce_vec = -global_basis.y * downforce_mag
	
	# Instead of apply_central_force, applying the downforce slightly behind the center of mass (for example, -0.5 meters)
		var aero_offset = Vector3(0, 0, -0.5) # Minus, because Z+ is da hood , meaning that Z- is the spoiler axis
		apply_force(downforce_vec, global_basis * Vector3(0, 0, aero_offset_z))
	else:
		# air controlls
		var pitch = Input.get_axis("brake", "accelerate") * air_pitch_force
		var roll = Input.get_axis("turn left", "turn right") * air_roll_force
		apply_torque(global_basis.x * pitch * mass)
		apply_torque(global_basis.z * roll * mass)
	
	## 5. Engine
	var engine_power = calculate_engine_force()

	for wheel in wheels:
		# If AWD, split power 50/50. If FWD, give only to front wheels.
		if wheel.is_motor:
			wheel.engine_force = engine_power / 2.0 # Splitting for AWD

	# 5. Ui timer
	time_since_last_speed_update += delta
	if time_since_last_speed_update >= speed_update_interval:
		speed_changed.emit(current_speed_kmh)
		get_tree().call_group("ui_layer", "update_speed_display", current_speed_kmh)
		time_since_last_speed_update = 0.0
