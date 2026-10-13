class_name Fighter
extends Node2D
## Ein Kämpfer in der Arena: Bewegung, Angriffe, Fähigkeiten, Statuseffekte, Darstellung.
## Die Simulation läuft ausschließlich in tick(), das vom Match in fester Reihenfolge
## aufgerufen wird. So lässt sich derselbe Code später auf dem Server ausführen.

const TILE := 32.0
const RADIUS := 9.0
const HIT_RADIUS := 11.0
const MAX_AMMO := 3.0
const REGEN_DELAY := 3.0
const REGEN_RATE := 0.12
const SPAWN_PROTECTION := 1.5

const TEAM_COLORS := [Color("2d8cff"), Color("ff8a1f")]

var match_ref: Match
var arena: Arena
var id := 0
var char_id := ""
var def: Dictionary
var team := 0
var display_name := ""
var is_local := false
var is_dummy := false
var controller: Object = null
var spawn_index := 0

var hp := 0.0
var max_hp := 0.0
var alive := true
var respawn_t := -1.0
var ammo := MAX_AMMO
var attack_cd := 0.0
var special_cd := 0.0
var ult := 0.0
var combo := 0
var facing := Vector2.RIGHT
var velocity := Vector2.ZERO
var last_hurt_t := 99.0
var last_attack_t := 99.0
var last_attacker: Fighter = null

# Statuseffekte (Restzeit in Sekunden)
var slow_t := 0.0
var cache_t := 0.0
var overflow_t := 0.0
var overclock_t := 0.0
var overheat_t := 0.0
var shield_t := 0.0
var invuln_t := 0.0
var marked_t := 0.0

# Dash / Rückstoß
var dash_t := 0.0
var dash_vel := Vector2.ZERO
var dash_damage := 0.0
var dash_hits: Array = []
var knock_t := 0.0
var knock_vel := Vector2.ZERO

# Statistik
var kos := 0
var deaths := 0
var damage_dealt := 0.0

# Darstellung
var sprite: Sprite2D
var flash := 0.0
var alpha := 1.0
var death_fx := 0.0
var _anim_t := 0.0
var _shader: ShaderMaterial

const FIGHTER_SHADER := preload("res://shaders/fighter.gdshader")


func setup(p_match: Match, p_char: String, p_team: int, p_name: String) -> void:
	match_ref = p_match
	arena = p_match.arena
	char_id = p_char
	def = CharacterDefs.get_def(p_char)
	team = p_team
	display_name = p_name
	max_hp = float(def["hp"])
	hp = max_hp
	sprite = Sprite2D.new()
	sprite.texture = load(String(def["sprite"]))
	sprite.hframes = 6
	sprite.offset = Vector2(0, -14)
	_shader = ShaderMaterial.new()
	_shader.shader = FIGHTER_SHADER
	sprite.material = _shader
	add_child(sprite)


# ---------------------------------------------------------------------------
# Werte mit Statuseffekten
# ---------------------------------------------------------------------------

func speed_px() -> float:
	var s := float(def["speed"]) * TILE
	if slow_t > 0.0:
		s *= 0.65
	if cache_t > 0.0:
		s *= 1.3
	if overclock_t > 0.0:
		s *= float(def["ult"].get("boost", 1.0))
	if overheat_t > 0.0:
		s *= 0.7
	if shield_t > 0.0:
		s *= 0.8
	return s


func attack_speed_mult() -> float:
	return float(def["ult"].get("boost", 1.0)) if overclock_t > 0.0 else 1.0


func damage_mult() -> float:
	return 1.25 if overflow_t > 0.0 else 1.0


func reload_time() -> float:
	return float(def["attack"]["reload"]) / attack_speed_mult()


func attack_range_px() -> float:
	return float(def["attack"]["range"]) * TILE


func in_noise() -> bool:
	return arena.is_noise_at(position)


func ult_ready() -> bool:
	return ult >= 1.0


## Versteckt im Rauschen-Feld? Gegner sehen den Kämpfer dann nicht,
## außer sie sind sehr nah, er ist markiert oder hat gerade angegriffen.
func hidden_from(viewer_team: int) -> bool:
	if viewer_team == team or not alive:
		return false
	if not in_noise():
		return false
	if marked_t > 0.0 or last_attack_t < 1.0 or last_hurt_t < 0.6:
		return false
	for f in match_ref.fighters:
		if f.alive and f.team == viewer_team and f.position.distance_to(position) < 2.2 * TILE:
			return false
	return true


func shield_dir() -> Vector2:
	return facing


# ---------------------------------------------------------------------------
# Simulation
# ---------------------------------------------------------------------------

