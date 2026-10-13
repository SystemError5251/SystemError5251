class_name TouchControls
extends Control
## Twin-Stick-Steuerung für Touchscreens (siehe Konzept 4.2).
## - Links: dynamischer Bewegungs-Stick (erscheint dort, wo der Daumen aufsetzt)
## - Rechts: Angriffs-Stick (Tippen = Auto-Aim, Ziehen = Zielen, zurück zur Mitte = Abbrechen)
## - Spezial- und Ultimate-Button funktionieren genauso.
## Auf dem Desktop kann die Maus einen Finger ersetzen.

const MOVE_RADIUS := 30.0
const DEADZONE := 9.0
const MOUSE_INDEX := 100

const STICKS := {
	"attack": {"center": Vector2(566, 290), "radius": 36.0, "grab": 50.0, "label": ""},
	"special": {"center": Vector2(484, 318), "radius": 22.0, "grab": 30.0, "label": "SPEZ"},
	"ult": {"center": Vector2(500, 244), "radius": 24.0, "grab": 32.0, "label": "ULT"},
}

var match_ref: Match
var _move_touch := -1
var _move_origin := Vector2.ZERO
var _move_cur := Vector2.ZERO
var _sticks := {}       # Name -> {touch, cur, max}
var _queued: Array = [] # [Name, Aim]
var _touchscreen := false
var _time := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_touchscreen = DisplayServer.is_touchscreen_available()
	for k in STICKS:
		_sticks[k] = {"touch": -1, "cur": Vector2.ZERO, "max": 0.0}


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or (match_ref and match_ref.paused):
		return
	if event is InputEventScreenTouch:
		var e := make_input_local(event) as InputEventScreenTouch
		if e.pressed:
			_down(e.index, e.position)
		else:
			_up(e.index, e.position)
	elif event is InputEventScreenDrag:
		var d := make_input_local(event) as InputEventScreenDrag
		_drag(d.index, d.position)
	elif not _touchscreen and event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		var m := make_input_local(event) as InputEventMouseButton
		if m.button_index == MOUSE_BUTTON_LEFT:
			if m.pressed:
				_down(MOUSE_INDEX, m.position)
			else:
				_up(MOUSE_INDEX, m.position)
	elif not _touchscreen and event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		var mm := make_input_local(event) as InputEventMouseMotion
		_drag(MOUSE_INDEX, mm.position)


func _down(index: int, pos: Vector2) -> void:
	for k in STICKS:
		var s: Dictionary = _sticks[k]
		var center: Vector2 = STICKS[k]["center"]
		if s["touch"] == -1 and pos.distance_to(center) <= float(STICKS[k]["grab"]):
			s["touch"] = index
			s["cur"] = pos
			s["max"] = 0.0
			return
	if pos.x < size.x * 0.5 and _move_touch == -1:
		_move_touch = index
		_move_origin = pos
		_move_cur = pos


func _drag(index: int, pos: Vector2) -> void:
	if index == _move_touch:
		_move_cur = pos
		var off := _move_cur - _move_origin
		if off.length() > MOVE_RADIUS:
			_move_origin = _move_cur - off.normalized() * MOVE_RADIUS
		return
	for k in STICKS:
		var s: Dictionary = _sticks[k]
		if s["touch"] == index:
			s["cur"] = pos
			var center: Vector2 = STICKS[k]["center"]
			s["max"] = maxf(float(s["max"]), pos.distance_to(center))


func _up(index: int, pos: Vector2) -> void:
	if index == _move_touch:
		_move_touch = -1
		return
	for k in STICKS:
		var s: Dictionary = _sticks[k]
		if s["touch"] != index:
			continue
		s["touch"] = -1
		var center: Vector2 = STICKS[k]["center"]
		var off := pos - center
		if float(s["max"]) < DEADZONE:
			_queued.append([k, Vector2.ZERO])       # Antippen → Auto-Aim
		elif off.length() >= DEADZONE:
			_queued.append([k, off.normalized()])   # Gezielter Einsatz
		# sonst: zurück zur Mitte gezogen → abgebrochen
		return


## Aktuelle Bewegungsrichtung (Länge 0..1).
func move_vector() -> Vector2:
	if _move_touch == -1:
		return Vector2.ZERO
	return ((_move_cur - _move_origin) / MOVE_RADIUS).limit_length(1.0)


