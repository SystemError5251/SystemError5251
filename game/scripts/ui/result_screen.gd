extends Control
## Ergebnis-Bildschirm nach einem Match.


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBackground.new())
	var r: Dictionary = Game.last_result
	if r.is_empty():
		r = {"mode": "team_crash", "title": "TEAM-CRASH", "winner": -1, "score": [0, 0], "rounds": [0, 0],
			"duration": 0.0, "stats": []}
	var winner := int(r["winner"])
	var head := _Banner.new()
	head.text = "SIEG!" if winner == 0 else ("NIEDERLAGE" if winner == 1 else "UNENTSCHIEDEN")
	head.col = Color("3cff8a") if winner == 0 else (UiKit.MAGENTA if winner == 1 else Color.WHITE)
	head.position = Vector2(0, 10)
	head.size = Vector2(640, 50)
	add_child(head)

	var score_txt := ""
	match String(r["mode"]):
		"team_crash":
			score_txt = "Team-Crash · %d : %d KOs" % [r["score"][0], r["score"][1]]
		"duel":
			score_txt = "Duell · Runden %d : %d" % [r["rounds"][0], r["rounds"][1]]
		_:
			score_txt = String(r["title"])
	score_txt += " · Dauer %s" % UiKit.format_time(float(r["duration"]))
	var sub := UiKit.label(score_txt, 8, UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	sub.position = Vector2(0, 62)
	sub.size = Vector2(640, 10)
	add_child(sub)

	# Tabelle
	var stats: Array = r["stats"]
	var mvp := -1
	var best := -1.0
	for i in stats.size():
		var s: Dictionary = stats[i]
		var v := float(s["damage"]) + float(s["kos"]) * 800.0
		if v > best:
			best = v
			mvp = i
	var table := Panel.new()
	table.position = Vector2(80, 82)
	table.size = Vector2(480, 26 + stats.size() * 26)
	add_child(table)
	var cols := [[46, "SPIELER"], [250, "KOs"], [310, "TODE"], [380, "SCHADEN"]]
	for c in cols:
		var h := UiKit.label(String(c[1]), 8, UiKit.MUTED)
		h.position = Vector2(float(c[0]), 8)
		table.add_child(h)
	var y := 24.0
	var sorted := stats.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["team"]) < int(b["team"]))
	for s: Dictionary in sorted:
		var team := int(s["team"])
		var stripe := ColorRect.new()
		stripe.color = Fighter.TEAM_COLORS[team]
		stripe.position = Vector2(6, y)
		stripe.size = Vector2(3, 22)
		table.add_child(stripe)
		var icon := CharPreview.new().setup(String(s["char"]), 0.75)
		icon.position = Vector2(16, y + 1)
		icon.size = Vector2(20, 22)
		table.add_child(icon)
		var nm := "%s (%s)" % [String(s["name"]), String(CharacterDefs.get_def(String(s["char"]))["name"])]
		if bool(s["local"]):
			nm = "DU (%s)" % String(CharacterDefs.get_def(String(s["char"]))["name"])
		var col := UiKit.YELLOW if bool(s["local"]) else UiKit.TEXT
		var l := UiKit.label(nm, 8, col)
		l.position = Vector2(46, y + 7)
		table.add_child(l)
		for c in [[250, str(s["kos"])], [310, str(s["deaths"])], [380, str(s["damage"])]]:
			var v := UiKit.label(String(c[1]), 8, UiKit.TEXT)
			v.position = Vector2(float(c[0]), y + 7)
			table.add_child(v)
		if stats.find(s) == mvp:
			var star := UiKit.label("★ MVP", 8, UiKit.YELLOW)
			star.position = Vector2(430, y + 7)
			table.add_child(star)
		y += 26.0

	var again := UiKit.button("NOCHMAL", Vector2(160, 28), true)
	again.position = Vector2(464, 322)
	again.pressed.connect(func() -> void: Game.start_match(String(r["mode"]), String(Game.pending.get("char", "overclock"))))
	add_child(again)
	var menu := UiKit.button("MENÜ", Vector2(120, 28))
	menu.position = Vector2(16, 322)
	menu.pressed.connect(func() -> void: Game.goto_menu())
	add_child(menu)


class _Banner extends Control:
	var text := ""
	var col := Color.WHITE
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		UiKit.draw_glitch_text(self, Game.font, Vector2(size.x * 0.5, 24), text, 32, col, minf(1.0, _t * 4.0))
