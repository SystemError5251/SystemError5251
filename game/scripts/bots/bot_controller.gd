class_name BotController
extends RefCounted
## Einfache Bot-KI: Ziel wählen, Abstand halten, ausweichen, angreifen,
## Fähigkeiten einsetzen und sich bei wenig Leben zurückziehen.
## Die Stärke (0 = leicht, 1 = normal, 2 = schwer) steuert Reaktionszeit und Zielgenauigkeit.

const TILE := 32.0
const PREFERRED_RANGE := {"overclock": 18.0, "ping": 210.0, "firewall": 70.0}

var match_ref: Match
var level := 1
var _think_t := 0.0
var _react_t := 0.0
var _strafe := 1.0
var _strafe_t := 0.0
var _target: Fighter = null
var _path := PackedVector2Array()
var _path_t := 0.0
var _goal := Vector2.ZERO
var _move := Vector2.ZERO
var _stuck_t := 0.0
var _unstick_t := 0.0
var _unstick_dir := Vector2.ZERO
var _last_pos := Vector2.ZERO
var _rng := RandomNumberGenerator.new()


func _init(p_match: Match, p_level: int = 1) -> void:
	match_ref = p_match
	level = p_level
	_rng.randomize()


func _reaction() -> float:
	return [0.45, 0.25, 0.12][clampi(level, 0, 2)]


func _aim_error() -> float:
	return [0.30, 0.14, 0.05][clampi(level, 0, 2)]


func get_input(f: Fighter, delta: float) -> InputFrame:
	var inp := InputFrame.new()
	_think_t -= delta
	_react_t -= delta
	_strafe_t -= delta
	_path_t -= delta
	if _strafe_t <= 0.0:
		_strafe = -_strafe if _rng.randf() < 0.6 else _strafe
		_strafe_t = _rng.randf_range(0.8, 1.8)

	if _think_t <= 0.0:
		_think_t = 0.15
		_think(f)

	# Festgefahren? Kurz in eine zufällige Richtung ausweichen.
	if _move.length() > 0.5 and f.position.distance_to(_last_pos) < 0.4:
		_stuck_t += delta
	else:
		_stuck_t = 0.0
	_last_pos = f.position
	if _stuck_t > 0.4:
		_stuck_t = 0.0
		_unstick_t = 0.35
		_unstick_dir = Vector2.from_angle(_rng.randf() * TAU)
		_path = PackedVector2Array()
	if _unstick_t > 0.0:
		_unstick_t -= delta
		inp.move = _unstick_dir
	else:
		inp.move = _move

	_combat(f, inp)
	return inp


func _think(f: Fighter) -> void:
	var arena := match_ref.arena
	var t := _pick_target(f)
	_target = t
	var low_hp := f.hp < f.max_hp * 0.3 and not f.ult_ready()

	if t == null:
		# Kein Ziel sichtbar: Power-up holen oder Richtung Arenamitte / Gegnerseite laufen.
		var goal := arena.size_px() * 0.5
		var best := INF
		for pk in match_ref.pickups:
			var d := pk.pos.distance_to(f.position)
			if d < best and d < 10.0 * TILE:
				best = d
				goal = pk.pos
		if best == INF:
			var enemy_spawns: Array = arena.spawns[1 - f.team]
			if not enemy_spawns.is_empty() and match_ref.mode != "training":
				goal = goal.lerp(enemy_spawns[f.spawn_index % enemy_spawns.size()], 0.35)
		_move = _follow_path(f, goal)
		return

	var to := t.position - f.position
	var dist := to.length()
	var los := arena.has_los(f.position, t.position)
	var pref: float = PREFERRED_RANGE.get(f.char_id, 80.0)

	if low_hp:
		# Rückzug Richtung eigenem Spawn, um zu regenerieren.
		var home: Array = arena.spawns[f.team]
		var home_pos: Vector2 = home[0] if not home.is_empty() else f.position - to
		_move = _follow_path(f, home_pos)
		return

	if not los or dist > f.attack_range_px() * 1.6:
		_move = _follow_path(f, t.position)
		return

	var dir := to / maxf(dist, 0.001)
	var radial := 0.0
	if dist > pref + 16.0:
		radial = 1.0
	elif dist < pref - 16.0:
		radial = -1.0
	var side := dir.orthogonal() * _strafe * (0.8 if f.char_id == "ping" else 0.55)
	var mv := (dir * radial + side)
	_move = mv.normalized() if mv.length() > 0.01 else Vector2.ZERO


func _pick_target(f: Fighter) -> Fighter:
	var best: Fighter = null
	var best_score := INF
	for e in match_ref.enemies_of(f):
		if e.hidden_from(f.team):
			continue
		var d := e.position.distance_to(f.position)
		if d > 14.0 * TILE:
			continue
		var s := d + (e.hp / e.max_hp) * 90.0
		if e == _target:
			s -= 40.0
		if s < best_score:
			best_score = s
			best = e
	return best


func _follow_path(f: Fighter, goal: Vector2) -> Vector2:
	if _path_t <= 0.0 or _path.is_empty() or goal.distance_to(_goal) > TILE:
		_goal = goal
		_path = match_ref.arena.find_path(f.position, goal)
		_path_t = 0.6
	while _path.size() > 1 and f.position.distance_to(_path[0]) < 12.0:
		_path.remove_at(0)
	if _path.is_empty():
		var d := goal - f.position
		return d.normalized() if d.length() > 8.0 else Vector2.ZERO
	var next := _path[0]
	if _path.size() == 1 and f.position.distance_to(next) < 8.0:
		return Vector2.ZERO
	return (next - f.position).normalized()


func _combat(f: Fighter, inp: InputFrame) -> void:
	var t := _target
	if t == null or not t.alive or t.hidden_from(f.team):
		return
	var arena := match_ref.arena
	var to := t.position - f.position
	var dist := to.length()
	var los := arena.has_los(f.position, t.position)
	var lead := t.velocity * clampf(dist / 500.0, 0.0, 0.35)
	var aim := (to + lead).normalized().rotated(_rng.randf_range(-_aim_error(), _aim_error()))

	# Ultimate
	if f.ult_ready():
		match f.char_id:
			"overclock":
				if dist < 5.0 * TILE:
					inp.ult = true
			"ping":
				if dist < 13.0 * TILE:
					inp.ult = true
					inp.ult_aim = aim
			"firewall":
				if dist < 5.0 * TILE and los:
					inp.ult = true
					inp.ult_aim = (to).normalized()

	# Spezialfähigkeit
	if f.special_cd <= 0.0:
		match f.char_id:
			"overclock":
				if los and dist > 2.0 * TILE and dist < 4.0 * TILE:
					inp.special = true
					inp.special_aim = aim
			"ping":
				if dist < 3.0 * TILE:
					inp.special = true
					inp.special_aim = -to.normalized()
			"firewall":
				if f.last_hurt_t < 0.4 and dist < 8.0 * TILE:
					inp.special = true

	# Basisangriff
	if _react_t > 0.0 or not los or f.ammo < 1.0:
		return
	if dist <= f.attack_range_px() + Fighter.HIT_RADIUS * 0.5:
		# Bei voller Munition sofort, sonst mit kleiner Pause (spart Munition für Folgeschüsse)
		if f.ammo >= 2.0 or _rng.randf() < 0.5:
			inp.attack = true
			inp.attack_aim = aim
			_react_t = _reaction()
