class_name CharPreview
extends Control
## Zeigt einen Charakter animiert und vergrößert (Menüs, Charakterwahl, Ergebnis).

var texture: Texture2D
var scale_factor := 3.0
var flip := false
var walking := false
var _time := 0.0
var _offset := 0.0


func setup(char_id: String, p_scale: float, p_flip := false) -> CharPreview:
	texture = load(String(CharacterDefs.get_def(char_id)["sprite"]))
	scale_factor = p_scale
	flip = p_flip
	custom_minimum_size = Vector2(26, 30) * p_scale
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_offset = randf() * 2.0
	return self


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if not texture:
		return
	var frame := (2 + int(_time * 9.0) % 4) if walking else int((_time + _offset) * 2.5) % 2
	var fw := 26.0
	var src := Rect2(frame * fw, 0, fw, 30)
	var dst_size := Vector2(fw, 30) * scale_factor
	var dst := Rect2((size - dst_size) * 0.5, dst_size)
	# Schatten
	draw_set_transform(Vector2(size.x * 0.5, dst.end.y - scale_factor * 2.0), 0.0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, dst_size.x * 0.32, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if flip:
		# An der senkrechten Mittelachse spiegeln
		draw_set_transform(Vector2(size.x, 0), 0.0, Vector2(-1, 1))
	draw_texture_rect_region(texture, dst, src)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
