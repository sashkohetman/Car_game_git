extends CanvasLayer

@onready var speed_label = $SpeedLabel

func update_speed_display(speed: float):
	print("Ui отримав швидкість: ", speed)
	speed_label.text = str(round(speed)) + "KM/H"
