extends Node
## Globaler Zustand: Einstellungen, ausgewählter Modus/Charakter, Szenenwechsel.

const VERSION := "0.2.0"
const SETTINGS_PATH := "user://settings.cfg"

const SCENE_MENU := "res://scenes/main_menu.tscn"
const SCENE_SELECT := "res://scenes/character_select.tscn"
const SCENE_MATCH := "res://scenes/match.tscn"
const SCENE_RESULT := "res://scenes/result_screen.tscn"
const SCENE_SETTINGS := "res://scenes/settings.tscn"
const SCENE_LAN := "res://scenes/lan.tscn"

var font: Font
var settings := {"haptics": true, "shake": true, "show_fps": false, "bot_level": 1, "name": ""}
var pending := {"mode": "team_crash", "char": "overclock"}
var last_result: Dictionary = {}
## Spieler wird von einer KI gesteuert (Demo/Screenshots: Startparameter --autopilot).
var autopilot := false
## Hinweis, der beim nächsten Bildschirm angezeigt wird (z. B. Verbindungsabbruch)
var notice := ""


func _ready() -> void:
	font = load("res://assets/fonts/pixel.fnt")
	load_settings()
	if String(settings["name"]).is_empty():
		settings["name"] = "Spieler %d" % randi_range(10, 99)
		save_settings()
	get_tree().root.theme = UiKit.make_theme(font)
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a == "--autopilot":
			autopilot = true
		elif a.begins_with("--net-sim="):
			var parts := a.trim_prefix("--net-sim=").split(",")
			Net.sim_lag_ms = int(parts[0])
			Net.sim_loss = float(parts[1]) / 100.0 if parts.size() > 1 else 0.0
		elif a.begins_with("--net-host") or a.begins_with("--net-join="):
			var nt := preload("res://scripts/tools/net_test.gd").new()
			nt.args = args
			add_child(nt)
		elif a.begins_with("--tour="):
			var tour := preload("res://scripts/tools/tour.gd").new()
			tour.out_dir = a.trim_prefix("--tour=")
			tour.wide = "--tour-wide" in args
			add_child(tour)


func goto_menu() -> void:
	get_tree().change_scene_to_file(SCENE_MENU)


func goto_select(mode: String) -> void:
	pending["mode"] = mode
	get_tree().change_scene_to_file(SCENE_SELECT)


func goto_lan() -> void:
	get_tree().change_scene_to_file(SCENE_LAN)


func goto_settings() -> void:
	get_tree().change_scene_to_file(SCENE_SETTINGS)


func start_match(mode: String, char_id: String) -> void:
	pending["mode"] = mode
	pending["char"] = char_id
	pending["autopilot"] = autopilot
	pending["bot_level"] = int(settings.get("bot_level", 1))
	get_tree().change_scene_to_file(SCENE_MATCH)


## LAN-Match starten (Konfiguration vom Host, siehe Net.start_match).
func start_net_match(cfg: Dictionary) -> void:
	pending = cfg
	pending["autopilot"] = autopilot
	for r in cfg.get("roster", []):
		if int(r["peer"]) == int(cfg.get("my_peer", -1)):
			pending["char"] = String(r["char"])
	get_tree().change_scene_to_file(SCENE_MATCH)


## Verbindung im LAN-Spiel verloren: Hinweis merken und zur LAN-Auswahl wechseln.
func on_net_disconnected(reason: String) -> void:
	notice = reason
	var cur := get_tree().current_scene
	if cur and cur.scene_file_path in [SCENE_MATCH, SCENE_RESULT, SCENE_LAN]:
		goto_lan()


func on_match_finished(result: Dictionary) -> void:
	last_result = result
	get_tree().change_scene_to_file(SCENE_RESULT)


## Abstände zu Notch/abgerundeten Ecken in Basis-Pixeln (links, oben, rechts, unten).
## Auf dem Desktop immer 0.
func safe_margins(view: Vector2) -> Vector4:
	if not OS.has_feature("mobile"):
		return Vector4.ZERO
	var win := Vector2(DisplayServer.window_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if win.x <= 0.0 or safe.size.x <= 0.0:
		return Vector4.ZERO
	var s := win.x / view.x
	return Vector4(safe.position.x / s, safe.position.y / s,
		maxf(0.0, win.x - safe.end.x) / s, maxf(0.0, win.y - safe.end.y) / s)


func vibrate(ms: int) -> void:
	if bool(settings.get("haptics", true)) and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	for k in settings.keys():
		settings[k] = cfg.get_value("settings", k, settings[k])


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in settings.keys():
		cfg.set_value("settings", k, settings[k])
	cfg.save(SETTINGS_PATH)
