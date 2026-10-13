extends Node
## Automatischer Rundgang für Screenshots (Desktop-Build, Startparameter: -- --tour=/pfad).
## Erzeugt reproduzierbare Bilder für Fortschrittsberichte.

var out_dir := ""


var wide := false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	if wide:
		run_wide.call_deferred()
	else:
		_run.call_deferred()


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(file + ".png"))
	print("Screenshot: ", file)


## Rechnet Koordinaten der 640x360-Basisauflösung in Fensterpixel um.
func _to_window(p: Vector2) -> Vector2:
	var win := Vector2(get_window().size)
	var s := minf(win.x / 640.0, win.y / 360.0)
	var vp := get_viewport().get_visible_rect().size
	var off := (win - vp * s) * 0.5
	return off + p * s


func _touch(index: int, p: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = _to_window(p)
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _drag(index: int, p: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = _to_window(p)
	Input.parse_input_event(ev)


func _run() -> void:
	await _wait(1.5)
	await _shot("01_hauptmenue")

	Game.goto_select("team_crash")
	await _wait(1.0)
	await _shot("02_charakterwahl")

	Game.autopilot = true
	Game.start_match("team_crash", "overclock")
	await _wait(1.3)
	await _shot("03_countdown")
	await _wait(8.0)
	await _shot("04_team_crash")

	# Zielvorschau: simulierte Finger auf Bewegungs- und Angriffs-Stick (Spieler muss leben)
	var cur := get_tree().current_scene as Match
	var tries := 0
	while is_instance_valid(cur) and cur.local and not cur.local.alive and tries < 40:
		await _wait(0.25)
		tries += 1
	var attack_center: Vector2 = cur.touch.stick_center("attack") if is_instance_valid(cur) else Vector2(566, 290)
	_touch(1, Vector2(96, 286), true)
	await get_tree().process_frame
	_drag(1, Vector2(118, 276))
	_touch(0, attack_center, true)
	await get_tree().process_frame
	_drag(0, attack_center + Vector2(-26, -14))
	await _wait(0.25)
	await _shot("05_zielvorschau")
	_drag(0, attack_center)
	_touch(0, attack_center, false)
	_touch(1, Vector2(118, 276), false)

	for i in 3:
		await _wait(4.0)
		await _shot("06_kampf_%d" % (i + 1))

	# Match im Zeitraffer regulär zu Ende spielen lassen (Bots auf beiden Seiten)
	var m := get_tree().current_scene as Match
	Engine.time_scale = 4.0
	var guard := 0
	while is_instance_valid(m) and not m.ended and guard < 600:
		await get_tree().create_timer(0.25, true, false, true).timeout
		guard += 1
	Engine.time_scale = 1.0
	await _wait(0.9)
	await _shot("07_match_ende")
	await _wait(3.0)
	await _shot("08_ergebnis")

	Game.start_match("duel", "ping")
	await _wait(9.0)
	await _shot("09_duell")
	await _wait(5.0)
	await _shot("09_duell_2")

	Game.start_match("training", "firewall")
	await _wait(7.0)
	await _shot("10_training")
	await _wait(4.0)
	await _shot("10_training_2")

	Game.goto_settings()
	await _wait(0.8)
	await _shot("11_einstellungen")

	print("Rundgang fertig")
	get_tree().quit()


## Zweiter Lauf mit Breitbild-Auflösung (--resolution 1600x720 -- --tour=… --tour-wide)
func run_wide() -> void:
	Game.autopilot = true
	Game.start_match("team_crash", "firewall")
	await _wait(7.0)
	# Die Viewport-Textur enthält keine Ränder; so sieht es im Fenster/auf dem Handy aus:
	await RenderingServer.frame_post_draw
	var content := get_viewport().get_texture().get_image()
	var win := get_window().size
	var full := Image.create(win.x, win.y, false, content.get_format())
	full.fill(Color.BLACK)
	full.blit_rect(content, Rect2i(Vector2i.ZERO, content.get_size()), (win - content.get_size()) / 2)
	full.save_png(out_dir.path_join("12_breitbild_20zu9.png"))
	get_tree().quit()
