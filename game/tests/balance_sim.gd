extends Node
## Balancing-Simulation: Bots spielen gegeneinander, Ergebnisse pro Charakter.
## Aufruf: godot --headless --path game res://tests/balance_sim.tscn -- --duels=10 --teams=12

const DT := 1.0 / 60.0


func _ready() -> void:
	var duels := 10
	var teams := 12
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--duels="):
			duels = int(a.trim_prefix("--duels="))
		elif a.begins_with("--teams="):
			teams = int(a.trim_prefix("--teams="))
	var ids: Array[String] = CharacterDefs.ORDER
	print("== Duelle (je Paarung %d, Bot gegen Bot, Stärke normal) ==" % duels)
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var wins := [0, 0]
			var seconds := 0.0
			for k in duels:
				# Seiten abwechseln, damit kein Spawn-Vorteil entsteht
				var swap := k % 2 == 1
				var a := ids[j] if swap else ids[i]
				var b := ids[i] if swap else ids[j]
				var r := _play("duel", a, [b], 1000 + k)
				seconds += float(r["duration"])
				var w := int(r["winner"])
				if w >= 0:
					var winner_id := a if w == 0 else b
					wins[0 if winner_id == ids[i] else 1] += 1
			print("%-9s vs %-9s  Siege %2d : %2d   Ø Dauer %4.0f s" % [ids[i], ids[j], wins[0], wins[1], seconds / duels])

	print("== Team-Crash (%d Matches, zufällige Teams) ==" % teams)
	var agg := {}
	for id in ids:
		agg[id] = {"n": 0, "dmg": 0.0, "kos": 0, "deaths": 0}
	var total_t := 0.0
	for k in teams:
		var pick: String = ids[k % ids.size()]
		var r := _play("team_crash", pick, [], 2000 + k)
		total_t += float(r["duration"])
		for s: Dictionary in r["stats"]:
			var e: Dictionary = agg[String(s["char"])]
			e["n"] += 1
			e["dmg"] += float(s["damage"])
			e["kos"] += int(s["kos"])
			e["deaths"] += int(s["deaths"])
	print("Ø Matchdauer: %.0f s" % (total_t / teams))
	for id in ids:
		var e: Dictionary = agg[id]
		var n := maxi(1, int(e["n"]))
		# Keine Siegquote: Beide Teams enthalten meist jeden Charakter einmal, sie läge immer bei ~50 %.
		print("%-9s Einsätze %3d  Ø Schaden %6.0f  Ø KOs %4.1f  Ø Tode %4.1f" % [id, n,
			float(e["dmg"]) / n, float(e["kos"]) / n, float(e["deaths"]) / n])
	get_tree().quit()


func _play(mode: String, char_id: String, enemies: Array, seed: int) -> Dictionary:
	seed(seed)
	var m := Match.new()
	m.config = {"mode": mode, "char": char_id, "autopilot": true, "headless": true, "seed": seed,
		"bot_level": 1, "enemies": enemies}
	m.manual = true
	add_child(m)
	var got := {}
	m.finished.connect(func(r: Dictionary) -> void: got.merge(r))
	var steps := 0
	while got.is_empty() and steps < 60 * 400:
		m.step(DT)
		steps += 1
	m.free()
	return got
