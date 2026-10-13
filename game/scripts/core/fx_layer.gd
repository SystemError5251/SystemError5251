class_name FxLayer
extends Node2D
## Kurzlebige Effekte (Strahlen, Schläge, Ringe, Funken, Nachbilder) und Projektile.
## Rein visuell – hat keinen Einfluss auf die Simulation.

const PELLET_TEX := preload("res://assets/fx/pellet.png")

var match_ref: Match
var _fx: Array[Dictionary] = []


func beam(a: Vector2, b: Vector2, col: Color, width: float) -> void:
	_fx.append({"type": "beam", "a": a, "b": b, "col": col, "w": width, "t": 0.0, "dur": 0.18})
	sparks(b, col, 5)


func slash(center: Vector2, dir: Vector2, reach: float, col: Color, strong: bool) -> void:
	_fx.append({"type": "slash", "c": center, "ang": dir.angle(), "r": reach * 0.8, "col": col,
		"t": 0.0, "dur": 0.14, "w": 4.0 if strong else 2.5})


func ring(center: Vector2, col: Color, radius: float) -> void:
	_fx.append({"type": "ring", "c": center, "col": col, "r": radius, "t": 0.0, "dur": 0.35})


func muzzle(p: Vector2, col: Color) -> void:
	_fx.append({"type": "muzzle", "c": p, "col": col, "t": 0.0, "dur": 0.08})


func sparks(p: Vector2, col: Color, n: int) -> void:
	for i in n:
		var v := Vector2.from_angle(randf() * TAU) * randf_range(30.0, 110.0)
		_fx.append({"type": "spark", "p": p, "v": v, "col": col, "t": 0.0, "dur": randf_range(0.2, 0.4)})


func burst(p: Vector2, col: Color) -> void:
	sparks(p, col, 16)
	sparks(p, Color("ff3df2"), 6)
	sparks(p, Color("27e1ff"), 6)
	ring(p, col, 34.0)


func afterimage(f: Fighter) -> void:
	_fx.append({"type": "after", "p": f.position, "tex": f.sprite.texture, "frame": f.sprite.frame,
		"flip": f.sprite.flip_h, "t": 0.0, "dur": 0.2})


func _process(delta: float) -> void:
	for e in _fx:
		e["t"] = float(e["t"]) + delta
		if e["type"] == "spark":
			e["p"] = Vector2(e["p"]) + Vector2(e["v"]) * delta
			e["v"] = Vector2(e["v"]) * 0.9
	_fx = _fx.filter(func(e: Dictionary) -> bool: return float(e["t"]) < float(e["dur"]))
	queue_redraw()


func _draw() -> void:
	# Projektile
	if match_ref:
		for p: Projectile in match_ref.projectiles:
			draw_texture(PELLET_TEX, p.pos + Vector2(-4, -14))
	for e in _fx:
		var k := 1.0 - float(e["t"]) / float(e["dur"])
		var col: Color = e["col"] if e.has("col") else Color.WHITE
		match String(e["type"]):
			"beam":
				var a: Vector2 = e["a"]
				var b: Vector2 = e["b"]
				var w := float(e["w"]) * (0.5 + k)
				draw_line(a + Vector2(-1, 0), b + Vector2(-1, 0), Color(0.15, 0.88, 1.0, 0.6 * k), w)
				draw_line(a + Vector2(1, 0), b + Vector2(1, 0), Color(1.0, 0.24, 0.95, 0.6 * k), w)
				draw_line(a, b, Color(col, k), w)
				draw_line(a, b, Color(1, 1, 1, k), maxf(1.0, w * 0.4))
			"slash":
				var c: Vector2 = e["c"]
				var ang := float(e["ang"])
				var r := float(e["r"]) * (0.7 + 0.3 * (1.0 - k))
				draw_arc(c, r, ang - 0.9, ang + 0.9, 12, Color(col, k), float(e["w"]))
				draw_arc(c, r - 4.0, ang - 0.6, ang + 0.6, 10, Color(1, 1, 1, k * 0.8), 1.5)
			"ring":
				var r2 := float(e["r"]) * (1.0 - k * 0.7)
				draw_arc(e["c"], r2, 0.0, TAU, 32, Color(col, k), 2.0)
			"muzzle":
				draw_circle(e["c"], 5.0 * k + 2.0, Color(col, k))
			"spark":
				var p: Vector2 = e["p"]
				draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), Color(col, k))
			"after":
				var tex: Texture2D = e["tex"]
				var fw := tex.get_width() / 6.0
				var src := Rect2(int(e["frame"]) * fw, 0, fw, tex.get_height())
				var dst := Rect2(Vector2(e["p"]) + Vector2(-fw * 0.5, -tex.get_height() + 1), Vector2(fw, tex.get_height()))
				if bool(e["flip"]):
					dst.size.x = -dst.size.x
					dst.position.x += fw
				draw_texture_rect_region(tex, dst, src, Color(1.0, 0.9, 0.3, 0.45 * k))
