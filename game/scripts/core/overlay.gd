class_name Overlay
extends Node2D
## Anzeigen über den Kämpfern: Lebensbalken, Namen, Munition, Schadenszahlen, Zielvorschau.

const TILE := 32.0

var match_ref: Match
var _numbers: Array[Dictionary] = []
var _font: Font
var _time := 0.0


func _ready() -> void:
	_font = Game.font


## Schadenszahlen desselben Ziels werden kurz zusammengefasst, damit nichts überlappt.
func damage_number(target: Fighter, amount: float, src: Fighter) -> void:
	if match_ref.net:
		match_ref.net.fx(["d", target.id, amount, src.id])
	var col := match_ref.damage_color(src, target)
	for n in _numbers:
		if n.get("target") == target and float(n["t"]) < 0.35 and n["col"] == col:
			n["amount"] = float(n["amount"]) + amount
			n["text"] = str(roundi(float(n["amount"])))
			n["t"] = 0.0
			n["p"] = target.position + Vector2(18, -30)
			return
	_numbers.append({"target": target, "amount": amount, "p": target.position + Vector2(18, -30),
		"text": str(roundi(amount)), "col": col, "t": 0.0})


## Kurzer Hinweis über einem Kämpfer („BLOCK“, „+1500“ …). Mehrere Hinweise
## für denselben Kämpfer werden übereinander gestapelt statt sich zu überdecken.
func popup(target: Fighter, text: String, col: Color) -> void:
	if match_ref.net:
		match_ref.net.fx(["p", target.id, text, col.to_rgba32()])
	var stacked := 0
	for n in _numbers:
		if n.get("popup_of") == target and float(n["t"]) < 0.6:
			stacked += 1
	_numbers.append({"popup_of": target, "p": target.position + Vector2(0, -54 - stacked * 9), "text": text,
		"col": col, "t": 0.0, "center": true})


func _process(delta: float) -> void:
	_time += delta
	for n in _numbers:
		n["t"] = float(n["t"]) + delta
		n["p"] = Vector2(n["p"]) + Vector2(0, -22.0 * delta)
	_numbers = _numbers.filter(func(n: Dictionary) -> bool: return float(n["t"]) < 0.9)
	queue_redraw()


func _text(pos: Vector2, text: String, col: Color, size := 8, centered := true) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := pos - Vector2(w * 0.5, 0) if centered else pos
	p = p.round()
	draw_string(_font, p + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, col.a * 0.85))
	draw_string(_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _draw() -> void:
	if not match_ref:
		return
	_draw_aim_preview()
	var viewer := match_ref.view_team()
	# Der eigene Kämpfer zuerst, dann nach Entfernung: nahe Namen haben Vorrang,
	# Namen, die einen bereits gezeichneten überdecken würden, entfallen.
	var order: Array[Fighter] = match_ref.fighters.duplicate()
	var me := match_ref.local
	if me:
		order.sort_custom(func(x: Fighter, y: Fighter) -> bool:
			if x == me or y == me:
				return x == me
			return x.position.distance_squared_to(me.position) < y.position.distance_squared_to(me.position))
	var taken: Array[Rect2] = []
	for f in order:
		if not f.alive or f.alpha < 0.05:
			continue
		if f.hidden_from(viewer):
			continue
		var a := f.alpha
		var top := f.position + Vector2(0, -34)
		var col: Color = Fighter.TEAM_COLORS[match_ref.display_team(f.team)]
		# Name (nur wenn Platz ist)
		var label := "DU" if f.is_local else f.display_name
		var lw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		var lrect := Rect2(top.x - lw * 0.5 - 1, top.y - 17, lw + 2, 10)
		var free := true
		for t in taken:
			if t.intersects(lrect):
				free = false
				break
		if free:
			taken.append(lrect)
			_text(top + Vector2(0, -9), label, Color(1, 0.88, 0.3, a) if f.is_local else Color(0.85, 0.88, 1.0, 0.85 * a))
		# Lebensbalken
		var w := 28.0
		var r := Rect2(top.x - w * 0.5, top.y, w, 4)
		draw_rect(r.grow(1), Color(0.02, 0.03, 0.06, 0.9 * a))
		draw_rect(Rect2(r.position, Vector2(w * clampf(f.hp / f.max_hp, 0.0, 1.0), 4)), Color(col, a))
		draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(f.hp / f.max_hp, 0.0, 1.0), 1)),
			Color(1, 1, 1, 0.35 * a))
		# Munition (nur eigener Kämpfer)
		if f.is_local:
			for i in 3:
				var seg := Rect2(r.position.x + i * 10.0, r.position.y + 6, 8, 2)
				draw_rect(seg, Color(0.1, 0.1, 0.15, 0.9 * a))
				var fill := clampf(f.ammo - i, 0.0, 1.0)
				draw_rect(Rect2(seg.position, Vector2(8 * fill, 2)),
					Color(1, 0.75, 0.2, a) if fill >= 1.0 else Color(0.7, 0.5, 0.2, a))
		# Ultimate bereit
		if f.ult_ready():
			var pulse := 0.6 + 0.4 * sin(_time * 8.0)
			_text(Vector2(r.end.x + 6, r.position.y - 2), "★", Color(1, 0.88, 0.3, pulse * a), 8, false)
		# Markiert (PING-Ultimate)
		if f.marked_t > 0.0:
			var m := top + Vector2(0, -16)
			draw_colored_polygon(PackedVector2Array([m + Vector2(0, -4), m + Vector2(4, 0), m + Vector2(0, 4),
				m + Vector2(-4, 0)]), Color(1, 0.24, 0.95, a))
		if f.shield_t > 0.0 and f.is_local:
			_text(top + Vector2(0, 14), "SCHILD %.1f" % f.shield_t, Color(0.6, 0.95, 1.0, a))
	for n in _numbers:
		var k := 1.0 - float(n["t"]) / 0.9
		var col2: Color = n["col"]
		_text(n["p"], String(n["text"]), Color(col2, minf(1.0, k * 2.0)), 8, bool(n.get("center", false)))


