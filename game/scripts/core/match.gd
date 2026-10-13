class_name Match
extends Node2D
## Ein Match: baut Arena, Kämpfer, Kamera und HUD auf und führt die Simulation
## in fester Reihenfolge aus (Eingaben → Kämpfer → Projektile → Power-ups → Regeln).

signal finished(result: Dictionary)

const TILE := 32.0
const PICKUP_FIRST := 10.0
const PICKUP_INTERVAL := 25.0
const BOT_NAMES := ["NULLPTR", "SEGFAULT", "DAEMON", "KERNEL", "BUFFER", "SPOOLER", "CRON", "SUDO"]

const MODES := {
	"team_crash": {"title": "TEAM-CRASH", "map": "serverraum", "team_size": 3, "time": 150.0,
		"target": 15, "respawn": 3.0},
	"duel": {"title": "DUELL", "map": "papierkorb", "team_size": 1, "time": 60.0,
		"rounds": 2, "respawn": -1.0},
	"training": {"title": "TRAINING", "map": "labor", "team_size": 1, "time": 0.0, "respawn": 1.0},
}

## Optionale Konfiguration (z. B. aus Tests). Sonst wird Game.pending verwendet.
var config: Dictionary = {}
## Bei true läuft die Simulation nicht automatisch, sondern nur über step() (Tests).
var manual := false

var mode := "team_crash"
var rules: Dictionary
var arena: Arena
var world: Node2D
var fx: FxLayer
var overlay: Overlay
var pickup_layer: Node2D
var camera: Camera2D
var hud: Hud
var touch: TouchControls
## Netzwerk-Teil im LAN-Spiel (sonst null)
var net: MatchNet = null

var fighters: Array[Fighter] = []
var projectiles: Array[Projectile] = []
var pickups: Array[Pickup] = []
var local: Fighter = null

var countdown := 3.0
var frozen := true
var ended := false
var paused := false
var time_left := 0.0
var elapsed := 0.0
var score := [0, 0]
var round_wins := [0, 0]
var round_no := 1
var round_pause := 0.0
var result: Dictionary = {}
var shake := 0.0
var _pickup_timers: Array[float] = []
var _end_t := 0.0
var _rng := RandomNumberGenerator.new()


func _enter_tree() -> void:
	# Im Match wird die volle Bildschirmbreite genutzt. Das sichtbare Spielfeld bleibt
	# trotzdem für alle gleich groß (640 × 360); die Ränder deckt das HUD ab.
	get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND


func _exit_tree() -> void:
	get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	if Net.match_ref == self:
		Net.match_ref = null


func _ready() -> void:
	if config.is_empty():
		config = Game.pending.duplicate()
	mode = String(config.get("mode", "team_crash"))
	rules = (MODES[mode] as Dictionary).duplicate()
	# Optionale Überschreibungen (Tests, kurze LAN-Testspiele)
	for key in ["time", "target"]:
		if config.has(key):
			rules[key] = config[key]
	if bool(config.get("net", false)):
		net = MatchNet.new(self, String(config.get("net_role", "host")))
		Net.match_ref = self
	_rng.seed = int(config.get("seed", Time.get_ticks_usec()))
	time_left = float(rules["time"])

	arena = Arena.new()
	arena.name = "Arena"
	add_child(arena)
	pickup_layer = Node2D.new()
	pickup_layer.name = "Pickups"
	pickup_layer.draw.connect(_draw_pickups)
	add_child(pickup_layer)
	world = Node2D.new()
	world.name = "World"
	world.y_sort_enabled = true
	add_child(world)
	arena.setup(String(rules["map"]), world)
	arena.block_destroyed.connect(_on_block_destroyed)
	arena.temp_wall_added.connect(func(c: Vector2i, dur: float) -> void:
		if net:
			net.reliable(["twall", c.x, c.y, dur]))
	fx = FxLayer.new()
	fx.name = "Fx"
	fx.z_index = 50
	fx.match_ref = self
	add_child(fx)
	overlay = Overlay.new()
	overlay.name = "Overlay"
	overlay.z_index = 100
	overlay.match_ref = self
	add_child(overlay)

	_spawn_fighters()
	for i in arena.pickup_spots.size():
		_pickup_timers.append(PICKUP_FIRST)

	if not bool(config.get("headless", false)):
		camera = Camera2D.new()
		camera.position_smoothing_enabled = true
		camera.position_smoothing_speed = 8.0
		add_child(camera)
		_setup_camera_limits()
		camera.position = local.position if local else arena.size_px() * 0.5
		camera.make_current()
		camera.reset_smoothing()
		finished.connect(Game.on_match_finished)
		if net and net.is_host:
			finished.connect(func(r: Dictionary) -> void: Net.send_end(r))
		hud = Hud.new()
		hud.match_ref = self
		add_child(hud)
		touch = hud.touch
		if local and local.controller is PlayerController:
			(local.controller as PlayerController).touch = touch
		hud.banner("3", Color.WHITE, 0.8)


