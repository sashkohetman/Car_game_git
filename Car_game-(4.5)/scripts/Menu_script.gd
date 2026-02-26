extends Node3D
class_name Menu
@onready var start_button = $Main_layer/HBoxContainer/Start_button
@onready var customization_button = $Main_layer/HBoxContainer/Customisation
@onready var rundyno_button = $Custommain_layer/HBoxContainer/Dyno_button
@onready var dyno_layer = $Dyno_layer
@onready var main_layer = $Main_layer
@onready var custom_main_layer = $Custommain_layer
@onready var car = $Car/RaycastCar
@onready var engine = $Car/Engine
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	car.control_car = false
	main_layer.show()
	custom_main_layer.hide()
	dyno_layer.hide()
	pass # Replace with function body.
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float):
	if start_button.button_pressed:
		get_tree().change_scene_to_file("res://scenes/enviroment.tscn")
	elif customization_button.button_pressed:
		main_layer.hide()
		custom_main_layer.show()
	elif rundyno_button.button_pressed:
		custom_main_layer.hide()
		dyno_layer.show()
	else: pass
