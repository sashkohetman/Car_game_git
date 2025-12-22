extends RayCast3D
class_name RaycastWheel

@export var shapecast : ShapeCast3D
@export var offset_shapecast : float = 0.3

@export_group("Wheel properties")
@export var spring_strenght := 100000.0
@export var spring_damping := 12000.0
@export var max_spring_force : float = INF
@export var rest_dist := 0.10
@export var wheel_radius := 0.33
@export var over_extend := 0.05
@export var base_grip = 1.0
@export var slip_limit_multiplyer := 2.0

@export_group("Traction & Braking")
@export var z_traction := 0.05       # Coasting friction
@export var z_brake_traction := 0.45 # Braking power
@export var handbrake_force := 0.8   # Handbrake friction factor

@export_group("Stability Limits")
@export var slip_limit_low_speed : float = 2.0 
@export var slip_limit_high_speed : float = 1.2
@export var speed_threshold_kph : float = 250.0 
@export var steer_bonus := 2.0       

@export_group("Motor & Steer")
@export var is_motor := false
@export var is_steer := false
@export var grip_curve : Curve
@export var accel_curve : Curve

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

func _ready() -> void:
	target_position.y = -(rest_dist + wheel_radius + over_extend)
	
	if shapecast:
		shapecast.target_position.x = -(rest_dist + over_extend) - offset_shapecast
		shapecast.add_exception(get_parent())
		shapecast.position.y = offset_shapecast

func apply_steering(car: RaycastCar, delta: float) -> void:
	if not is_steer: return
	
	var speed_ratio = clampf(abs(car.linear_velocity.length()) / car.max_speed, 0.0, 1.0)
	var curve_value = 1.0
	if car.steering_sensitivity_curve:
		curve_value = car.steering_sensitivity_curve.sample_baked(speed_ratio)
	
	var dynamic_max_steer = deg_to_rad(car.tire_max_turn_degrees * curve_value)
	var turn_input = Input.get_axis("turn right", "turn left")
	var target_rad = turn_input * dynamic_max_steer
	
	rotation.y = move_toward(rotation.y, target_rad, car.tire_turn_speed * delta)