## LAN-Spiel: Die Aufstellung kommt vom Host (gleiche Reihenfolge auf allen Geräten).
func _spawn_from_roster(roster: Array) -> void:
	var my_peer := int(config.get("my_peer", 1))
	var level := int(config.get("bot_level", 1))
	var autopilot := bool(config.get("autopilot", false))
	for entry in roster:
		var r: Dictionary = entry
		var f := _add_fighter(String(r["char"]), int(r["team"]), String(r["name"]), int(r["slot"]))
		f.peer_id = int(r["peer"])
		if f.peer_id == my_peer and f.peer_id != 0:
			f.is_local = true
			local = f
		if net.is_host:
			if f.peer_id == 0:
				f.controller = BotController.new(self, level)
			elif f.is_local:
				f.controller = _local_controller(autopilot, level)
			else:
				var c := NetController.new(f.peer_id)
				f.controller = c
				net.register_controller(f.peer_id, c)
		elif f.is_local:
			f.controller = _local_controller(autopilot, level)


func _local_controller(autopilot: bool, level: int) -> Object:
	if autopilot:
		return BotController.new(self, level)
	return PlayerController.new()


func _spawn_fighters() -> void:
	if config.has("roster"):
		_spawn_from_roster(config["roster"])
		return
	var player_char := String(config.get("char", "overclock"))
	var autopilot := bool(config.get("autopilot", false))
	var level := int(config.get("bot_level", 1))
	var names: Array = BOT_NAMES.duplicate()
	names.shuffle()
	var roster: Array[String] = CharacterDefs.ORDER.duplicate()
	var team_size := int(rules["team_size"])

	# Team Blau: Spieler + Verbündete
	var allies: Array[String] = []
	for c in roster:
		if c != player_char:
			allies.append(c)
	allies.shuffle()
	for c in config.get("allies", []):
		allies.push_front(String(c))
	var p := _add_fighter(player_char, 0, "DU", 0)
	p.is_local = true
	if autopilot:
		p.controller = BotController.new(self, level)
	else:
		p.controller = PlayerController.new()
	local = p
	for i in range(1, team_size):
		var f := _add_fighter(allies[(i - 1) % allies.size()], 0, String(names.pop_back()), i)
		f.controller = BotController.new(self, level)

	if mode == "training":
		for i in arena.dummy_spots.size():
			var d := _add_fighter("dummy", 1, "DUMMY", i)
			d.is_dummy = true
			d.position = arena.dummy_spots[i]
		return

	# Team Orange: Bots
	var enemies: Array[String] = roster.duplicate()
	enemies.shuffle()
	var forced: Array = config.get("enemies", [])
	for i in range(forced.size() - 1, -1, -1):
		enemies.push_front(String(forced[i]))
	for i in team_size:
		var e := _add_fighter(enemies[i % enemies.size()], 1, String(names.pop_back()), i)
		e.controller = BotController.new(self, level)


