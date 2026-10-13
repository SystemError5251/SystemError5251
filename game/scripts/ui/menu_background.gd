class_name MenuBackground
extends Control
## Animierter Menü-Hintergrund: Raster, Leiterbahnen und zufällige Glitch-Streifen.

var _time := 0.0
var _glitches: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.seed = 3


func _process(delta: float) -> void:
	_time += delta
	if _rng.randf() < delta * 3.0:
		_glitches.append({"y": _rng.randf_range(0, 360), "h": _rng.randf_range(1, 5),
			"x": _rng.randf_range(-100, 500), "w": _rng.randf_range(40, 260),
			"c": [UiKit.CYAN, UiKit.MAGENTA, Color.WHITE][_rng.randi_range(0, 2)], "t": 0.0})
	for g in _glitches:
		g["t"] = float(g["t"]) + delta
	_glitches = _glitches.filter(func(g: Dictionary) -> bool: return float(g["t"]) < 0.25)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UiKit.BG)
	var off := fmod(_time * 12.0, 32.0)
	for x in range(-32, int(size.x) + 32, 32):
		draw_line(Vector2(x + off, 0), Vector2(x + off, size.y), Color(0.15, 0.2, 0.35, 0.35), 1.0)
	for y in range(-32, int(size.y) + 32, 32):
		draw_line(Vector2(0, y + off), Vector2(size.x, y + off), Color(0.15, 0.2, 0.35, 0.35), 1.0)
	# Leuchtende Punkte, die über das Raster wandern
	for i in 8:
		var phase := fmod(_time * 0.15 + i * 0.13, 1.0)
		var horizontal := i % 2 == 0
		var lane := 32.0 * (2 + i * 2) + off
		var p := Vector2(phase * size.x, lane) if horizontal else Vector2(lane, phase * size.y)
		draw_rect(Rect2(p - Vector2(1, 1), Vector2(3, 3)), Color(UiKit.CYAN, 0.6))
	for g in _glitches:
		var c: Color = g["c"]
		draw_rect(Rect2(float(g["x"]), float(g["y"]), float(g["w"]), float(g["h"])), Color(c, 0.18))
	# Vignette unten
	for i in 12:
		draw_rect(Rect2(0, size.y - 12 * 6 + i * 6, size.x, 6), Color(0, 0, 0, 0.03 * i))
