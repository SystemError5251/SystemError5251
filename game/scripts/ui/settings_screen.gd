extends Control
## Einstellungen: Vibration, Bildschirmwackeln, FPS-Anzeige, Bot-Stärke.

const LEVELS := ["LEICHT", "NORMAL", "SCHWER"]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBackground.new())
	var title := UiKit.label("EINSTELLUNGEN", 16, UiKit.YELLOW, HORIZONTAL_ALIGNMENT_CENTER)
	title.position = Vector2(0, 20)
	title.size = Vector2(640, 16)
	add_child(title)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.position = Vector2(170, 70)
	box.custom_minimum_size = Vector2(300, 0)
	add_child(box)
	box.add_child(_toggle("Vibration bei Treffern", "haptics"))
	box.add_child(_toggle("Bildschirmwackeln", "shake"))
	box.add_child(_toggle("FPS anzeigen", "show_fps"))

	var lvl := UiKit.button("", Vector2(300, 28))
	lvl.add_theme_font_size_override("font_size", 8)
	var update_lvl := func() -> void:
		lvl.text = "Bot-Stärke: %s" % LEVELS[int(Game.settings["bot_level"])]
	update_lvl.call()
	lvl.pressed.connect(func() -> void:
		Game.settings["bot_level"] = (int(Game.settings["bot_level"]) + 1) % 3
		Game.save_settings()
		update_lvl.call())
	box.add_child(lvl)

	var note := UiKit.label("Online- und LAN-Einstellungen folgen mit dem Mehrspieler-Modus.", 8, UiKit.MUTED)
	box.add_child(note)

	var back := UiKit.button("ZURÜCK", Vector2(120, 28))
	back.position = Vector2(16, 322)
	back.pressed.connect(func() -> void: Game.goto_menu())
	add_child(back)


func _toggle(text: String, key: String) -> Control:
	var b := CheckButton.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 28)
	b.focus_mode = Control.FOCUS_NONE
	b.button_pressed = bool(Game.settings.get(key, true))
	b.toggled.connect(func(on: bool) -> void:
		Game.settings[key] = on
		Game.save_settings())
	return b