# MAIN PHYSICS FUNCTION
func apply_wheel_physics(car: RaycastCar) -> void:
	# 0. Setup
	force_raycast_update()
	if shapecast:
		shapecast.force_shapecast_update()
	
	target_position.y = -(rest_dist + wheel_radius + over_extend)
	var p_delta = get_physics_process_delta_time() # FIXED: Delta definition
	
	var colliding := is_colliding()
	if shapecast and shapecast.is_colliding():
		colliding = true
	
	if not colliding:
		Wheel_model.position.y = move_toward(Wheel_model.position.y, -rest_dist, 5 * p_delta)
		return
	
	var contact : Vector3 = get_collision_point()
	var forward_dir := global_basis.z.normalized()
	var right_dir := global_basis.x.normalized()
	var tire_vel := car._get_point_velocity(contact)
	var speed = forward_dir.dot(car.linear_velocity)
	
	# 1. Suspension & Visuals
	Wheel_model.rotate_x((speed * p_delta) / wheel_radius)
	
	var spring_len := maxf(0.0, global_position.distance_to(contact) - wheel_radius)
	var offset := rest_dist - spring_len
	Wheel_model.position.y = move_toward(Wheel_model.position.y, -spring_len, 5 * p_delta)
	
	var force_pos : Vector3 = contact - car.global_position
	
	var compression = clampf(offset / rest_dist, 0.0, 1.0)
	var spring_force := spring_strenght * offset
	
	if compression > 0.8:
		var bump_stop_factor = pow(compression - 0.8, 2) * 10.0
		spring_force *= (1.0 + bump_stop_factor)

	var spring_damp_f := spring_damping * global_basis.y.dot(tire_vel)
	var suspension_force := maxf(0.0, spring_force - spring_damp_f)
	var y_force := suspension_force * get_collision_normal()
	
	if offset < rest_dist * 0.1: 
		var shock_force = car.mass * 2.0 
		car.apply_central_impulse(global_basis.y * shock_force * p_delta)
	
	var gravity_mag = abs(car.get_gravity().y)
	var weight_on_wheel = suspension_force / gravity_mag if colliding else 0.0
	weight_on_wheel = max(weight_on_wheel, (car.mass * gravity_mag) / (car.total_wheels * 2.0))

	# 2. Acceleration (Z)
	if is_motor and car.motor_input:
		var speed_ratio: float = abs(speed) / car.max_speed
		var ac: float = accel_curve.sample_baked(speed_ratio)
		
		# Handbrake Power Cut (Applied directly here)
		var accel_mult = 1.0
		if car.hand_break: accel_mult = 0.3
			
		var accel_force: Vector3 = forward_dir * car.acceleration * car.motor_input * ac * accel_mult
		car.apply_force(accel_force, force_pos)

	# 3. Lateral Friction (X - Turning)
	var steering_x_vel := right_dir.dot(tire_vel)
	grip_factor = absf(steering_x_vel / max(tire_vel.length(), 0.1))
	var x_traction := grip_curve.sample_baked(grip_factor)
	
	var speed_kph = car.linear_velocity.length() * 3.6
	var dynamic_limit_factor = remap(clamp(speed_kph, 0, 200), 0, 200, slip_limit_low_speed, slip_limit_high_speed)
	var slip_limit = weight_on_wheel * dynamic_limit_factor * slip_limit_multiplyer
	
	var x_force : Vector3 = -right_dir * steering_x_vel * x_traction * weight_on_wheel * lateral_stiffness * base_grip

	if x_force.length() > slip_limit:
		x_force = x_force.limit_length(slip_limit)

	# 4. Longitudinal Friction (Z - Braking & Handbrake)
	var current_z_friction = z_traction
	if is_braking:
		var final_brake_force = z_brake_traction
		if is_steer:
			final_brake_force *= car.brake_bias
		else:
			final_brake_force *= (1.0 - car.brake_bias)
		current_z_friction = final_brake_force
	
	var friction_mag = speed * current_z_friction * weight_on_wheel
	
	# --- HYBRID HANDBRAKE SYSTEM (The Fix) ---
	if car.hand_break and not is_steer:
		# A. Stopping Power (Linear)
		# Mix of constant drag + slight speed dependent friction
		var hb_stop_power = (car.mass * 0.1) + (abs(speed) * weight_on_wheel * 0.05)
		friction_mag = sign(speed) * hb_stop_power
		
		# B. Drift Initiation (Lateral)
		# High grip when straight, Low grip when turning
		var side_slide_factor = remap(clamp(abs(steering_x_vel), 0.0, 5.0), 0.0, 5.0, 0.4, 0.1)
		x_force *= side_slide_factor
		
		# C. Safety Momentum Clamp (Prevent instant stops)
		var momentum_limit = (abs(speed) * car.mass * p_delta) * 2.0
		friction_mag = clampf(friction_mag, -momentum_limit, momentum_limit)
	# ----------------------------------------
	
	# --- DYNAMIC TRACTION CIRCLE (High Speed Cornering) ---
	var grip_boost = remap(clamp(speed_kph, 50, 200), 50, 200, 1.0, 2.5)
	var max_tire_force = weight_on_wheel * friction_coefficient * 1.5 * grip_boost
	
	var total_force_vec = Vector2(x_force.length(), friction_mag)
	if total_force_vec.length() > max_tire_force:
		var reduction_factor = max_tire_force / total_force_vec.length()
		if is_steer:
			# Prioritize steering for front wheels
			x_force *= max(reduction_factor, 0.8)
			friction_mag *= reduction_factor * 0.5
		else:
			friction_mag *= reduction_factor
			x_force *= reduction_factor
	# ------------------------------------------------------

	var z_force: Vector3 = -forward_dir * friction_mag

	# 5. Apply Final Forces
	car.apply_force(y_force, force_pos)
	car.apply_force(x_force, force_pos)
	car.apply_force(z_force, force_pos)