func tick(delta: float, inp: InputFrame) -> void:
	if not alive:
		_tick_dead(delta)
		return
	_tick_timers(delta)
	if is_dummy:
		return

	var motion := Vector2.ZERO
	if dash_t > 0.0:
		motion = dash_vel * delta
	elif knock_t > 0.0:
		motion = knock_vel * delta
	else:
		var mv := inp.move.limit_length(1.0)
		motion = mv * speed_px() * delta
		if mv.length() > 0.15:
			facing = mv.normalized()
	var old := position
	position = arena.move_circle(position, motion, RADIUS)
	velocity = (position - old) / delta
	if dash_t > 0.0:
		_dash_contact()

	if shield_t > 0.0:
		var t := match_ref.nearest_enemy(self, 6.0 * TILE, true)
		if t:
			facing = (t.position - position).normalized()

	if inp.attack:
		try_attack(inp.attack_aim)
	if inp.special:
		try_special(inp.special_aim)
	if inp.ult:
		try_ult(inp.ult_aim)

	ammo = minf(MAX_AMMO, ammo + delta / reload_time())
	if last_hurt_t > REGEN_DELAY and last_attack_t > REGEN_DELAY and hp < max_hp:
		hp = minf(max_hp, hp + max_hp * REGEN_RATE * delta)


func _tick_timers(delta: float) -> void:
	attack_cd = maxf(0.0, attack_cd - delta)
	special_cd = maxf(0.0, special_cd - delta)
	last_hurt_t += delta
	last_attack_t += delta
	slow_t = maxf(0.0, slow_t - delta)
	cache_t = maxf(0.0, cache_t - delta)
	overflow_t = maxf(0.0, overflow_t - delta)
	shield_t = maxf(0.0, shield_t - delta)
	invuln_t = maxf(0.0, invuln_t - delta)
	marked_t = maxf(0.0, marked_t - delta)
	dash_t = maxf(0.0, dash_t - delta)
	knock_t = maxf(0.0, knock_t - delta)
	if overclock_t > 0.0:
		overclock_t -= delta
		if overclock_t <= 0.0:
			overclock_t = 0.0
			overheat_t = float(def["ult"].get("overheat", 0.0))
	else:
		overheat_t = maxf(0.0, overheat_t - delta)


func _tick_dead(delta: float) -> void:
	death_fx = minf(1.0, death_fx + delta * 2.5)
	if respawn_t > 0.0:
		respawn_t -= delta
		if respawn_t <= 0.0:
			respawn()


## Auto-Aim: ohne Zielrichtung wird auf den nächsten sichtbaren Gegner gezielt.
func resolve_aim(aim: Vector2, max_range: float) -> Vector2:
	if aim.length() > 0.2:
		return aim.normalized()
	var t := match_ref.nearest_enemy(self, max_range * 1.15, true)
	if t:
		return (t.position - position).normalized()
	return facing


func try_attack(aim: Vector2) -> bool:
	if attack_cd > 0.0 or ammo < 1.0 or dash_t > 0.0:
		return false
	var atk: Dictionary = def["attack"]
	var kind: String = atk["kind"]
	if kind == "none":
		return false
	var dir := resolve_aim(aim, attack_range_px())
	ammo -= 1.0
	attack_cd = float(atk["cooldown"]) / attack_speed_mult()
	last_attack_t = 0.0
	facing = dir
	match kind:
		"melee":
			_attack_melee(dir, atk)
		"beam":
			_attack_beam(dir, atk)
		"shotgun":
			_attack_shotgun(dir, atk)
	return true


func _attack_melee(dir: Vector2, atk: Dictionary) -> void:
	var reach := float(atk["range"]) * TILE
	var half_arc := deg_to_rad(float(atk["arc"])) * 0.5
	combo = (combo + 1) % 3
	var knock := combo == 0
	for e in match_ref.enemies_of(self):
		var to := e.position - position
		var dist := to.length()
		if dist > reach + HIT_RADIUS:
			continue
		if dist > HIT_RADIUS * 1.5 and absf(dir.angle_to(to)) > half_arc:
			continue
		match_ref.deal_damage(self, e, float(atk["damage"]), dir)
		if knock and e.alive:
			e.knock_vel = dir * 300.0
			e.knock_t = 0.16
	# Blöcke direkt vor dem Kämpfer
	var front := arena.to_cell(position + dir * (TILE * 0.8))
	if arena.cell_type(front) == Arena.Cell.BLOCK:
		match_ref.hit_block(front, float(atk["damage"]))
	match_ref.fx.slash(position + Vector2(0, -10), dir, reach, Color("ffe14d"), knock)


