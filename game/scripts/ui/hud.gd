class_name Hud
extends CanvasLayer
## HUD im Match: Punktestand, Zeit, Kill-Feed, Banner, Pause-Menü und Touch-Steuerung.

var match_ref: Match
var touch: TouchControls
var _info: Control
var _pause_btn: Button
var _pause_panel: Control
var _feed: Array[Dictionary] = []
var _banner := {}
var _time := 0.0


func _ready() -> void:
	layer = 10
	_info = Control.new()
	_info.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.draw.connect(_draw_info)
	add_child(_info)

	touch = TouchControls.new()
	touch.match_ref = match_ref
	add_child(touch)

	_pause_btn = UiKit.button("II", Vector2(24, 20))
	_pause_btn.add_theme_font_size_override("font_size", 8)
	_pause_btn.position = Vector2(608, 6)
	_pause_btn.pressed.connect(func() -> void: set_paused(true))
	add_child(_pause_btn)

	_build_pause_menu()


func _build_pause_menu() -> void:
	_pause_panel = ColorRect.new()
	(_pause_panel as ColorRect).color = Color(0.02, 0.03, 0.06, 0.75)
	_pause_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_panel.visible = false
	add_child(_pause_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.position = Vector2(220, 110)
	box.custom_minimum_size = Vector2(200, 140)
	_pause_panel.add_child(box)
	box.add_child(UiKit.label("PAUSE", 24, UiKit.YELLOW, HORIZONTAL_ALIGNMENT_CENTER))
	var resume := UiKit.button("WEITER", Vector2(200, 28), true)
	resume.pressed.connect(func() -> void: set_paused(false))
	box.add_child(resume)
	var quit := UiKit.button("AUFGEBEN")
	quit.pressed.connect(func() -> void:
		set_paused(false)
		match_ref.surrender())
	box.add_child(quit)
	var menu := UiKit.button("HAUPTMENÜ")
	menu.pressed.connect(func() -> void: Game.goto_menu())
	box.add_child(menu)


func set_paused(p: bool) -> void:
	if match_ref.ended:
		p = false
	match_ref.paused = p
	_pause_panel.visible = p
	touch.visible = not p


func banner(text: String, col: Color, duration: float) -> void:
	_banner = {"text": text, "col": col, "t": 0.0, "dur": duration}


func killfeed(killer: Fighter, victim: Fighter) -> void:
	_feed.append({"k": killer.display_name, "kt": match_ref.display_team(killer.team),
		"v": victim.display_name, "vt": match_ref.display_team(victim.team), "t": 0.0})
	if _feed.size() > 4:
		_feed.pop_front()


func _process(delta: float) -> void:
	_time += delta
	for e in _feed:
		e["t"] = float(e["t"]) + delta
	_feed = _feed.filter(func(e: Dictionary) -> bool: return float(e["t"]) < 5.0)
	if not _banner.is_empty():
		_banner["t"] = float(_banner["t"]) + delta
		if float(_banner["t"]) > float(_banner["dur"]):
			_banner = {}
	_info.queue_redraw()


func _draw_info() -> void:
	var font := Game.font
	var m := match_ref
	var cx := 320.0
	match m.mode:
		"team_crash":
			_score_box(Rect2(cx - 92, 6, 56, 22), str(m.score[0]), UiKit.BLUE)
			_score_box(Rect2(cx + 36, 6, 56, 22), str(m.score[1]), UiKit.ORANGE)
			_text_c(Vector2(cx, 22), UiKit.format_time(m.time_left), 16,
				UiKit.MAGENTA if m.time_left < 30.0 and int(_time * 4) % 2 == 0 else UiKit.TEXT)
			_text_c(Vector2(cx, 38), "ZIEL: %d KOs" % int(m.rules["target"]), 8, UiKit.MUTED)
		"duel":
			_text_c(Vector2(cx, 16), "RUNDE %d" % m.round_no, 8, UiKit.MUTED)
			_text_c(Vector2(cx, 32), UiKit.format_time(m.time_left), 16, UiKit.TEXT)
			for i in 2:
				_dot(Vector2(cx - 50 - i * 12, 20), m.round_wins[0] > i, UiKit.BLUE)
				_dot(Vector2(cx + 50 + i * 12, 20), m.round_wins[1] > i, UiKit.ORANGE)
		"training":
			_text_c(Vector2(cx, 18), "TRAINING", 16, UiKit.YELLOW)
			var dmg := roundi(m.local.damage_dealt) if m.local else 0
			_text_c(Vector2(cx, 32), "Schaden gesamt: %d" % dmg, 8, UiKit.TEXT)
	# Kill-Feed
	var y := 38.0
	for e in _feed:
		var a := clampf(5.0 - float(e["t"]), 0.0, 1.0)
		var kc: Color = Fighter.TEAM_COLORS[int(e["kt"])]
		var vc: Color = Fighter.TEAM_COLORS[int(e["vt"])]
		var right := 630.0
		var vw := font.get_string_size(String(e["v"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		var kw := font.get_string_size(String(e["k"]) + " → ", HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		_info.draw_rect(Rect2(right - vw - kw - 6, y - 8, vw + kw + 8, 11), Color(0, 0, 0, 0.45 * a))
		_info.draw_string(font, Vector2(right - vw - kw - 2, y), String(e["k"]) + " → ", HORIZONTAL_ALIGNMENT_LEFT,
			-1, 8, Color(kc, a))
		_info.draw_string(font, Vector2(right - vw - 2, y), String(e["v"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 8,
			Color(vc, a))
		y += 13.0
	# Banner
	if not _banner.is_empty():
		var t := float(_banner["t"])
		var dur := float(_banner["dur"])
		var a2 := clampf(minf(t * 8.0, (dur - t) * 4.0), 0.0, 1.0)
		var size := 32 if String(_banner["text"]).length() < 12 else 24
		UiKit.draw_glitch_text(_info, font, Vector2(cx, 150), String(_banner["text"]), size, _banner["col"], a2)
	# Tod: Respawn-Hinweis
	if m.local and not m.local.alive and m.local.respawn_t > 0.0 and not m.ended:
		_text_c(Vector2(cx, 200), "Neustart in %.1f s" % m.local.respawn_t, 16, UiKit.TEXT)
	if Game.settings.get("show_fps", false):
		_info.draw_string(font, Vector2(6, 12), "%d FPS" % Engine.get_frames_per_second(), HORIZONTAL_ALIGNMENT_LEFT,
			-1, 8, UiKit.MUTED)


func _text_c(pos: Vector2, text: String, size: int, col: Color) -> void:
	var font := Game.font
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := (pos - Vector2(w * 0.5, 0)).round()
	_info.draw_string(font, p + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.8))
	_info.draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _score_box(r: Rect2, text: String, col: Color) -> void:
	_info.draw_rect(r, Color(col, 0.25))
	_info.draw_rect(r, col, false, 1.0)
	_text_c(Vector2(r.get_center().x, r.position.y + 17), text, 16, Color.WHITE)


func _dot(p: Vector2, filled: bool, col: Color) -> void:
	_info.draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), col if filled else Color(col, 0.2))
	_info.draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), col, false, 1.0)
