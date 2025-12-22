extends RayCast3D
class_name RaycastWheel

@export var shapecast : ShapeCast3D
@export var offset_shapecast : float = 0.3

@export_group("Wheel properties")
@export var spring_strenght := 90000.0
@export var spring_damping := 9000.0
@export var max_spring_force : float = INF
@export var rest_dist := 0.2
@export var wheel_radius := 0.33
@export var over_extend := 0.05

@export_group("Traction & Braking")
@export var z_traction := 0.05       # Тертя кочення (накатом)
@export var z_brake_traction := 0.45 # Сила гальм
@export var handbrake_force := 0.8   # Наскільки сильно ручник блокує колесо

@export_group("Stability Limits")
@export var slip_limit_low_speed : float = 2.0 
@export var slip_limit_high_speed : float = 1.2
@export var speed_threshold_kph : float = 250.0 # Швидкість для розрахунку ліміту
@export var steer_bonus := 2.0       # Додатковий зацеп для передніх коліс

@export_group("Motor & Steer")
@export var is_motor := false
@export var is_steer := false
@export var grip_curve : Curve
@export var accel_curve : Curve

@export_group("Traction & Grip")
@export var lateral_stiffness := 4.0
# Коефіцієнт зчеплення (1.0 - асфальт, 0.3 - лід)
@export var friction_coefficient := 1.0 

@export_group("Drift & Slip")
# Швидкість (м/с), при якій починають малюватися сліди
@export var skid_mark_threshold := 2.5 
# Наскільки сильно падає зчеплення, коли колесо повністю зірвалося (0.1 - 1.0)
@export var sliding_grip_multiplier := 0.6 

@export_group("Motor & Differential")
# Емуляція заблокованого диференціалу (якщо true, колесо менше буксує)
@export var limited_slip_differential := true
@onready var Wheel_model: Node3D = get_child(0)


var engine_force := 0.0
var grip_factor := 0.0
var is_braking := false


func _ready() -> void:
	target_position.y = -(rest_dist + wheel_radius + over_extend)
	
	if shapecast:
		shapecast.target_position.x = -(rest_dist + over_extend) - offset_shapecast
		shapecast.add_exception(get_parent())
		shapecast.position.y = offset_shapecast

func apply_steering(car: RaycastCar, delta: float) -> void:
	if not is_steer: return
	
	# 1. Рахуємо відношення швидкості (0.0 до 1.0)
	var speed_ratio = clampf(abs(car.linear_velocity.length()) / car.max_speed, 0.0, 1.0)
	
	# 2. Беремо значення з графіка машини
	var curve_value = 1.0
	if car.steering_sensitivity_curve:
		curve_value = car.steering_sensitivity_curve.sample_baked(speed_ratio)
	
	# 3. Рахуємо фінальний кут
	var dynamic_max_steer = deg_to_rad(car.tire_max_turn_degrees * curve_value)
	
	# Отримуємо ввід
	var turn_input = Input.get_axis("turn right", "turn left")
	var target_rad = turn_input * dynamic_max_steer
	
	# Плавне повертання моделі та вектора сили
	rotation.y = move_toward(rotation.y, target_rad, car.tire_turn_speed * delta)
	
func apply_wheel_physics(car: RaycastCar) -> void:
	force_raycast_update()
	if shapecast:
		shapecast.force_shapecast_update()
		
	target_position.y = -(rest_dist + wheel_radius + over_extend)
	
	var colliding := is_colliding()
	if shapecast and shapecast.is_colliding():
		colliding = true
	
	if not colliding:
		Wheel_model.position.y = move_toward(Wheel_model.position.y, -rest_dist, 5 * get_physics_process_delta_time())
		return
	
	var contact : Vector3 = get_collision_point()
	var forward_dir := global_basis.z.normalized()
	var right_dir := global_basis.x.normalized()
	var tire_vel := car._get_point_velocity(contact)
	
	## 1. Візуальне обертання та підвіска
	var speed = forward_dir.dot(car.linear_velocity)
	Wheel_model.rotate_x((speed * get_physics_process_delta_time()) / wheel_radius)
	
	var spring_len := maxf(0.0, global_position.distance_to(contact) - wheel_radius)
	var offset := rest_dist - spring_len
	Wheel_model.position.y = move_toward(Wheel_model.position.y, -spring_len, 5 * get_physics_process_delta_time())
	
	var force_pos : Vector3 = contact - car.global_position
	
	## 2. Сила підвіски (Y)
	var spring_force := spring_strenght * offset
	var spring_damp_f := spring_damping * global_basis.y.dot(tire_vel)
	var suspension_force := clampf(spring_force - spring_damp_f, -max_spring_force, max_spring_force)
	var y_force := suspension_force * get_collision_normal()

	## 3. Acceleration (Z - розгін)
	if is_motor and car.motor_input:
		var speed_ratio: float = abs(speed) / car.max_speed
		# ВИПРАВЛЕНО: прибираємо "car.", бо тепер accel_curve належить самому колесу
		var ac: float = accel_curve.sample_baked(speed_ratio) 
		var accel_force: Vector3 = forward_dir * car.acceleration * car.motor_input * ac
		car.apply_force(accel_force, force_pos)

