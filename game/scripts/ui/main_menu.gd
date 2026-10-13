extends Control
## Hauptmenü: Logo, Modus-Auswahl, Einstellungen.


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBackground.new())

	var logo := TextureRect.new()
	logo.texture = preload("res://assets/ui/logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_SCALE
	logo.size = Vector2(142, 26) * 3.0
	logo.position = Vector2(320 - logo.size.x * 0.5, 10)
	add_child(logo)
	var sub := UiKit.label("2D-Multiplayer-Arena-Brawler", 8, UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	sub.position = Vector2(0, 92)
	sub.size = Vector2(640, 10)
	add_child(sub)

	# Charaktere links und rechts
	var left := CharPreview.new().setup("firewall", 4.0)
	left.position = Vector2(30, 190)
	add_child(left)
	var left2 := CharPreview.new().setup("overclock", 4.0)
	left2.position = Vector2(112, 222)
	add_child(left2)
	var right := CharPreview.new().setup("ping", 4.0, true)
	right.position = Vector2(500, 200)
	add_child(right)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.position = Vector2(220, 110)
	box.custom_minimum_size = Vector2(200, 0)
	add_child(box)

	var b1 := UiKit.button("TEAM-CRASH 3v3", Vector2(200, 30), true)
	b1.pressed.connect(func() -> void: Game.goto_select("team_crash"))
	box.add_child(b1)
	var b2 := UiKit.button("DUELL 1v1")
	b2.pressed.connect(func() -> void: Game.goto_select("duel"))
	box.add_child(b2)
	var b3 := UiKit.button("TRAINING")
	b3.pressed.connect(func() -> void: Game.goto_select("training"))
	box.add_child(b3)
	var b4 := UiKit.button("LAN-SPIEL (bald)")
	b4.disabled = true
	box.add_child(b4)
	var b5 := UiKit.button("EINSTELLUNGEN")
	b5.pressed.connect(func() -> void: Game.goto_settings())
	box.add_child(b5)

	var ver := UiKit.label("v%s · Prototyp (Phase 0/1) · Bots statt Online-Gegner" % Game.VERSION, 8,
		Color(UiKit.MUTED, 0.8))
	ver.position = Vector2(8, 344)
	add_child(ver)
