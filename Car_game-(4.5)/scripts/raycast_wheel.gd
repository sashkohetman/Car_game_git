extends RayCast3D
class_name RaycastWheel

@export var engine : Node3D
@export var shapecast : ShapeCast3D
@export var offset_shapecast : float = 0.3

@export_group("Wheel properties")
@export var spring_strenght := 80000.0
@export var spring_damping := 12000.0
@export var max_spring_force : float = INF
@export var rest_dist := 0.10
@export var wheel_radius := 0.33
@export var over_extend := 0.05
@export var base_grip = 10.0
@export var slip_limit_multiplyer := 10.0

@export_group("Traction & Braking")
@export var z_traction := 0.05       # Coasting friction
@export var z_brake_traction := 2.0 # Braking power
@export var handbrake_force := 0.8   # Handbrake friction factor

@export_group("Stability Limits")
@export var slip_limit_low_speed : float = 2.0 
@export var slip_limit_high_speed : float = 1.2
@export var speed_threshold_kph : float = 330.0
@export var steer_bonus := 1.0       

@export_group("Motor & Steer")
@export var is_motor := false
@export var is_steer := false
@export var grip_curve : Curve

@export_group("Traction & Grip")
@export var lateral_stiffness := 1.0
@export var friction_coefficient := 1.0 

@export_group("Drift & Slip")
@export var skid_mark_threshold := 2.0 
@export var sliding_grip_multiplier := 0.6

@onready var Wheel_model: Node3D = get_child(0)

var engine_force := 0.0
var grip_factor := 0.0
var is_braking := false
var z_load := 0.0
var slip_ratio = 0.0
var slip_limit = 0.0
signal slip_updated(value)
func _ready() -> void:
	target_position.y = -(rest_dist + wheel_radius + over_extend)
	
	if shapecast:
		shapecast.target_position.x = -(rest_dist + over_extend) - offset_shapecast
		shapecast.add_exception(get_parent())
		shapecast.position.y = offset_shapecast

func apply_steering(car: RaycastCar, delta: float) -> void:
	if not is_steer or car.control_car == false: return
	
	var speed_ratio = clampf(abs(car.linear_velocity.length()), 0.0, 1.0)
	var curve_value = 1.0
	if car.steering_sensitivity_curve:
		curve_value = car.steering_sensitivity_curve.sample_baked(speed_ratio)
	
	var dynamic_max_steer = deg_to_rad(car.tire_max_turn_degrees * curve_value)
	var turn_input = Input.get_axis("turn right", "turn left")
	var target_rad = turn_input * dynamic_max_steer
	
	rotation.y = move_toward(rotation.y, target_rad, car.tire_turn_speed * delta)