## 4. Lateral Friction (Кермування та Занос)
	var steering_x_vel := right_dir.dot(tire_vel)
	grip_factor = absf(steering_x_vel / max(tire_vel.length(), 0.1))
	var x_traction := grip_curve.sample_baked(grip_factor)

	var gravity_mag = abs(car.get_gravity().y)
	
	# РЕАЛЬНА ВАГА: використовуємо силу підвіски замість статичної маси
	# Це дозволить колесу мати більше зчеплення, коли на нього тисне вага в повороті
	var weight_on_wheel = suspension_force / gravity_mag if colliding else 0.0
	# Захист від занадто малих значень (мінімальне зчеплення)
	weight_on_wheel = max(weight_on_wheel, (car.mass * gravity_mag) / (car.total_wheels * 2.0))
	
	# steer_bonus для передніх коліс тепер впливає сильніше
	var steer_bonus = 2.5 if is_steer else 1.0 
	
	# Динамічний ліміт: даємо переднім колесам більший ліміт, щоб вони не зривалися в занос завчасно
	# 1. Розширюємо поріг швидкості до 200, щоб ліміт не падав занадто різко
	var speed_kph = car.linear_velocity.length() * 3.6
	
	# dynamic_limit_factor тепер плавно падає, але не в нуль
	var dynamic_limit_factor = remap(clamp(speed_kph, 0, 200), 0, 200, slip_limit_low_speed, slip_limit_high_speed)
	
	# 2. Додаємо "мінімальне зчеплення", нижче якого сила не впаде навіть на 300 км/год
	var final_slip_limit_factor = max(dynamic_limit_factor * (1.5 if is_steer else 1.0), 0.6)
	
	# 1. Піднімаємо базовий множник (lateral_stiffness тепер буде працювати ефективніше)
	var base_grip = 2.5 # Було 1.5-1.8, піднімаємо до 2.5
	var x_force : Vector3 = -right_dir * steering_x_vel * x_traction * weight_on_wheel * lateral_stiffness * base_grip

	# 2. Робимо ліміт ковзання вищим (щоб шини пізніше зривалися в занос)
	var slip_limit = weight_on_wheel * dynamic_limit_factor * 2.0 # Додали множник 2.0
	# Передні колеса мають вищий ліміт зриву, щоб "тягнути" машину
	if x_force.length() > slip_limit:
		x_force = x_force.limit_length(slip_limit)

	## 5. Longitudinal Friction (Гальма та зупинка)
	var current_z_friction = z_traction
	if is_braking:
		current_z_friction = z_brake_traction
		# У apply_wheel_physics колеса
	var final_brake_force = z_brake_traction
	if is_steer:
		final_brake_force *= car.brake_bias      # Передні
	else:
		final_brake_force *= (1.0 - car.brake_bias) # Задні

	if is_braking:
		current_z_friction = final_brake_force
	
	var friction_mag = speed * current_z_friction * weight_on_wheel
	var z_force: Vector3 = -forward_dir * friction_mag

	# --- ДОДАНО: Жорстка зупинка ---
	# Якщо ми тиснемо гальма і швидкість менша за 1.5 м/с ( ~5 км/год)
	if is_braking and abs(speed) < 1.5:
		# Прямо сповільнюємо лінійну швидкість машини до нуля
		car.linear_velocity = car.linear_velocity.lerp(Vector3.ZERO, 0.2)
		z_force = Vector3.ZERO # Вимикаємо фізичну силу, щоб не було дрижання
	# ------------------------------

	# Ручник теж допомагає зупинитися до нуля
	if car.hand_break:
		if abs(speed) < 1.5:
			car.linear_velocity = car.linear_velocity.lerp(Vector3.ZERO, 0.2)
		else:
			var brake_drag = -forward_dir * speed * 0.5 * car.mass
			car.apply_central_force(brake_drag)

	# Застосування сил
	car.apply_force(y_force, force_pos)
	car.apply_force(x_force, force_pos)
	car.apply_force(z_force, force_pos)