func _attack_beam(dir: Vector2, atk: Dictionary) -> void:
	var reach := float(atk["range"]) * TILE
	var end := position + dir * reach
	var cast := arena.cast_segment(position, end)
	if cast["hit"]:
		end = cast["pos"]
		var c: Vector2i = cast["cell"]
		if arena.cell_type(c) == Arena.Cell.BLOCK:
			match_ref.hit_block(c, float(atk["damage"]) * 0.5)
	var target := _first_enemy_on_segment(position, end, HIT_RADIUS + 4.0)
	if target:
		end = target.position
		match_ref.deal_damage(self, target, float(atk["damage"]), dir)
	match_ref.fx.beam(position + Vector2(0, -12), end + Vector2(0, -12), Color("3cff8a"), 2.0)


func _attack_shotgun(dir: Vector2, atk: Dictionary) -> void:
	var n: int = atk["pellets"]
	var spread := deg_to_rad(float(atk["spread"]))
	for i in n:
		var t := (float(i) / float(n - 1)) - 0.5 if n > 1 else 0.0
		var d := dir.rotated(t * spread)
		match_ref.spawn_projectile(self, position + d * 6.0, d, float(atk["projectile_speed"]) * TILE,
			float(atk["range"]) * TILE, float(atk["damage"]))
	match_ref.fx.muzzle(position + dir * 10.0 + Vector2(0, -12), Color("ffb02e"))


func _first_enemy_on_segment(a: Vector2, b: Vector2, width: float) -> Fighter:
	var best: Fighter = null
	var best_t := INF
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.001:
		return null
	for e in match_ref.enemies_of(self):
		var t := clampf((e.position - a).dot(ab) / len2, 0.0, 1.0)
		var p := a + ab * t
		if p.distance_to(e.position) <= width and t < best_t:
			best_t = t
			best = e
	return best


func try_special(aim: Vector2) -> bool:
	if special_cd > 0.0 or dash_t > 0.0:
		return false
	var sp: Dictionary = def["special"]
	var kind: String = sp["kind"]
	match kind:
		"dash":
			var dir := resolve_aim(aim, float(sp["distance"]) * TILE)
			var dur := float(sp["duration"])
			dash_vel = dir * float(sp["distance"]) * TILE / dur
			dash_t = dur
			dash_damage = float(sp["damage"])
			dash_hits.clear()
			facing = dir
			match_ref.fx.ring(position + Vector2(0, -8), Color("ffe14d"), 18.0)
		"backjump":
			var dir: Vector2
			if aim.length() > 0.2:
				dir = aim.normalized()
			else:
				var t := match_ref.nearest_enemy(self, 12.0 * TILE, true)
				dir = (position - t.position).normalized() if t else -facing
			var dur2 := float(sp["duration"])
			dash_vel = dir * float(sp["distance"]) * TILE / dur2
			dash_t = dur2
			dash_damage = 0.0
			dash_hits.clear()
			match_ref.fx.ring(position + Vector2(0, -8), Color("3cff8a"), 18.0)
		"shield":
			shield_t = float(sp["duration"])
			match_ref.fx.ring(position + Vector2(0, -10), Color("27e1ff"), 22.0)
		_:
			return false
	special_cd = float(sp["cooldown"])
	last_attack_t = 0.0
	return true


func _dash_contact() -> void:
	match_ref.fx.afterimage(self)
	if dash_damage <= 0.0:
		return
	for e in match_ref.enemies_of(self):
		if e in dash_hits:
			continue
		if e.position.distance_to(position) <= HIT_RADIUS * 2.0 + 2.0:
			dash_hits.append(e)
			match_ref.deal_damage(self, e, dash_damage, dash_vel.normalized())


func try_ult(aim: Vector2) -> bool:
	if not ult_ready():
		return false
	var u: Dictionary = def["ult"]
	var kind: String = u["kind"]
	match kind:
		"overclock":
			overclock_t = float(u["duration"])
			overheat_t = 0.0
			match_ref.fx.ring(position + Vector2(0, -10), Color("ffe14d"), 40.0)
		"traceroute":
			var reach := float(u["range"]) * TILE
			var dir := _resolve_ult_aim(aim, reach)
			var end := position + dir * reach
			facing = dir
			for e in match_ref.enemies_of(self):
				var ab := end - position
				var t := clampf((e.position - position).dot(ab) / ab.length_squared(), 0.0, 1.0)
				if (position + ab * t).distance_to(e.position) <= HIT_RADIUS + 5.0:
					match_ref.deal_damage(self, e, float(u["damage"]), dir, false)
					e.marked_t = float(u["mark"])
			match_ref.fx.beam(position + Vector2(0, -12), end + Vector2(0, -12), Color("ff3df2"), 5.0)
		"portblock":
			var dir2 := _resolve_ult_aim(aim, 6.0 * TILE)
			facing = dir2
			var center := position + dir2 * float(u["distance"]) * TILE
			var along := Vector2(0, 1) if absf(dir2.x) >= absf(dir2.y) else Vector2(1, 0)
			var length: int = u["length"]
			var placed := 0
			for k in range(-(length / 2), length / 2 + 1):
				var c := arena.to_cell(center + along * k * TILE)
				if match_ref.cell_occupied(c):
					continue
				if arena.add_temp_wall(c, float(u["duration"])):
					placed += 1
			match_ref.fx.ring(center + Vector2(0, -10), Color("ff8a1f"), 50.0)
		_:
			return false
	ult = 0.0
	last_attack_t = 0.0
	return true


