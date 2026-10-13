extends Node3D

@onready var crt_area: Area3D = $CRT/Area3D

func _ready() -> void:
	if crt_area:
		crt_area.input_event.connect(_on_crt_area_input_event)

func _on_crt_area_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	# On Left Click, switch to the 2D UI scene
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		get_tree().change_scene_to_file("res://main_menu_ui.tscn")