func _add_fighter(char_id: String, team: int, display: String, index: int) -> Fighter:
	var f := Fighter.new()
	f.id = fighters.size()
	f.name = "%s_%d" % [char_id, f.id]
	f.spawn_index = index
	world.add_child(f)
	f.setup(self, char_id, team, display)
	var pts: Array = arena.spawns[team]
	f.position = pts[index % pts.size()] if not pts.is_empty() else arena.size_px() * 0.5
	f.facing = Vector2.RIGHT if team == 0 else Vector2.LEFT
	fighters.append(f)
	return f


func _setup_camera_limits() -> void:
	var view := get_viewport_rect().size
	var sz := arena.size_px()
	var margin := 24.0
	var lx := -margin
	var rx := sz.x + margin
	var ty := -margin - 8.0
	var by := sz.y + margin
	if rx - lx < view.x:
		lx = (sz.x - view.x) * 0.5
		rx = lx + view.x
	if by - ty < view.y:
		ty = (sz.y - view.y) * 0.5
		by = ty + view.y
	camera.limit_left = int(lx)
	camera.limit_right = int(rx)
	camera.limit_top = int(ty)
	camera.limit_bottom = int(by)


# ---------------------------------------------------------------------------
# Simulation
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if manual or paused:
		return
	step(delta)


func step(delta: float) -> void:
	if net and net.is_client:
		net.client_step(delta)
		return
	elapsed += delta
	if ended:
		_end_t += delta
		if _end_t > 2.4 and not result.is_empty():
			var r := result
			result = {}
			finished.emit(r)
		_tick_visual_only(delta)
		if net:
			net.after_host_step()
		return
	if frozen:
		_tick_countdown(delta)
	if round_pause > 0.0:
		round_pause -= delta
		if round_pause <= 0.0:
			_start_next_round()

	for f in fighters:
		var inp: InputFrame
		if frozen or round_pause > 0.0 or f.controller == null:
			inp = InputFrame.new()
			if f.controller is PlayerController:
				(f.controller as PlayerController).discard()
		else:
			inp = f.controller.get_input(f, delta)
		f.tick(delta, inp)

	_tick_projectiles(delta)
	_tick_pickups(delta)
	arena.tick(delta)
	if not frozen and round_pause <= 0.0:
		_tick_rules(delta)
	_tick_camera(delta)
	if net:
		net.after_host_step()


func _tick_visual_only(delta: float) -> void:
	for f in fighters:
		f.tick(delta, InputFrame.new())
	_tick_camera(delta)


func _tick_countdown(delta: float) -> void:
	var before := ceili(countdown)
	countdown -= delta
	var now := ceili(countdown)
	if now != before and now > 0:
		_banner(str(now), Color.WHITE, 0.8)
	if countdown <= 0.0:
		frozen = false
		_banner("LOS!", Color("ffe14d"), 0.9)


func _tick_projectiles(delta: float) -> void:
	for p in projectiles:
		var dist := p.speed * delta
		var steps := maxi(1, ceili(dist / 6.0))
		for s in steps:
			var mv := p.dir * (dist / steps)
			p.pos += mv
			p.travelled += mv.length()
			var c := arena.to_cell(p.pos)
			if arena.is_solid(c):
				if arena.cell_type(c) == Arena.Cell.BLOCK:
					hit_block(c, p.damage)
				fx.sparks(p.pos + Vector2(0, -10), Color("ffb02e"), 3)
				p.alive = false
				break
			for e in enemies_of(p.owner_f):
				if e.position.distance_to(p.pos) <= Fighter.HIT_RADIUS + p.radius:
					deal_damage(p.owner_f, e, p.damage, p.dir)
					p.alive = false
					break
			if not p.alive or p.travelled >= p.max_dist:
				p.alive = false
				break
	projectiles = projectiles.filter(func(p: Projectile) -> bool: return p.alive)


