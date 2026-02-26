extends Node3D
class_name CarEngine

@export_group("Engine_parameters")
@export var max_rpm := 8600
@export var idle_rpm := 900.0
@export var bore := 8.6 ##cm
@export var stroke := 8.6 ##cm
@export var cyl_count := 4 ## AYY JAPANESE ENGINE!!!
@export var flywheel_inertia := 0.3
@export var base_friction := 2.1
@export var friction_coeff := 0.005
@export var engine_quallity := 1.25 ## based on the amt of valves (16)
@export var exhaust_multiplier := 1.1

@export_group("Cam Profile")
@export var base_VE := 1.5
@export var cam_base_peak := 6250
### Vtec
@export var Vtec := false
@export var low_cam := 3000.0
@export var cam_switch_rpm := 6000.0
@export var high_cam := 7000.0

@export_group("Turbo")
@export var is_turbo := true
@export var turbo_count := 1
@export var max_boost := 0.5
@export var spool_rpm := 4500
@export var best_boost_rpm := 6500
@export var full_boost_rpm := 8000
@export var boost_heat_coeff := 20

@export_group("intercooler")
@export var intercooler_kW := 4000.0
 
var current_boost := 0.0
var rpm := idle_rpm + 200
var idle_compensation = 0.0
var Current_VE : float
var boost:float
var dynamic_friction: float
# Called every frame. 'delta' is the elapsed time since the previous frame.

func get_ve_at_rpm(test_rpm: float) -> float:
	var peak_rpm = 6500.0
	# Робимо спад дуже плавним (ділимо на більшу величину)
	var dist = abs(test_rpm - peak_rpm) / (max_rpm * 1.5) 
	var res_ve = 1.2 - (dist * 0.3) # Тримаємо VE вище 0.9 майже до відсічки
	return clamp(res_ve, 0.8, 1.2)
	if Vtec:
		if test_rpm < cam_switch_rpm:
			dist = (test_rpm - low_cam) / (cam_switch_rpm - low_cam) if test_rpm > low_cam else (low_cam - test_rpm) / (low_cam - idle_rpm)
			res_ve = base_VE + (0.9 - base_VE) * (1.0 - pow(dist, 2))
		else:
			if test_rpm < high_cam:
				dist = (high_cam - test_rpm) / (high_cam - cam_switch_rpm)
				res_ve = 0.85 + (1.1 - 0.85) * (1.0 - pow(dist, 1.5))
			else:
				dist = (test_rpm - high_cam) / (max_rpm - high_cam)
				res_ve = 1.1 - (0.2 * pow(dist, 1.2))
	return clamp(res_ve, 0.1, 1.3) # Захист від від'ємних значень

func get_torque_at_rpm(test_rpm: float) -> float:
	var test_VE = get_ve_at_rpm(test_rpm)
	
	# --- TURBO LOGIC FIX ---
	var test_boost = 0.0
	if is_turbo:
		if test_rpm < spool_rpm:
			# Pre-spool: little to no boost
			test_boost = 0.0
		elif test_rpm < best_boost_rpm:
			# Spooling up: Linear or curved increase to max
			var spool_factor = (test_rpm - spool_rpm) / (best_boost_rpm - spool_rpm)
			test_boost = max_boost * pow(spool_factor, 2) # Exponential spool
		else:
			# At Peak: Hold boost steady!
			# Only taper slightly near absolute redline to protect engine
			test_boost = max_boost 
			
			# Optional: Slight taper only after 8000 RPM (Realism)
			if test_rpm > 8000:
				var drop = (test_rpm - 8000) / (max_rpm - 8000)
				test_boost -= drop * 0.1 # Lose only 0.1 bar at max RPM
		if test_rpm > best_boost_rpm:
			test_boost = max_boost
	# --- INTERCOOLER LOGIC ---
	# (Use max(0, ...) to prevent negative values if logic tweaks go wrong)
	var air_q = intercooler_kW / (intercooler_kW + (max(0.0, test_boost) * boost_heat_coeff))
	var eff_boost = max(0.0, test_boost) * air_q

	# --- TORQUE CALCULATION ---
	# Fixed Liter calculation to allow standard Inputs (Bore/Stroke in CM is fine)
	var disp_liters = (PI * pow(bore/2, 2) * stroke * cyl_count) / 1000.0
	var real_torque = disp_liters * test_VE * 105.0 * (1.0 + eff_boost)
	
	# ШТУЧНИЙ МНОЖНИК (Torque Hack)
	# real_torque — це чесні 200-400 Nm. 
	# Для Godot нам потрібно перетворити їх на 2000-4000 ігрових одиниць.
	var torque_multiplier = 1.0 
	
	return real_torque * engine_quallity * exhaust_multiplier
func _process(delta: float) -> void:
	var throttle = Input.get_action_strength("accelerate")
	
	# Отримуємо чистий момент
	var raw_torque = get_torque_at_rpm(rpm)
	
	# Розрахунок тертя (важливо: на високих обертах воно має бути значним)
	dynamic_friction = 0 #base_friction + (rpm * friction_coeff)
	
	# Idle Assist: не даємо впасти нижче idle_rpm
	if rpm < idle_rpm:
		var idle_boost = (idle_rpm - rpm) / 100.0
		throttle = max(throttle, idle_boost)
	
	# Розрахунок чистого моменту, що йде на маховик
	var net_torque = (raw_torque * throttle) - dynamic_friction
	
	# Прискорення обертів (Flywheel Physics)
	var rpm_accel = net_torque / flywheel_inertia * 3.0
	rpm += rpm_accel * delta * 2.0 # Коефіцієнт для швидкості відгуку
	
	# (Rev Limiter)
	if rpm > max_rpm:
		rpm = max_rpm
		
	rpm = max(rpm, 0) # Двигун не крутиться назад
	print(raw_torque, "Nm")
	print(throttle, "throttle")
	print(rpm, "rpm")
