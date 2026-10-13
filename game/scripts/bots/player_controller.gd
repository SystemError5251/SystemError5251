class_name PlayerController
extends RefCounted
## Liefert die Eingaben des lokalen Spielers: Touch-Steuerung plus Tastatur (Desktop-Test).

var touch: TouchControls


func get_input(_f: Fighter, _delta: float) -> InputFrame:
	var inp := touch.consume_frame() if touch else InputFrame.new()
	var kb := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	if kb != Vector2.ZERO:
		inp.move = kb.normalized()
	return inp


## Verwirft gesammelte Eingaben (z. B. während des Countdowns).
func discard() -> void:
	if touch:
		touch.consume_frame()