func _tick_pickups(delta: float) -> void:
	if mode != "training":
		for i in _pickup_timers.size():
			var occupied := false
			for pk in pickups:
				if pk.spot == i:
					occupied = true
			if occupied:
				continue
			_pickup_timers[i] -= delta
			if _pickup_timers[i] <= 0.0:
				_pickup_timers[i] = PICKUP_INTERVAL
				var pk := Pickup.new()
				pk.kind = _rng.randi_range(0, 2) as Pickup.Kind
				pk.pos = arena.pickup_spots[i]
				pk.spot = i
				pickups.append(pk)
				fx.ring(pk.pos, Pickup.COLORS[pk.kind], 20.0)
	for pk in pickups:
		pk.t += delta
		for f in fighters:
			if f.alive and not f.is_dummy and f.position.distance_to(pk.pos) < 16.0:
				_apply_pickup(f, pk)
				pk.spot = -99
				break
	pickups = pickups.filter(func(pk: Pickup) -> bool: return pk.spot != -99)
	pickup_layer.queue_redraw()


func _apply_pickup(f: Fighter, pk: Pickup) -> void:
	match pk.kind:
		Pickup.Kind.BACKUP:
			f.hp = minf(f.max_hp, f.hp + 1500.0)
			overlay.popup(f, "+1500", Color("2fbf6a"))
		Pickup.Kind.CACHE:
			f.cache_t = 6.0
			overlay.popup(f, "TEMPO!", Color("27e1ff"))
		Pickup.Kind.OVERFLOW:
			f.overflow_t = 8.0
			overlay.popup(f, "SCHADEN!", Color("ff4d4d"))
	fx.ring(pk.pos, Pickup.COLORS[pk.kind], 26.0)


func _tick_rules(delta: float) -> void:
	match mode:
		"team_crash":
			time_left -= delta
			var target := int(rules["target"])
			if score[0] >= target or score[1] >= target or time_left <= 0.0:
				time_left = maxf(time_left, 0.0)
				var winner := -1
				if score[0] != score[1]:
					winner = 0 if score[0] > score[1] else 1
				_end_match(winner)
		"duel":
			time_left -= delta
			if time_left <= 0.0:
				time_left = 0.0
				# Zeit abgelaufen: mehr Leben (in Prozent) gewinnt die Runde
				var a := fighters[0]
				var b := fighters[1]
				var ra := a.hp / a.max_hp if a.alive else 0.0
				var rb := b.hp / b.max_hp if b.alive else 0.0
				_finish_round(-1 if is_equal_approx(ra, rb) else (0 if ra > rb else 1))
		"training":
			pass


func _finish_round(winner: int) -> void:
	if winner >= 0:
		round_wins[winner] += 1
	var needed := int(rules["rounds"])
	if round_wins[0] >= needed or round_wins[1] >= needed:
		_end_match(0 if round_wins[0] > round_wins[1] else 1)
		return
	round_pause = 2.0
	show_round_banner(winner)
	if net:
		net.reliable(["round", winner])


func _start_next_round() -> void:
	round_no += 1
	time_left = float(rules["time"])
	projectiles.clear()
	for f in fighters:
		f.respawn()
		f.invuln_t = 0.0
		f.ult = minf(f.ult, 0.5)
	_banner("RUNDE %d" % round_no, Color("ffe14d"), 1.0)


func _end_match(winner: int) -> void:
	if ended:
		return
	ended = true
	frozen = true
	var stats: Array = []
	for f in fighters:
		stats.append({"id": f.id, "name": f.display_name, "char": f.char_id, "team": f.team, "local": f.is_local,
			"human": f.peer_id != 0, "kos": f.kos, "deaths": f.deaths, "damage": roundi(f.damage_dealt)})
	result = {"mode": mode, "title": rules["title"], "winner": winner, "local_team": view_team(),
		"net": net != null, "score": score.duplicate(), "rounds": round_wins.duplicate(), "duration": elapsed,
		"stats": stats}
	show_end_banner(winner)
	if net:
		net.reliable(["end", winner])


