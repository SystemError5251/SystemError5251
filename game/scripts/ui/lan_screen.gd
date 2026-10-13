extends Control
## LAN-Spiel: Spiel eröffnen oder im WLAN gefundenem Spiel beitreten, danach Lobby.

var _content: Control
var _hosts_box: VBoxContainer
var _name_edit: LineEdit
var _ip_edit: LineEdit
var _notice: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBackground.new())
	_content = Control.new()
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_content)
	Net.lobby_changed.connect(_rebuild)
	Net.hosts_changed.connect(_refresh_hosts)
	Net.disconnected.connect(func(_r: String) -> void: _rebuild())
	_rebuild()


func _exit_tree() -> void:
	Net.stop_browsing()


func _rebuild() -> void:
	for c in _content.get_children():
		c.queue_free()
	_hosts_box = null
	if Net.is_in_lobby():
		Net.stop_browsing()
		_build_lobby()
	elif Net.active:
		_build_connecting()
	else:
		_build_browse()


# ---------------------------------------------------------------------------
# Spiel suchen / eröffnen
# ---------------------------------------------------------------------------

func _build_browse() -> void:
	_title("LAN-SPIEL", "Alle Handys im selben WLAN – oder im Hotspot eines der Handys.")
	_notice = UiKit.label(Game.notice, 8, UiKit.MAGENTA, HORIZONTAL_ALIGNMENT_CENTER)
	_notice.position = Vector2(0, 44)
	_notice.size = Vector2(640, 10)
	_content.add_child(_notice)
	Game.notice = ""

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.position = Vector2(24, 62)
	left.custom_minimum_size = Vector2(280, 0)
	_content.add_child(left)
	left.add_child(UiKit.label("DEIN NAME", 8, UiKit.MUTED))
	_name_edit = _line_edit(String(Game.settings.get("name", "")), "Name", 12)
	_name_edit.text_changed.connect(func(t: String) -> void:
		Game.settings["name"] = t.strip_edges()
		Game.save_settings())
	left.add_child(_name_edit)
	left.add_child(_spacer(4))
	var host := UiKit.button("SPIEL ERÖFFNEN", Vector2(280, 30), true)
	host.pressed.connect(_on_host)
	left.add_child(host)
	left.add_child(UiKit.label("Dein Handy wird zum Host. Andere treten bei.", 8, UiKit.MUTED))
	left.add_child(_spacer(8))
	left.add_child(UiKit.label("PER IP BEITRETEN", 8, UiKit.MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_ip_edit = _line_edit("", "z. B. 192.168.0.12", 15)
	_ip_edit.custom_minimum_size = Vector2(170, 26)
	row.add_child(_ip_edit)
	var connect_btn := UiKit.button("VERBINDEN", Vector2(104, 26))
	connect_btn.add_theme_font_size_override("font_size", 8)
	connect_btn.pressed.connect(func() -> void: _join(_ip_edit.text.strip_edges()))
	row.add_child(connect_btn)
	left.add_child(row)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.position = Vector2(336, 62)
	right.custom_minimum_size = Vector2(280, 0)
	_content.add_child(right)
	right.add_child(UiKit.label("GEFUNDENE SPIELE IM WLAN", 8, UiKit.MUTED))
	_hosts_box = VBoxContainer.new()
	_hosts_box.add_theme_constant_override("separation", 6)
	right.add_child(_hosts_box)
	Net.start_browsing()
	_refresh_hosts()

	var back := UiKit.button("ZURÜCK", Vector2(120, 28))
	back.position = Vector2(16, 322)
	back.pressed.connect(func() -> void: Game.goto_menu())
	_content.add_child(back)


func _refresh_hosts() -> void:
	if _hosts_box == null:
		return
	for c in _hosts_box.get_children():
		c.queue_free()
	if Net.found_hosts.is_empty():
		var dots := ".".repeat(1 + int(Time.get_ticks_msec() / 500) % 3)
		_hosts_box.add_child(UiKit.label("Suche läuft" + dots, 8, UiKit.TEXT))
		_hosts_box.add_child(UiKit.label("Noch nichts gefunden? Dann per IP beitreten.", 8, UiKit.MUTED))
		return
	for ip in Net.found_hosts:
		var h: Dictionary = Net.found_hosts[ip]
		var mode_name := "TEAM-CRASH" if h.get("mode") == "team_crash" else "DUELL"
		var b := UiKit.button("%s · %d/%d · %s" % [String(h.get("name", "?")), int(h.get("n", 0)),
			int(h.get("max", 6)), mode_name], Vector2(280, 28))
		b.add_theme_font_size_override("font_size", 8)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var target_ip := String(ip)
		b.pressed.connect(func() -> void: _join(target_ip))
		_hosts_box.add_child(b)


func _on_host() -> void:
	var err := Net.host(_player_name(), String(Game.pending.get("char", "overclock")))
	if err != OK:
		Game.notice = "Spiel konnte nicht eröffnet werden (Fehler %d). Ist Port %d frei?" % [err, Net.PORT]
		_rebuild()


func _join(ip: String) -> void:
	if not ip.is_valid_ip_address():
		Game.notice = "„%s“ ist keine gültige IP-Adresse." % ip
		_rebuild()
		return
	var err := Net.join(ip, _player_name(), String(Game.pending.get("char", "overclock")))
	if err != OK:
		Game.notice = "Verbindung konnte nicht aufgebaut werden (Fehler %d)." % err
	_rebuild()


func _player_name() -> String:
	var n := String(Game.settings.get("name", "")).strip_edges()
	return n if not n.is_empty() else "Spieler"


func _build_connecting() -> void:
	_title("VERBINDE …", "Warte auf Antwort vom Host.")
	var cancel := UiKit.button("ABBRECHEN", Vector2(140, 28))
	cancel.position = Vector2(16, 322)
	cancel.pressed.connect(func() -> void:
		Net.leave()
		_rebuild())
	_content.add_child(cancel)


# ---------------------------------------------------------------------------
# Lobby
# ---------------------------------------------------------------------------

func _build_lobby() -> void:
	var lobby := Net.lobby
	var mode := String(lobby.get("mode", "team_crash"))
	var team_size := int(Match.MODES[mode]["team_size"])
	var sub := "Host: %s" % String(lobby.get("host_name", "?"))
	if Net.is_host:
		var ips := Net.local_ips()
		sub = "Du bist Host · Deine IP: %s" % (", ".join(ips) if not ips.is_empty() else "unbekannt")
	_title("LOBBY", sub)

	# Modus
	var mode_lbl := "MODUS: %s" % ("TEAM-CRASH 3v3" if mode == "team_crash" else "DUELL 1v1")
	if Net.is_host:
		var mb := UiKit.button(mode_lbl + "  >", Vector2(220, 24))
		mb.add_theme_font_size_override("font_size", 8)
		mb.position = Vector2(210, 44)
		mb.pressed.connect(func() -> void: Net.set_mode("duel" if mode == "team_crash" else "team_crash"))
		_content.add_child(mb)
	else:
		var ml := UiKit.label(mode_lbl, 8, UiKit.YELLOW, HORIZONTAL_ALIGNMENT_CENTER)
		ml.position = Vector2(0, 50)
		ml.size = Vector2(640, 10)
		_content.add_child(ml)

	# Teams
	for team in 2:
		var panel := Panel.new()
		panel.position = Vector2(24 + team * 304, 76)
		panel.size = Vector2(288, 30 + team_size * 22)
		panel.add_theme_stylebox_override("panel", UiKit.style(Color(UiKit.PANEL, 0.92), Fighter.TEAM_COLORS[team]))
		_content.add_child(panel)
		var head := UiKit.label("TEAM BLAU" if team == 0 else "TEAM ORANGE", 8, Fighter.TEAM_COLORS[team])
		head.position = Vector2(10, 7)
		panel.add_child(head)
		var members: Array = []
		for p in lobby.get("players", []):
			if int(p["team"]) == team:
				members.append(p)
		for slot in maxi(team_size, members.size()):
			var y := 24 + slot * 22
			var txt := "– Bot –"
			var col := UiKit.MUTED
			if slot < members.size():
				var p: Dictionary = members[slot]
				var is_me := int(p["id"]) == Net.my_id
				txt = "%s%s · %s" % [String(p["name"]), " (DU)" if is_me else "",
					String(CharacterDefs.get_def(String(p["char"]))["name"])]
				col = UiKit.YELLOW if is_me else UiKit.TEXT
				if slot >= team_size:
					txt += " · schaut zu"
					col = UiKit.MUTED
			var l := UiKit.label(txt, 8, col)
			l.position = Vector2(10, y)
			panel.add_child(l)

	# Eigener Charakter
	var mine := Net.my_player()
	var chooser := HBoxContainer.new()
	chooser.add_theme_constant_override("separation", 8)
	chooser.position = Vector2(110, 182 if team_size == 3 else 142)
	_content.add_child(chooser)
	for id in CharacterDefs.ORDER:
		var b := Button.new()
		b.custom_minimum_size = Vector2(130, 92)
		b.focus_mode = Control.FOCUS_NONE
		var sel := String(mine.get("char", "")) == id
		b.add_theme_stylebox_override("normal", UiKit.style(Color("1a2440") if sel else UiKit.PANEL,
			UiKit.YELLOW if sel else Color(UiKit.CYAN, 0.35), 2 if sel else 1))
		b.add_theme_stylebox_override("hover", UiKit.style(Color("1d2a4a"), UiKit.YELLOW if sel else UiKit.CYAN))
		var cid := String(id)
		b.pressed.connect(func() -> void: Net.choose_char(cid))
		var prev := CharPreview.new().setup(cid, 2.0)
		prev.position = Vector2(39, 4)
		b.add_child(prev)
		var nl := UiKit.label(String(CharacterDefs.get_def(cid)["name"]), 8, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		nl.position = Vector2(0, 72)
		nl.size = Vector2(130, 10)
		b.add_child(nl)
		chooser.add_child(b)

	var leave := UiKit.button("VERLASSEN", Vector2(140, 28))
	leave.position = Vector2(16, 322)
	leave.pressed.connect(func() -> void:
		Net.leave()
		_rebuild())
	_content.add_child(leave)
	if Net.is_host:
		var start := UiKit.button("START", Vector2(160, 28), true)
		start.position = Vector2(464, 322)
		start.pressed.connect(func() -> void: Net.start_match())
		_content.add_child(start)
		var hint := UiKit.label("Freie Plätze füllen Bots.", 8, UiKit.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
		hint.position = Vector2(320, 308)
		hint.size = Vector2(304, 10)
		_content.add_child(hint)
	else:
		var wait := UiKit.label("Warte, bis der Host startet …", 8, UiKit.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
		wait.position = Vector2(320, 332)
		wait.size = Vector2(304, 10)
		_content.add_child(wait)


# ---------------------------------------------------------------------------

func _title(text: String, sub: String) -> void:
	var t := UiKit.label(text, 16, UiKit.YELLOW, HORIZONTAL_ALIGNMENT_CENTER)
	t.position = Vector2(0, 6)
	t.size = Vector2(640, 16)
	_content.add_child(t)
	var s := UiKit.label(sub, 8, UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	s.position = Vector2(0, 28)
	s.size = Vector2(640, 10)
	_content.add_child(s)


func _line_edit(text: String, placeholder: String, max_len: int) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.max_length = max_len
	e.custom_minimum_size = Vector2(280, 26)
	e.add_theme_font_size_override("font_size", 8)
	e.add_theme_stylebox_override("normal", UiKit.style(UiKit.PANEL, Color(UiKit.CYAN, 0.45)))
	e.add_theme_stylebox_override("focus", UiKit.style(UiKit.PANEL_LIGHT, UiKit.CYAN))
	return e


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _process(_delta: float) -> void:
	# „Suche läuft …“-Punkte animieren, solange nichts gefunden wurde
	if _hosts_box and Net.found_hosts.is_empty() and Engine.get_process_frames() % 30 == 0:
		_refresh_hosts()
