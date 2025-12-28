extends Node3D
class_name CarEngine

@export_group("Engine_parameters")
@export var max_rpm := 9000
@export var idle_rpm := 1000.0
@export var bore := 8.6 ##cm
@export var stroke := 8.6 ##cm
@export var cyl_count := 4 ## AYY JAPANESE ENGINE!!!
@export var flywheel_inertia := 0.1
@export var base_friction := 10.1
@export var friction_coeff := 0.1
@export var engine_quallity := 1.1 ## based on the amt of valves (16)
@export var exhaust_multiplier := 1.05

@export_group("Cam Profile")
@export var base_VE := 0.5
@export var cam_base_peak := 6250
### Vtec
@export var Vtec := true
@export var low_cam := 4000.0
@export var cam_switch_rpm := 5500.0
@export var high_cam := 7500.0

@export_group("Turbo")
@export var is_turbo := true
@export var turbo_count := 1
@export var max_boost := 1.0
@export var spool_rpm := 4500
@export var best_boost_rpm := 6500
@export var full_boost_rpm := 9000
@export var boost_heat_coeff := 20

@export_group("intercooler")
@export var intercooler_kW := 4000.0
 
var current_boost := 0.0
var rpm := idle_rpm + 100
var idle_compensation = 0.0
var Current_VE : float
var boost:float
var dynamic_friction: float
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	var throttle := Input.get_action_strength("accelerate")
	
	
	### Turbo ###
	if rpm >= spool_rpm:
		var distance = 0.0
		if rpm < best_boost_rpm:
			distance = (best_boost_rpm - rpm) / (best_boost_rpm - spool_rpm)
		elif rpm >= best_boost_rpm:
			distance = (rpm - best_boost_rpm) / (full_boost_rpm - best_boost_rpm) 
		boost = max_boost - (distance ** 2 * 0.6)
	
	var heat_from_turbo := boost * boost_heat_coeff 
	var air_quality = intercooler_kW / (intercooler_kW + heat_from_turbo)
	var effective_boost = boost * (intercooler_kW / (intercooler_kW + air_quality))

	### Cam Profile (I'm that complex)
	if Vtec == false:
		var distance = 0.0
		if rpm < cam_base_peak:
			distance = (cam_base_peak - rpm) / (cam_base_peak - idle_rpm)
		elif rpm >= cam_base_peak:
			distance = (rpm - cam_base_peak) / (max_rpm - cam_base_peak) 
		Current_VE = base_VE + (1.0 - base_VE) * (1.0 - distance ** 2)
	if Vtec:
		var distance = 0.0
		if rpm < cam_switch_rpm:
			if rpm < low_cam:
				distance = (low_cam - rpm) / (low_cam - idle_rpm)
			elif rpm >= low_cam:
				distance = (rpm - low_cam) / (max_rpm - low_cam) 
		if rpm >= cam_switch_rpm:
			if rpm < high_cam:
				distance = (high_cam - rpm) / (high_cam - idle_rpm)
			elif rpm >= high_cam:
				distance = (rpm - high_cam) / (max_rpm - high_cam) 
		Current_VE = base_VE + (1.0 - base_VE) * (1.0 - distance ** 2)
	### Friction ###
	dynamic_friction = base_friction + (rpm * friction_coeff)
		
	###  Torque ###
	var Displacement := PI * (bore/2) ** 2 * stroke * cyl_count
	var torque :float= Displacement  * (Current_VE) * (1.0 + effective_boost)
	
	### idle fuel compensation!!!!! ###
	if rpm <= idle_rpm and not Input.is_action_pressed("accelerate"):
		if rpm <= (idle_rpm - 10):
			idle_compensation += 0.01
		throttle = clamp(throttle + idle_compensation, 0.0, 1.0)
	if rpm >= max_rpm:
		rpm = max_rpm
	rpm += ((torque  * throttle - dynamic_friction) / flywheel_inertia) * delta

	print(rpm, "rpm")
	print(torque, "tQ")
	print(effective_boost, "boost")
	print(Current_VE, "VE")
