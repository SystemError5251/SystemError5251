extends Node
## Globaler Zustand: Einstellungen, ausgewählter Modus/Charakter, Szenenwechsel.

const VERSION := "0.1.0"
const SETTINGS_PATH := "user://settings.cfg"

const SCENE_MENU := "res://scenes/main_menu.tscn"
const SCENE_SELECT := "res://scenes/character_select.tscn"
const SCENE_MATCH := "res://scenes/match.tscn"
const SCENE_RESULT := "res://scenes/result_screen.tscn"
const SCENE_SETTINGS := "res://scenes/settings.tscn"

var font: Font
var settings := {"haptics": true, "shake": true, "show_fps": false, "bot_level": 1}
var pending := {"mode": "team_crash", "char": "overclock"}
var last_result: Dictionary = {}
## Spieler wird von einer KI gesteuert (Demo/Screenshots: Startparameter --autopilot).
var autopilot := false


func _ready() -> void:
	font = load("res://assets/fonts/pixel.fnt")
	load_settings()
	get_tree().root.theme = UiKit.make_theme(font)
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a == "--autopilot":
			autopilot = true
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


func goto_settings() -> void:
	get_tree().change_scene_to_file(SCENE_SETTINGS)


func start_match(mode: String, char_id: String) -> void:
	pending["mode"] = mode
	pending["char"] = char_id
	pending["autopilot"] = autopilot
	pending["bot_level"] = int(settings.get("bot_level", 1))
	get_tree().change_scene_to_file(SCENE_MATCH)


func on_match_finished(result: Dictionary) -> void:
	last_result = result
	get_tree().change_scene_to_file(SCENE_RESULT)


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
