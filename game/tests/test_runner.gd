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
	_test_overclock_combo()
	_test_net_sync()
	_test_net_controller()
	_test_net_replication()
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


func _test_overclock_combo() -> void:
	var m := _make_match("duel", "overclock", 31, {"enemies": ["ping"]})
	_skip_countdown(m)
	var me := m.local
	var foe := m.fighters[1]
	foe.controller = null
	me.position = m.arena.cell_center(Vector2i(4, 4))
	foe.position = m.arena.cell_center(Vector2i(5, 4))
	var hp0 := foe.hp
	check(me.try_attack(Vector2.RIGHT), "OVERCLOCK greift an")
	for i in 30:
		me.tick(DT, InputFrame.new())
	check(is_equal_approx(hp0 - foe.hp, 3 * 420.0), "Faustkombo trifft 3× (Schaden %f)" % (hp0 - foe.hp))
	check(foe.knock_t > 0.0 or foe.position.x > m.arena.cell_center(Vector2i(5, 4)).x + 4.0,
		"Dritter Schlag stößt zurück")
	m.queue_free()


# ---------------------------------------------------------------------------
# Netzwerk
# ---------------------------------------------------------------------------

func _test_net_sync() -> void:
	var inp := InputFrame.new()
	inp.move = Vector2(0.6, -0.8)
	inp.attack = true
	inp.attack_aim = Vector2(1, 0)
	inp.ult = true
	var packed := NetSync.pack_input(42, inp)
	var back := NetSync.unpack_input(packed)
	check(NetSync.input_seq(packed) == 42, "Eingabe: Sequenznummer")
	check(back.move.is_equal_approx(inp.move) and back.attack and back.ult and not back.special,
		"Eingabe übersteht Kodierung")

	var a := _make_match("duel", "firewall", 41, {"enemies": ["ping"]})
	var b := _make_match("duel", "firewall", 41, {"enemies": ["ping"]})
	var src := a.fighters[0]
	src.hp = 1234.0
	src.shield_t = 1.5
	src.ult = 0.75
	src.kos = 3
	src.facing = Vector2.UP
	var buf := PackedFloat32Array()
	NetSync.write_fighter(src, buf, false)
	check(buf.size() == NetSync.STATE_LEN, "Zustandslänge stimmt (%d)" % buf.size())
	var dst := b.fighters[0]
	var pos := NetSync.read_fighter(dst, buf, 0)
	check(pos.is_equal_approx(src.position), "Position übertragen")
	check(is_equal_approx(dst.hp, 1234.0) and is_equal_approx(dst.ult, 0.75) and dst.kos == 3
		and is_equal_approx(dst.shield_t, 1.5), "Zustand übertragen")
	# Versteckte Gegner: Position wird nicht verraten
	var hidden := PackedFloat32Array()
	NetSync.write_fighter(src, hidden, true)
	var hp := NetSync.read_fighter(dst, hidden, 0)
	check(dst.net_hidden and hp.x == NetSync.HIDDEN_POS, "Versteckter Gegner ohne Position")
	a.queue_free()
	b.queue_free()


func _test_net_controller() -> void:
	var c := NetController.new(2)
	var f1 := InputFrame.new()
	f1.move = Vector2.RIGHT
	f1.attack = true
	f1.attack_aim = Vector2.UP
	var f2 := InputFrame.new()
	f2.move = Vector2.LEFT
	# Pakete enthalten die letzten Eingaben mehrfach – nichts darf doppelt zählen
	c.receive([NetSync.pack_input(1, f1)])
	c.receive([NetSync.pack_input(1, f1), NetSync.pack_input(2, f2)])
	c.receive([NetSync.pack_input(1, f1)])
	check(c.last_seq == 2, "Höchste Sequenz wird bestätigt")
	var out := c.get_input(null, DT)
	check(out.move == Vector2.LEFT, "Neueste Bewegung gilt")
	check(out.attack and out.attack_aim == Vector2.UP, "Angriff geht nicht verloren")
	check(not c.get_input(null, DT).attack, "Angriff wird nur einmal ausgeführt")


## Host und Client im selben Prozess, direkt verbunden: Der Client muss den Zustand
## des Hosts nachbilden, die eigene Figur vorhersagen und Ereignisse empfangen.
func _test_net_replication() -> void:
	var roster := [
		{"peer": 1, "name": "HOST", "char": "overclock", "team": 0, "slot": 0},
		{"peer": 0, "name": "BOT1", "char": "firewall", "team": 0, "slot": 1},
		{"peer": 0, "name": "BOT2", "char": "ping", "team": 0, "slot": 2},
		{"peer": 2, "name": "CLIENT", "char": "ping", "team": 1, "slot": 0},
		{"peer": 0, "name": "BOT3", "char": "overclock", "team": 1, "slot": 1},
		{"peer": 0, "name": "BOT4", "char": "firewall", "team": 1, "slot": 2},
	]
	var base := {"net": true, "roster": roster, "time": 25.0, "seed": 77}
	var host := _make_match("team_crash", "overclock", 77, base.merged({"net_role": "host", "my_peer": 1}))
	var client := _make_match("team_crash", "ping", 77, base.merged({"net_role": "client", "my_peer": 2}))
	host.net.send_snapshot_fn = func(peer: int, snap: Array) -> void:
		if peer == 2:
			client.net.apply_snapshot(snap)
	host.net.send_events_fn = func(evs: Array) -> void: client.net.apply_events(evs)
	client.net.send_input_fn = func(frames: Array) -> void: host.net.receive_input(2, frames)
	check(client.local != null and client.local.team == 1, "Client steuert Team Orange")
	check(host.fighters[3].controller is NetController, "Host steuert Client-Figur über Netzwerk-Eingaben")
	var kills := 0
	for i in 60 * 14:
		host.step(DT)
		client.step(DT)
	var same_hp := true
	var same_alive := true
	for i in host.fighters.size():
		var hf := host.fighters[i]
		var cf := client.fighters[i]
		if absf(hf.hp - cf.hp) > 0.5:
			same_hp = false
		if hf.alive != cf.alive:
			same_alive = false
		kills += hf.kos
	check(same_hp, "Lebenspunkte auf Client = Host")
	check(same_alive, "Lebend/KO auf Client = Host")
	check(client.score == host.score, "Punktestand synchron (%s / %s)" % [client.score, host.score])
	check(kills > 0, "Im Netzwerk-Match fallen KOs (%d)" % kills)
	var hl := host.fighters[3]
	var cl := client.local
	if hl.alive and cl.alive:
		check(hl.position.distance_to(cl.position) < 16.0,
			"Vorhersage nah an Host-Position (%.1f px)" % hl.position.distance_to(cl.position))
	# Interpolierte Gegner liegen nahe an ihrer Host-Position (≈ 100 ms Verzögerung)
	var far := 0
	for i in host.fighters.size():
		var hf2 := host.fighters[i]
		var cf2 := client.fighters[i]
		if i != 3 and hf2.alive and not cf2.net_hidden and hf2.position.distance_to(cf2.position) > 64.0:
			far += 1
	check(far == 0, "Interpolierte Figuren folgen dem Host (%d zu weit weg)" % far)
	# Verbindungsabbruch: Bot übernimmt
	host.net.peer_left(2)
	check(host.fighters[3].controller is BotController, "Bot übernimmt nach Verbindungsabbruch")
	host.queue_free()
	client.queue_free()