func _draw_aim_preview() -> void:
	var f := match_ref.local
	if not f or not f.alive or not match_ref.touch:
		return
	var aim := match_ref.touch.aim_preview()
	if aim.is_empty():
		return
	var kind: String = aim["kind"]
	var dir: Vector2 = aim["dir"]
	var cancel: bool = aim["cancel"]
	var origin := f.position
	var col := Color(1, 1, 1, 0.35) if not cancel else Color(1, 0.3, 0.3, 0.3)
	var info: Dictionary
	match kind:
		"attack":
			info = f.def["attack"]
		"special":
			info = f.def["special"]
		_:
			info = f.def["ult"]
	var shape := String(info.get("kind", ""))
	match shape:
		"melee":
			var reach := float(info["range"]) * TILE
			var half := deg_to_rad(float(info["arc"])) * 0.5
			_draw_cone(origin, dir, reach, half, col)
		"shotgun":
			var reach2 := float(info["range"]) * TILE
			var half2 := deg_to_rad(float(info["spread"])) * 0.5 + 0.05
			_draw_cone(origin, dir, reach2, half2, col)
		"beam", "traceroute":
			var reach3 := float(info["range"]) * TILE
			var end := origin + dir * reach3
			if shape == "beam":
				end = match_ref.arena.cast_segment(origin, end)["pos"]
			var side := dir.orthogonal() * (3.0 if shape == "beam" else 6.0)
			draw_colored_polygon(PackedVector2Array([origin + side, end + side, end - side, origin - side]), col)
		"dash", "backjump":
			var reach4 := float(info["distance"]) * TILE
			var end2 := origin + dir * reach4
			draw_line(origin, end2, col, 6.0)
			draw_circle(end2, 8.0, col)
		"portblock":
			var center := origin + dir * float(info["distance"]) * TILE
			var along := Vector2(0, 1) if absf(dir.x) >= absf(dir.y) else Vector2(1, 0)
			for k in range(-2, 3):
				var c := match_ref.arena.to_cell(center + along * k * TILE)
				draw_rect(Rect2(c.x * TILE, c.y * TILE, TILE, TILE), col)
		"shield", "overclock":
			draw_arc(origin + Vector2(0, -10), 22.0, 0.0, TAU, 24, col, 3.0)


func _draw_cone(origin: Vector2, dir: Vector2, reach: float, half: float, col: Color) -> void:
	var pts := PackedVector2Array([origin])
	var steps := 10
	for i in steps + 1:
		var a := dir.angle() - half + (2.0 * half) * float(i) / steps
		pts.append(origin + Vector2.from_angle(a) * reach)
	draw_colored_polygon(pts, col)
