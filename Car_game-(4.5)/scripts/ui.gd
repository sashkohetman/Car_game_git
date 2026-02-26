extends Node2D
@export var engine : CarEngine
@export var car : RigidBody3D
@export var wheels: Array[RaycastWheel]
@onready var speed_label = $CanvasLayer/SpeedLabel
@onready var rpm_label = $CanvasLayer/RPMLabel
@onready var DebugLayel = $DebugLayer
@onready var DebugLabel = $DebugLayer/DebugLabel
@onready var GearLabel = $CanvasLayer/GearLabel
func update_speed_display(speed: float):
	# Пряме відображення залежно від індексу
	match car.current_gear:
		0:
			GearLabel.text = "R"
		1:
			GearLabel.text = "N"
		2:
			GearLabel.text = "1G"
		3:
			GearLabel.text = "2G"
		4:
			GearLabel.text = "3G"
		5:
			GearLabel.text = "4G"
		6:
			GearLabel.text = "5G"
		_:
			GearLabel.text = "?"
	speed_label.text = str(round(speed)) + "KM/H"
	rpm_label.text = str(round(engine.rpm))
	if engine.rpm > engine.max_rpm - 200:
		rpm_label.set("theme_override_colors/font_color", Color.CRIMSON)
	else:
		rpm_label.set("theme_override_colors/font_color", Color.GHOST_WHITE)
	DebugLabel.text = str("Slip\n Fl: ", str(wheels[0].slip_ratio), " | FR: ", str(wheels[1].slip_ratio), "\n RL: ", str(wheels[2].slip_ratio), " | FR: ", str(wheels[3].slip_ratio),)
