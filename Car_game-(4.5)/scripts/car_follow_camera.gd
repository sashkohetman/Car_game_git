extends Camera3D


@export var min_distance := 4.0
@export var max_distance := 7.0 # Збільшив для більшого ефекту швидкості
@export var height := 2.5
@export var camera_sensetivity = 0.002
@export var speed_zoom_factor := 0.05 # Наскільки сильно швидкість впливає на зум
@onready var target : Node3D = get_parent()



func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		top_level = false
		get_parent().rotate_y(-event.relative.x * camera_sensetivity)
		top_level = true

func _ready() -> void:
# Чекаємо ініціалізації фізики
	await get_tree().physics_frame
	top_level = true
# Спробуємо взяти Basis.z (якщо капот, то міняємо на -z)
# Якщо спавниться перед капотом, просто зміни + на - нижче:
	var back_direction = target.global_basis.z 
# Встановлюємо позицію: позиція машини + напрямок назад * дистанція
	global_position = target.global_position + (back_direction * min_distance)
	global_position.y += height
	look_at(target.global_position, Vector3.UP)
# Дивимося на машину
	look_at(target.global_position, Vector3.UP)

func _physics_process(delta: float) -> void:
# 1. Отримуємо швидкість цілі (RaycastCar)
	var current_speed = 0.0
	if target is RigidBody3D:
		current_speed = target.linear_velocity.length()
# 2. Розраховуємо бажану дистанцію на основі швидкості
# Чим більша швидкість, тим далі камера
	var target_dist = min_distance + (current_speed * speed_zoom_factor)
	target_dist = clamp(target_dist, min_distance, max_distance)

# 3. Розрахунок позиції камери

	var from_target := global_position - target.global_position


# Плавне наближення/віддалення (lerp), щоб не було різких стрибків

	var current_dist = from_target.length()

	var new_dist = lerp(current_dist, target_dist, delta * 5.0)

	var target_pos = target.global_position + (target.global_basis.z * current_dist)

	target_pos.y += height

	global_position = global_position.lerp(target_pos, delta * 5.0) # 5.0 — швидкість догону

	from_target = from_target.normalized() * new_dist

	from_target.y = height


	global_position = target.global_position + from_target


# 4. Погляд на машину

	look_at_from_position(global_position, target.global_position, Vector3.UP)


	fov = lerp(fov, 75.0 + (current_speed * 0.2), delta * 2.0)
