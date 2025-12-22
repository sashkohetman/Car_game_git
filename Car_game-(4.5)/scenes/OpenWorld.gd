extends Node3D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var car := $Car/RaycastCar
	var ui := $UI/CanvasLayer
	car.speed_changed.connect(ui.update_speed_display)