## Banner anzeigen und im LAN-Spiel an alle Clients weitergeben.
func _banner(text: String, col: Color, dur: float) -> void:
	if hud:
		hud.banner(text, col, dur)
	if net:
		net.reliable(["banner", text, col.to_rgba32(), dur])


## Rundenbanner aus Sicht des eigenen Teams.
func show_round_banner(winner: int) -> void:
	if not hud:
		return
	if winner < 0:
		hud.banner("UNENTSCHIEDEN", Color.WHITE, 1.6)
	elif winner == view_team():
		hud.banner("RUNDE GEWONNEN", Fighter.TEAM_COLORS[0], 1.6)
	else:
		hud.banner("RUNDE VERLOREN", Fighter.TEAM_COLORS[1], 1.6)


## Endbanner aus Sicht des eigenen Teams.
func show_end_banner(winner: int) -> void:
	if not hud:
		return
	if winner < 0:
		hud.banner("UNENTSCHIEDEN", Color.WHITE, 2.2)
	elif winner == view_team():
		hud.banner("SIEG!", Color("3cff8a"), 2.2)
	else:
		hud.banner("NIEDERLAGE", Color("ff3df2"), 2.2)


## Beendet das Match vorzeitig (Pause-Menü „Aufgeben“).
func surrender() -> void:
	_end_match(1)
	_end_t = 2.4


# ---------------------------------------------------------------------------
# Schaden & KOs
# ---------------------------------------------------------------------------

func deal_damage(src: Fighter, target: Fighter, amount: float, dir: Vector2, blockable := true) -> float:
	if ended or round_pause > 0.0 or not target.alive or target.team == src.team:
		return 0.0
	if target.invuln_t > 0.0:
		overlay.popup(target, "IMMUN", Color(0.8, 0.8, 1.0))
		return 0.0
	if blockable and target.shield_t > 0.0 and dir != Vector2.ZERO:
		var half := deg_to_rad(float(target.def["special"].get("arc", 140.0))) * 0.5
		if absf(target.shield_dir().angle_to(-dir)) <= half:
			overlay.popup(target, "BLOCK", Color("27e1ff"))
			fx.sparks(target.position + target.shield_dir() * 18.0 + Vector2(0, -12), Color("27e1ff"), 4)
			return 0.0
	var dmg := amount * src.damage_mult() * target.damage_taken_mult()
	target.hp -= dmg
	target.last_hurt_t = 0.0
	target.last_attacker = src
	target.take_hit_feedback()
	src.damage_dealt += dmg
	src.ult = minf(1.0, src.ult + dmg / float(src.def["ult"]["charge"]))
	overlay.damage_number(target, dmg, src)
	if target.is_local:
		Game.vibrate(25)
		add_shake(2.0)
	if target.hp <= 0.0:
		_on_ko(target, src)
	return dmg


func _on_ko(victim: Fighter, killer: Fighter) -> void:
	victim.hp = 0.0
	victim.die()
	victim.deaths += 1
	killer.kos += 1
	fx.burst(victim.position + Vector2(0, -12), Fighter.TEAM_COLORS[display_team(victim.team)])
	add_shake(5.0 if victim.is_local or killer.is_local else 2.0)
	if victim.is_local:
		Game.vibrate(90)
	if hud:
		hud.killfeed(killer, victim)
	if net:
		net.reliable(["kill", killer.id, victim.id])
	var respawn := float(rules["respawn"])
	match mode:
		"team_crash":
			score[killer.team] += 1
			victim.respawn_t = respawn
		"duel":
			if round_pause <= 0.0:
				_finish_round(killer.team)
		"training":
			victim.respawn_t = respawn


