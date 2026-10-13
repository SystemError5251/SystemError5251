extends Node
## Automatischer LAN-Test mit zwei Spielinstanzen (Host + Client), z. B. auf einem Rechner:
##   godot --path game -- --net-host=40 [--net-shots=DIR]
##   godot --path game -- --net-join=127.0.0.1 [--net-shots=DIR]
##   godot --path game -- --net-join=discover          (Host per WLAN-Suche finden)
## Beide Seiten spielen per Autopilot. Ergebnisse stehen als „NETTEST …“-Zeilen in der Ausgabe.
## Exit-Code 0 = Erfolg.

var args: PackedStringArray
var _shots := ""
var _char := "overclock"


func _ready() -> void:
	for a in args:
		if a.begins_with("--net-shots="):
			_shots = a.trim_prefix("--net-shots=")
			DirAccess.make_dir_recursive_absolute(_shots)
		elif a.begins_with("--net-char="):
			_char = a.trim_prefix("--net-char=")
	Game.autopilot = true
	Game.pending["char"] = _char
	for a in args:
		if a.begins_with("--net-host"):
			var t := 40.0
			if a.contains("="):
				t = float(a.get_slice("=", 1))
			_run_host.call_deferred(t)
			return
		if a.begins_with("--net-join="):
			_run_client.call_deferred(a.trim_prefix("--net-join="))
			return


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _shot(file: String) -> void:
	if _shots.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shots.path_join(file + ".png"))


func _done(ok: bool, msg: String) -> void:
	print("NETTEST %s %s" % ["OK" if ok else "FEHLER", msg])
	await _wait(0.5)
	Net.leave()
	get_tree().quit(0 if ok else 1)


func _scene_is(path: String) -> bool:
	var cur := get_tree().current_scene
	return cur != null and cur.scene_file_path == path


func _wait_for(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await _wait(0.1)
		t += 0.1
	return false


# ---------------------------------------------------------------------------

func _run_host(match_time: float) -> void:
	await _wait(0.5)
	var err := Net.host("HOST", _char)
	if err != OK:
		await _done(false, "Host konnte nicht starten (%d)" % err)
		return
	Game.goto_lan()
	var joined := await _wait_for(func() -> bool: return (Net.lobby.get("players", []) as Array).size() >= 2, 30.0)
	if not joined:
		await _done(false, "kein Client beigetreten")
		return
	await _wait(1.0)
	await _shot("lan_lobby_host")
	Net.start_match({"time": match_time})
	await _wait(6.0)
	await _shot("lan_match_host")
	var ended := await _wait_for(func() -> bool: return _scene_is(Game.SCENE_RESULT), match_time + 25.0)
	if not ended:
		await _done(false, "Match wurde nicht beendet")
		return
	await _wait(1.0)
	await _shot("lan_ergebnis_host")
	var snaps := int(Net.stats["snapshots"])
	var bytes := int(Net.stats["snapshot_bytes"])
	var avg := bytes / maxi(1, snaps)
	print("NETTEST HOST snapshots_gesendet=%d mittel_bytes=%d kb_pro_s_pro_client=%.1f inputs=%d" % [snaps, avg,
		avg * 30.0 / 1024.0, int(Net.stats["inputs"])])
	Net.return_to_lobby()
	await _wait(2.0)
	await _done(true, "Host: Lobby → Match → Ergebnis → Lobby")


func _run_client(ip: String) -> void:
	await _wait(0.5)
	if ip == "discover":
		Net.start_browsing()
		var found := await _wait_for(func() -> bool: return not Net.found_hosts.is_empty(), 10.0)
		Net.stop_browsing()
		if not found:
			await _done(false, "kein Spiel im WLAN gefunden")
			return
		ip = String(Net.found_hosts.keys()[0])
		print("NETTEST CLIENT spiel_gefunden=%s" % ip)
	var err := Net.join(ip, "CLIENT", _char)
	if err != OK:
		await _done(false, "Verbindung fehlgeschlagen (%d)" % err)
		return
	Game.goto_lan()
	var in_lobby := await _wait_for(func() -> bool: return Net.is_in_lobby(), 15.0)
	if not in_lobby:
		await _done(false, "Lobby nicht erreicht")
		return
	Net.choose_char("ping")
	await _wait(1.0)
	await _shot("lan_lobby_client")
	var started := await _wait_for(func() -> bool: return _scene_is(Game.SCENE_MATCH), 30.0)
	if not started:
		await _done(false, "Match nicht gestartet")
		return
	await _wait(8.0)
	await _shot("lan_match_client")
	var m := get_tree().current_scene as Match
	var snaps := 0
	var corr := 0
	var ended := false
	var t := 0.0
	while t < 200.0:
		if is_instance_valid(m) and m.net:
			snaps = m.net.snapshots
			corr = m.net.corrections
		if _scene_is(Game.SCENE_RESULT):
			ended = true
			break
		await _wait(0.2)
		t += 0.2
	if not ended:
		await _done(false, "kein Ergebnis empfangen")
		return
	await _wait(1.0)
	await _shot("lan_ergebnis_client")
	var r := Game.last_result
	print("NETTEST CLIENT snapshots=%d korrekturen=%d ereignisse=%d sieger=%d eigenes_team=%d" % [snaps, corr,
		int(Net.stats["events"]), int(r.get("winner", -9)), int(r.get("local_team", -9))])
	var back := await _wait_for(func() -> bool: return _scene_is(Game.SCENE_LAN), 15.0)
	await _done(back and snaps > 100, "Client: Lobby → Match → Ergebnis → Lobby")