func _resolve_ult_aim(aim: Vector2, reach: float) -> Vector2:
	if aim.length() > 0.2:
		return aim.normalized()
	var t := match_ref.nearest_enemy(self, reach, false)
	if t:
		return (t.position - position).normalized()
	return facing


func take_hit_feedback() -> void:
	flash = 1.0


func die() -> void:
	alive = false
	death_fx = 0.0
	dash_t = 0.0
	knock_t = 0.0
	shield_t = 0.0
	overclock_t = 0.0
	overheat_t = 0.0
	marked_t = 0.0


func respawn() -> void:
	var pts: Array = arena.spawns[team]
	if not pts.is_empty():
		position = pts[spawn_index % pts.size()]
	alive = true
	hp = max_hp
	ammo = MAX_AMMO
	attack_cd = 0.0
	invuln_t = SPAWN_PROTECTION
	slow_t = 0.0
	cache_t = 0.0
	overflow_t = 0.0
	respawn_t = -1.0
	death_fx = 0.0
	last_hurt_t = 99.0
	last_attack_t = 99.0
	velocity = Vector2.ZERO


# ---------------------------------------------------------------------------
# Darstellung
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	_anim_t += delta
	flash = maxf(0.0, flash - delta * 6.0)
	var target_alpha := 1.0
	var viewer := match_ref.view_team()
	if not alive:
		target_alpha = 1.0 - death_fx
	elif hidden_from(viewer):
		target_alpha = 0.0
	elif in_noise():
		target_alpha = 0.55
	alpha = move_toward(alpha, target_alpha, delta * 5.0)
	sprite.modulate.a = alpha
	if invuln_t > 0.0 and alive:
		sprite.modulate.a = alpha * (0.45 if int(_anim_t * 12.0) % 2 == 0 else 1.0)

	if velocity.length() > 6.0 and alive:
		sprite.frame = 2 + int(_anim_t * 9.0) % 4
	else:
		sprite.frame = int(_anim_t * 2.5) % 2
	if absf(facing.x) > 0.1:
		sprite.flip_h = facing.x < 0.0
	_shader.set_shader_parameter("flash", flash)
	var glitch := 0.0
	if not alive:
		glitch = death_fx
	elif overclock_t > 0.0:
		glitch = 0.15
	elif marked_t > 0.0:
		glitch = 0.08
	_shader.set_shader_parameter("glitch", glitch)
	_shader.set_shader_parameter("seed", floorf(_anim_t * 20.0))
	queue_redraw()


func _draw() -> void:
	if not alive or alpha <= 0.01:
		return
	var col: Color = TEAM_COLORS[match_ref.display_team(team)]
	col.a = 0.9 * alpha
	# Team-Ring unter den Füßen (Ellipse)
	draw_set_transform(Vector2(0, 1), 0.0, Vector2(1.0, 0.5))
	draw_arc(Vector2.ZERO, 12.0, 0.0, TAU, 24, col, 2.0 if is_local else 1.0)
	if is_local:
		draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 24, Color(1, 1, 1, 0.25 * alpha), 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if shield_t > 0.0:
		var a := facing.angle()
		var half := deg_to_rad(float(def["special"].get("arc", 140.0))) * 0.5
		var pulse := 0.6 + 0.4 * sin(_anim_t * 18.0)
		draw_arc(Vector2(0, -12), 20.0, a - half, a + half, 16, Color(0.15, 0.88, 1.0, 0.85 * pulse * alpha), 3.0)
	if overclock_t > 0.0:
		for i in 4:
			var ang := _anim_t * 7.0 + i * TAU / 4.0
			var p := Vector2(cos(ang) * 13.0, sin(ang) * 6.0 - 12.0)
			draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), Color("ffe14d"))
