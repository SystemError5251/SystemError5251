extends Node
## Headless-Tests der Spiellogik.
## Aufruf: godot --headless --path game res://tests/test_runner.tscn
## Exit-Code 0 = alles grün, 1 = mindestens ein Fehler.

const DT := 1.0 / 60.0

var _fails := 0
var _checks := 0


func _ready() -> void:
	_test_maps()
	_test_collision()
	_test_attacks_and_ammo()
	_test_shield()
	_test_noise_visibility()
	_test_portblock()
	_test_full_match("team_crash", "overclock", 11)
	_test_full_match("team_crash", "ping", 12)
	_test_full_match("duel", "firewall", 13)
	_test_training()
	print("Tests: %d Prüfungen, %d Fehler" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		printerr("FEHLER: ", msg)


func _make_match(mode: String, char_id: String, seed: int, extra := {}) -> Match:
	var m := Match.new()
	m.config = {"mode": mode, "char": char_id, "autopilot": true, "headless": true, "seed": seed, "bot_level": 1}
	m.config.merge(extra, true)
	m.manual = true
	add_child(m)
	return m


func _skip_countdown(m: Match) -> void:
	m.countdown = 0.0
	m.frozen = false


# ---------------------------------------------------------------------------

func _test_maps() -> void:
	for id: String in MapDefs.MAPS:
		var rows := MapDefs.build_rows(id)
		var w := rows[0].length()
		var h := rows.size()
		var counts := {"a": 0, "b": 0}
		for y in h:
			check(rows[y].length() == w, "%s: Zeile %d hat Länge %d statt %d" % [id, y, rows[y].length(), w])
			for x in w:
				var ch := rows[y][x]
				if ch in counts:
					counts[ch] += 1
				# Punktsymmetrie (a <-> b, Dummys nur oben)
				var other := rows[h - 1 - y][w - 1 - x]
				var expect := String(MapDefs.SWAP.get(ch, ch))
				if ch == "D" or other == "D":
					continue
				check(other == expect, "%s: nicht symmetrisch bei (%d,%d)" % [id, x, y])
			check(rows[y][0] == "#" and rows[y][w - 1] == "#", "%s: Rand offen in Zeile %d" % [id, y])
		check(counts["a"] == counts["b"] and counts["a"] > 0, "%s: Spawns ungleich %s" % [id, counts])
		# Alle Spawns müssen sich gegenseitig erreichen können
		var arena := Arena.new()
		var world := Node2D.new()
		add_child(world)
		add_child(arena)
		arena.setup(id, world)
		var a: Vector2 = arena.spawns[0][0]
		var b: Vector2 = arena.spawns[1][0]
		check(arena.find_path(a, b).size() > 2, "%s: kein Weg zwischen den Spawns" % id)
		arena.queue_free()
		world.queue_free()


func _test_collision() -> void:
	var m := _make_match("duel", "overclock", 1)
	var arena := m.arena
	# In Zeile 4 der Arena „Papierkorb“ liegt ab x=11 eine Wand (####)
	var start := arena.cell_center(Vector2i(9, 4))
	var p := arena.move_circle(start, Vector2(200, 0), Fighter.RADIUS)
	check(p.x <= 11 * 32 - Fighter.RADIUS + 0.5, "Kreis darf nicht in die Wand: x=%f" % p.x)
	check(p.x > start.x + 20.0, "Kreis sollte sich bis zur Wand bewegen")
	# Diagonal an der Wand entlanggleiten
	var p2 := arena.move_circle(arena.cell_center(Vector2i(10, 5)), Vector2(60, -60), Fighter.RADIUS)
	check(not arena.circle_hits_solid(p2, Fighter.RADIUS - 0.5), "Kreis steckt nach Gleiten in Wand")
	check(p2.x > arena.cell_center(Vector2i(10, 5)).x, "Gleiten entlang der Wand funktioniert nicht")
	# Sichtlinie durch die Wand ist blockiert
	check(not arena.has_los(arena.cell_center(Vector2i(10, 4)), arena.cell_center(Vector2i(16, 4))),
		"Sichtlinie durch Wand")
	check(arena.has_los(arena.cell_center(Vector2i(2, 4)), arena.cell_center(Vector2i(9, 4))),
		"freie Sichtlinie wird blockiert")
	m.queue_free()


func _test_attacks_and_ammo() -> void:
	var m := _make_match("duel", "ping", 2, {"enemies": ["overclock"]})
	_skip_countdown(m)
	var me := m.local
	var foe := m.fighters[1]
	foe.controller = null
	me.position = m.arena.cell_center(Vector2i(2, 4))
	foe.position = m.arena.cell_center(Vector2i(7, 4))
	var hp0 := foe.hp
	check(me.try_attack(Vector2.RIGHT), "PING sollte angreifen können")
	check(is_equal_approx(hp0 - foe.hp, 1100.0), "Strahl macht 1100 Schaden (war %f)" % (hp0 - foe.hp))
	check(me.ult > 0.0, "Schaden lädt die Ultimate")
	me.attack_cd = 0.0
	check(me.try_attack(Vector2.ZERO), "Auto-Aim-Angriff")
	me.attack_cd = 0.0
	check(me.try_attack(Vector2.RIGHT), "Dritter Angriff")
	me.attack_cd = 0.0
	check(not me.try_attack(Vector2.RIGHT), "Ohne Munition kein Angriff")
	check(foe.alive and foe.hp > 0.0, "Drei Treffer (3300) besiegen OVERCLOCK (4400 LP) noch nicht")
	# Nachladen über die Zeit
	for i in 120:
		me.tick(DT, InputFrame.new())
	check(me.ammo >= 1.0, "Munition lädt nach")
	m.queue_free()


func _test_shield() -> void:
	var m := _make_match("duel", "overclock", 3, {"enemies": ["firewall"]})
	_skip_countdown(m)
	var me := m.local
	var wall := m.fighters[1]
	wall.controller = null
	me.position = m.arena.cell_center(Vector2i(4, 4))
	wall.position = m.arena.cell_center(Vector2i(5, 4))
	check(wall.try_special(Vector2.ZERO), "FIREWALL aktiviert Schild")
	wall.facing = Vector2.LEFT
	var hp0 := wall.hp
	me.try_attack(Vector2.RIGHT)
	check(is_equal_approx(wall.hp, hp0), "Schild blockt Angriff von vorne")
	me.attack_cd = 0.0
	me.position = m.arena.cell_center(Vector2i(6, 4))
	me.try_attack(Vector2.LEFT)
	check(wall.hp < hp0, "Schild blockt nicht von hinten")
	m.queue_free()


func _test_noise_visibility() -> void:
	var m := _make_match("duel", "overclock", 4, {"enemies": ["ping"]})
	_skip_countdown(m)
	var me := m.local
	var foe := m.fighters[1]
	foe.position = m.arena.cell_center(Vector2i(1, 1))   # Rauschen-Feld
	me.position = m.arena.cell_center(Vector2i(8, 4))
	check(foe.in_noise(), "Testposition liegt im Rauschen")
	check(foe.hidden_from(me.team), "Gegner im Rauschen ist versteckt")
	check(not me.hidden_from(foe.team), "Kämpfer außerhalb des Rauschens ist sichtbar")
	me.position = m.arena.cell_center(Vector2i(2, 2))
	check(not foe.hidden_from(me.team), "Nahe Gegner werden sichtbar")
	m.queue_free()


func _test_portblock() -> void:
	var m := _make_match("duel", "firewall", 5, {"enemies": ["ping"]})
	_skip_countdown(m)
	var me := m.local
	m.fighters[1].position = m.arena.cell_center(Vector2i(14, 9))
	me.position = m.arena.cell_center(Vector2i(4, 9))
	me.ult = 1.0
	check(me.try_ult(Vector2.RIGHT), "Port Block auslösbar")
	check(m.arena.temp_walls.size() >= 3, "Port Block setzt Wände (%d)" % m.arena.temp_walls.size())
	for i in 60 * 7:
		m.arena.tick(DT)
	check(m.arena.temp_walls.is_empty(), "Temporäre Wände verschwinden wieder")
	m.queue_free()


func _test_full_match(mode: String, char_id: String, seed: int) -> void:
	var m := _make_match(mode, char_id, seed)
	var got := {}
	m.finished.connect(func(r: Dictionary) -> void: got.merge(r))
	var steps := 0
	while steps < 60 * 260 and got.is_empty():
		m.step(DT)
		steps += 1
	check(m.ended, "%s: Match endet (nach %d s)" % [mode, steps / 60])
	check(not got.is_empty(), "%s: Ergebnis wird gemeldet" % mode)
	var total_kos := 0
	var total_dmg := 0
	for f in m.fighters:
		total_kos += f.kos
		total_dmg += roundi(f.damage_dealt)
	check(total_kos > 0, "%s: Bots erzielen KOs (%d)" % [mode, total_kos])
	print("  %s mit %s: %d s, KOs %d, Schaden %d, Stand %s, Runden %s" % [mode, char_id, steps / 60,
		total_kos, total_dmg, m.score, m.round_wins])
	m.queue_free()


func _test_training() -> void:
	var m := _make_match("training", "overclock", 21)
	var dummies := 0
	for f in m.fighters:
		if f.is_dummy:
			dummies += 1
	check(dummies >= 2, "Training hat Dummys (%d)" % dummies)
	for i in 60 * 25:
		m.step(DT)
	check(m.local.damage_dealt > 0.0, "Autopilot trifft Dummys im Training")
	check(not m.ended, "Training endet nicht von selbst")
	m.queue_free()