func apply_wheel_physics(car: RaycastCar) -> void:
	force_raycast_update()
	if shapecast:
		shapecast.force_shapecast_update()
	
	target_position.y = -(rest_dist + wheel_radius + over_extend)
	var p_delta = get_physics_process_delta_time()
	
	var colliding := is_colliding()
	if shapecast and shapecast.is_colliding():
		colliding = true
	
	if not colliding:
		Wheel_model.position.y = move_toward(Wheel_model.position.y, -rest_dist, 5 * p_delta)
		return
	
	# --- 1. Отримання базових даних про контакт ---
	var contact : Vector3 = get_collision_point()
	var forward_dir := global_basis.z.normalized()
	var right_dir := global_basis.x.normalized()
	var tire_vel := car._get_point_velocity(contact)
	var forward_vel := forward_dir.dot(tire_vel)
	
	# Точка прикладання сили (важливо оголосити ТУТ)
	var force_pos : Vector3 = contact - car.global_position
	
	# --- 2. Підвіска (Suspension) ---
	var spring_len := maxf(0.0, global_position.distance_to(contact) - wheel_radius)
	var offset := rest_dist - spring_len
	
	# Візуальне зміщення колеса
	Wheel_model.position.y = move_toward(Wheel_model.position.y, -spring_len, 5 * p_delta)
	Wheel_model.rotate_x((forward_vel * p_delta) / wheel_radius)
	
	var compression = clampf(offset / rest_dist, 0.0, 1.0)
	var spring_force := spring_strenght * offset # Оголошуємо spring_force
	
	if compression > 0.8:
		var bump_stop_factor = pow(compression - 0.8, 2) * 10.0
		spring_force *= (1.0 + bump_stop_factor)

	var spring_damp_f := spring_damping * global_basis.y.dot(tire_vel)
	var suspension_force := maxf(0.0, spring_force - spring_damp_f)
	var y_force := suspension_force * get_collision_normal()
	
	var gravity_mag = abs(car.get_gravity().y)
	var weight_on_wheel = max(suspension_force / gravity_mag, (car.mass * gravity_mag) / (car.total_wheels * 2.0))
	var load_factor = clamp(suspension_force / spring_strenght, 1.0, 3.5)

	# --- 3. Lateral Friction (X) ---
	var steering_x_vel := right_dir.dot(tire_vel)
	grip_factor = absf(steering_x_vel / max(tire_vel.length(), 0.1))
	var x_traction = grip_curve.sample_baked(clamp(grip_factor, 0.0, 1.0))
	var speed_grip_mult = clamp(1.0 - (car.current_speed_kmh / 400.0), 0.5, 1.0)
	var x_force : Vector3 = -right_dir * steering_x_vel * x_traction * weight_on_wheel * lateral_stiffness * base_grip * speed_grip_mult

	## --- 4. Longitudinal Logic (Z) ---
	var wheel_surface_speed = forward_vel
	
	if is_motor:
		var gear_idx = clampi(car.current_gear - 1, 0, car.gear_ratios.size() - 1)
		var engine_wheel_rpm = car.engine.rpm / (car.gear_ratios[gear_idx] * car.final_drive)
		var desired_wheel_speed = (engine_wheel_rpm / 9.549) * wheel_radius
		wheel_surface_speed = lerp(forward_vel, desired_wheel_speed, car.motor_input)

	# ВИНОСИМО РОЗРАХУНОК СЛІПУ СЮДИ (поза if is_motor)
	var abs_vel = max(abs(forward_vel), 0.5) # Мінімальна швидкість для розрахунку
	slip_ratio = (wheel_surface_speed - forward_vel) / abs_vel
	
	# Якщо ми гальмуємо, slip_ratio має стати від'ємним автоматично
	if is_braking:
		# Спрощена логіка сліпу при гальмуванні для дебагу
		slip_ratio = -clamp(abs(forward_vel) * 0.1, 0.0, 1.0)
	var lookup_slip = clamp(abs(slip_ratio), 0.0, 1.0)
	var traction_factor = grip_curve.sample_baked(lookup_slip)
	
	# Захист: якщо буксуємо, даємо хоча б 60% зачепу
	if lookup_slip > 0.8 and traction_factor < 0.6:
		traction_factor = 0.6 

	z_load = engine_force * traction_factor

	# Опір кочення (мінімальний)
	var rolling_resistance = sign(forward_vel) * (car.mass * 0.01)
	if abs(forward_vel) < 0.2: rolling_resistance = 0.0
	z_load -= rolling_resistance

	if is_braking:
		z_load -= sign(forward_vel) * z_brake_traction * weight_on_wheel
	
	# --- 5. Traction Circle High-Speed Fix ---
	var total_force_vec = Vector2(x_force.length(), z_load)
	
	# На великій швидкості ми "приклеюємо" машину до дороги сильніше
	var high_speed_grip = clamp(car.current_speed_kmh / 200.0, 1.0, 1.5)
	var max_tire_force = weight_on_wheel * friction_coefficient * 5.0 * high_speed_grip
	
	if total_force_vec.length() > max_tire_force and total_force_vec.length() > 0:
		var ratio = max_tire_force / total_force_vec.length()
		x_force *= ratio
		# Дозволяємо поздовжній силі ігнорувати обрізку на 90%, щоб боротися з повітрям
		z_load *= max(ratio, 0.9)
	
	# ОГОЛОШЕННЯ ТУТ (виправлення помилки Identifier)
	var z_force_vec: Vector3 = forward_dir * z_load
	
	
	slip_updated.emit(slip_ratio)
	print(slip_ratio, " slip limit")
	# --- 6. Apply Final Forces ---
	car.apply_force(y_force, force_pos)
	car.apply_force(x_force, force_pos)
	car.apply_force(z_force_vec, force_pos)