## Liefert die Eingaben seit dem letzten Aufruf als InputFrame.
func consume_frame() -> InputFrame:
	var inp := InputFrame.new()
	inp.move = move_vector()
	for q in _queued:
		var aim: Vector2 = q[1]
		match String(q[0]):
			"attack":
				inp.attack = true
				inp.attack_aim = aim
			"special":
				inp.special = true
				inp.special_aim = aim
			"ult":
				inp.ult = true
				inp.ult_aim = aim
	_queued.clear()
	return inp


## Für die Zielvorschau: welcher Stick wird gerade gezogen?
func aim_preview() -> Dictionary:
	for k in STICKS:
		var s: Dictionary = _sticks[k]
		if s["touch"] == -1 or float(s["max"]) < DEADZONE:
			continue
		var center: Vector2 = STICKS[k]["center"]
		var off: Vector2 = Vector2(s["cur"]) - center
		var dir := off.normalized() if off.length() > 0.5 else Vector2.RIGHT
		return {"kind": k, "dir": dir, "cancel": off.length() < DEADZONE}
	return {}


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var font := Game.font
	var f: Fighter = match_ref.local if match_ref else null
	# Bewegungs-Stick
	if _move_touch != -1:
		draw_circle(_move_origin, MOVE_RADIUS + 6.0, Color(1, 1, 1, 0.08))
		draw_arc(_move_origin, MOVE_RADIUS + 6.0, 0.0, TAU, 32, Color(1, 1, 1, 0.3), 1.5)
		draw_circle(_move_origin + move_vector() * MOVE_RADIUS, 13.0, Color(1, 1, 1, 0.45))
	else:
		var hint := Vector2(92, 284)
		draw_arc(hint, MOVE_RADIUS + 6.0, 0.0, TAU, 32, Color(1, 1, 1, 0.12), 1.5)
		draw_circle(hint, 11.0, Color(1, 1, 1, 0.1))
	for k in STICKS:
		var cfg: Dictionary = STICKS[k]
		var center: Vector2 = cfg["center"]
		var r := float(cfg["radius"])
		var s: Dictionary = _sticks[k]
		var active: bool = s["touch"] != -1
		var ready := true
		var fill := 1.0
		var col := Color("ff8a1f")
		match String(k):
			"attack":
				col = Color("ff8a1f")
				ready = f != null and f.ammo >= 1.0
			"special":
				col = Color("27e1ff")
				if f:
					var cd := float(f.def["special"]["cooldown"])
					fill = 1.0 - f.special_cd / cd
					ready = f.special_cd <= 0.0
			"ult":
				col = Color("ffe14d")
				if f:
					fill = f.ult
					ready = f.ult_ready()
		var base_a := 0.55 if ready else 0.25
		draw_circle(center, r, Color(0.04, 0.06, 0.1, 0.55))
		draw_arc(center, r, 0.0, TAU, 40, Color(col, 0.25), 2.0)
		if fill < 1.0:
			draw_arc(center, r, -PI * 0.5, -PI * 0.5 + TAU * fill, 40, Color(col, 0.9), 2.0)
		else:
			var pulse := 1.0 if k != "ult" else 0.7 + 0.3 * sin(_time * 7.0)
			draw_arc(center, r, 0.0, TAU, 40, Color(col, base_a * pulse + 0.2), 2.0)
		var knob := center
		if active:
			var off: Vector2 = Vector2(s["cur"]) - center
			knob = center + off.limit_length(r)
		draw_circle(knob, r * (0.42 if k == "attack" else 0.62), Color(col, base_a * (1.0 if k == "attack" else 0.55)))
		var label := String(cfg["label"])
		if k == "attack":
			# Fadenkreuz + Munitionsanzeige
			draw_arc(knob, 6.0, 0.0, TAU, 16, Color(1, 1, 1, 0.85), 1.5)
			draw_line(knob + Vector2(-10, 0), knob + Vector2(-4, 0), Color(1, 1, 1, 0.85), 1.5)
			draw_line(knob + Vector2(4, 0), knob + Vector2(10, 0), Color(1, 1, 1, 0.85), 1.5)
			if f:
				for i in 3:
					var have := f.ammo >= i + 1
					draw_circle(Vector2(center.x - 14 + i * 14, center.y - r - 7), 3.0,
						Color(1, 0.75, 0.2, 0.95) if have else Color(0.3, 0.3, 0.35, 0.8))
		elif label != "":
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
			var tp := (knob + Vector2(-w * 0.5, 3)).round()
			draw_string(font, tp + Vector2(1, 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0, 0, 0, 0.8))
			draw_string(font, tp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8,
				Color(1, 1, 1, 0.95) if ready else Color(1, 1, 1, 0.45))
