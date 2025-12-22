extends Camera3D

@export var min_distance := 4.0
@export var max_distance := 7.0 
@export var height := 2.5
@export var camera_sensetivity = 0.002
@export var speed_zoom_factor := 0.05 

@onready var target : Node3D = get_parent()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		top_level = false
		get_parent().rotate_y(-event.relative.x * camera_sensetivity)
		top_level = true

func _ready() -> void:
	await get_tree().physics_frame
	top_level = true
	
	# ЗМІНА: використовуємо -target.global_basis.z, бо Z+ це перед
	var back_direction = -target.global_basis.z 
	
	global_position = target.global_position + (back_direction * min_distance)
	global_position.y += height
	look_at(target.global_position, Vector3.UP)

func _physics_process(delta: float) -> void:
	# 1. Отримуємо швидкість
	var current_speed = 0.0
	if target is RigidBody3D:
		current_speed = target.linear_velocity.length()

	# 2. Розраховуємо ідеальну дистанцію (обмежуємо clamp)
	var target_dist = clamp(min_distance + (current_speed * speed_zoom_factor), min_distance, max_distance)

	# 3. Визначаємо точку, де камера МАЄ бути (завжди за багажником на target_dist)
	# Z+ це перед, тому -target.global_basis.z це стабільно зад
	var back_direction = -target.global_basis.z
	var desired_position = target.global_position + (back_direction * target_dist)
	desired_position.y += height

	# 4. Плавний догін (LERP) тільки для фінальної позиції
	# 5.0 — це швидкість реакції. Якщо камера занадто повільна, постав 10.0
	global_position = global_position.lerp(desired_position, delta * 5.0)

	# 5. Погляд та FOV
	look_at(target.global_position, Vector3.UP)
	fov = lerp(fov, 75.0 + (current_speed * 0.2), delta * 2.0)
