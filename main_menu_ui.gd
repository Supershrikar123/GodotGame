extends Control

signal start_game_pressed
signal settings_pressed

# Drag and drop your nodes here if your node paths differ
@onready var button_play: Button = $ColorRect/MarginContainer/VBoxContainer/ButtonPlay
@onready var button_quit: Button = $ColorRect/MarginContainer/VBoxContainer/ButtonQuit

func _ready() -> void:
	# Check if nodes exist before connecting to prevent crashes if paths change
	if button_play:
		button_play.pressed.connect(_on_play_pressed) 
	if button_quit:
		button_quit.pressed.connect(_on_quit_pressed)

func _on_play_pressed() -> void:
	emit_signal("start_game_pressed")

func _on_quit_pressed() -> void:
	get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	# Press ESC to switch back to the 3D room view
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://main_menu.tscn")