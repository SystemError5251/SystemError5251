extends Control
## Charakterwahl mit Werten und Fähigkeiten.

const MODE_INFO := {
	"team_crash": ["TEAM-CRASH", "3 gegen 3 · erstes Team mit 15 KOs gewinnt · 2:30 min"],
	"duel": ["DUELL", "1 gegen 1 · Best of 3 Runden · 60 s pro Runde"],
	"training": ["TRAINING", "Fähigkeiten an Trainings-Dummys ausprobieren"],
}

var _cards := {}
var _selected := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBackground.new())
	var info: Array = MODE_INFO[Game.pending.get("mode", "team_crash")]
	var title := UiKit.label("CHARAKTER WÄHLEN", 16, UiKit.YELLOW, HORIZONTAL_ALIGNMENT_CENTER)
	title.position = Vector2(0, 8)
	title.size = Vector2(640, 16)
	add_child(title)
	var sub := UiKit.label("%s – %s" % [info[0], info[1]], 8, UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	sub.position = Vector2(0, 28)
	sub.size = Vector2(640, 10)
	add_child(sub)

	var x := 16.0
	for id in CharacterDefs.ORDER:
		var card := _make_card(id)
		card.position = Vector2(x, 44)
		add_child(card)
		_cards[id] = card
		x += 208.0

	var back := UiKit.button("ZURÜCK", Vector2(120, 28))
	back.position = Vector2(16, 322)
	back.pressed.connect(func() -> void: Game.goto_menu())
	add_child(back)
	var go := UiKit.button("KAMPF!", Vector2(160, 28), true)
	go.position = Vector2(464, 322)
	go.pressed.connect(func() -> void: Game.start_match(String(Game.pending.get("mode", "team_crash")), _selected))
	add_child(go)
	_select(String(Game.pending.get("char", "overclock")))


func _make_card(id: String) -> Control:
	var def := CharacterDefs.get_def(id)
	var card := Button.new()
	card.custom_minimum_size = Vector2(196, 270)
	card.size = Vector2(196, 270)
	card.focus_mode = Control.FOCUS_NONE
	card.pressed.connect(func() -> void: _select(id))

	var preview := CharPreview.new().setup(id, 3.0)
	preview.position = Vector2(59, 4)
	card.add_child(preview)
	var name_l := UiKit.label(String(def["name"]), 16, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	name_l.position = Vector2(0, 98)
	name_l.size = Vector2(196, 16)
	card.add_child(name_l)
	var role := UiKit.label(String(def["role"]).to_upper(), 8, def["role_color"], HORIZONTAL_ALIGNMENT_CENTER)
	role.position = Vector2(0, 116)
	role.size = Vector2(196, 10)
	card.add_child(role)

	var bars: Dictionary = def["bars"]
	var y := 130.0
	for entry in [["LEBEN", "hp"], ["TEMPO", "speed"], ["REICHWEITE", "range"]]:
		var l := UiKit.label(String(entry[0]), 8, UiKit.MUTED)
		l.position = Vector2(12, y)
		card.add_child(l)
		var bar := _Bar.new()
		bar.value = float(bars[entry[1]])
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.position = Vector2(84, y + 2)
		bar.size = Vector2(100, 5)
		card.add_child(bar)
		y += 12.0
	var texts: Dictionary = def["text"]
	y += 4.0
	for k in [["A", "attack", UiKit.ORANGE], ["S", "special", UiKit.CYAN], ["U", "ult", UiKit.YELLOW]]:
		var tag := UiKit.label(String(k[0]), 8, k[2])
		tag.position = Vector2(12, y)
		card.add_child(tag)
		var desc := UiKit.label(String(texts[k[1]]), 8, UiKit.TEXT)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD
		desc.position = Vector2(24, y)
		desc.size = Vector2(164, 20)
		card.add_child(desc)
		y += 28.0
	return card


func _select(id: String) -> void:
	_selected = id
	Game.pending["char"] = id
	for k in _cards:
		var card: Button = _cards[k]
		var sel: bool = k == id
		card.add_theme_stylebox_override("normal", UiKit.style(Color("1a2440") if sel else UiKit.PANEL,
			UiKit.YELLOW if sel else Color(UiKit.CYAN, 0.35), 2 if sel else 1))
		card.add_theme_stylebox_override("hover", UiKit.style(Color("1d2a4a"), UiKit.YELLOW if sel else UiKit.CYAN,
			2 if sel else 1))
		card.add_theme_stylebox_override("pressed", UiKit.style(Color("1a2440"), UiKit.YELLOW, 2))
		card.modulate = Color.WHITE if sel else Color(0.78, 0.8, 0.9)


class _Bar extends Control:
	var value := 0.5

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.07, 0.12))
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * value, size.y)), UiKit.CYAN)
		for i in range(1, 5):
			draw_line(Vector2(size.x * i / 5.0, 0), Vector2(size.x * i / 5.0, size.y), Color(0, 0, 0, 0.6), 1.0)