func hit_block(c: Vector2i, amount: float) -> void:
	arena.damage_block(c, amount)
	if net:
		net.reliable(["block", c.x, c.y, amount])


func _on_block_destroyed(c: Vector2i) -> void:
	var p := arena.cell_center(c)
	fx.sparks(p + Vector2(0, -8), Color("ff3df2"), 10)
	fx.sparks(p + Vector2(0, -8), Color("8d3bb5"), 8)


func spawn_projectile(owner_f: Fighter, pos: Vector2, dir: Vector2, speed: float, max_dist: float, damage: float) -> void:
	var p := Projectile.new()
	p.owner_f = owner_f
	p.team = owner_f.team
	p.pos = pos
	p.dir = dir
	p.speed = speed
	p.max_dist = max_dist
	p.damage = damage
	projectiles.append(p)


# ---------------------------------------------------------------------------
# Abfragen
# ---------------------------------------------------------------------------

func enemies_of(f: Fighter) -> Array[Fighter]:
	var out: Array[Fighter] = []
	for e in fighters:
		if e.alive and e.team != f.team:
			out.append(e)
	return out


func allies_of(f: Fighter) -> Array[Fighter]:
	var out: Array[Fighter] = []
	for e in fighters:
		if e.alive and e.team == f.team and e != f:
			out.append(e)
	return out


func nearest_enemy(f: Fighter, max_dist: float, require_visible: bool) -> Fighter:
	var best: Fighter = null
	var best_d := max_dist
	for e in enemies_of(f):
		if require_visible and e.hidden_from(f.team):
			continue
		var d := e.position.distance_to(f.position)
		if d <= best_d:
			best_d = d
			best = e
	return best


func cell_occupied(c: Vector2i) -> bool:
	var rect := Rect2(c.x * TILE, c.y * TILE, TILE, TILE)
	for f in fighters:
		if f.alive and rect.grow(Fighter.RADIUS).has_point(f.position):
			return true
	return false


## Aus welcher Team-Sicht wird dargestellt (Sichtbarkeit im Rauschen)?
func view_team() -> int:
	return local.team if local else 0


## Farbe einer Schadenszahl aus Sicht des Betrachters.
func damage_color(src: Fighter, target: Fighter) -> Color:
	if src.is_local:
		return Color("ffe14d")
	if target.is_local:
		return Color("ff5a5a")
	return Color(1, 1, 1, 0.9)


## Das eigene Team wird immer blau dargestellt.
func display_team(team: int) -> int:
	return team if view_team() == 0 else 1 - team


# ---------------------------------------------------------------------------
# Kamera & Darstellung
# ---------------------------------------------------------------------------

func add_shake(amount: float) -> void:
	if Game.settings.get("shake", true):
		shake = minf(8.0, shake + amount)


func _tick_camera(delta: float) -> void:
	if not camera:
		return
	if local:
		camera.position = local.position + Vector2(0, -10)
	elif not fighters.is_empty():
		camera.position = fighters[0].position + Vector2(0, -10)   # Zuschauer
	shake = maxf(0.0, shake - delta * 20.0)
	camera.offset = Vector2(randf_range(-shake, shake), randf_range(-shake, shake)).round()


func _draw_pickups() -> void:
	var tex: Texture2D = preload("res://assets/fx/pickups.png")
	for pk in pickups:
		var bob := sin(pk.t * 4.0) * 2.0
		var col: Color = Pickup.COLORS[pk.kind]
		pickup_layer.draw_set_transform(pk.pos + Vector2(0, 2), 0.0, Vector2(1.0, 0.45))
		pickup_layer.draw_circle(Vector2.ZERO, 9.0, Color(col, 0.35))
		pickup_layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		pickup_layer.draw_texture_rect_region(tex, Rect2(pk.pos + Vector2(-8, -18 + bob), Vector2(16, 16)),
			Rect2(pk.kind * 16, 0, 16, 16))


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and hud and not ended and net == null:
		hud.set_paused(true)
