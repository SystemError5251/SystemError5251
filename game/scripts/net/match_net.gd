class_name MatchNet
extends RefCounted
## Netzwerk-Teil eines Matches (Konzept 11.3).
##
## Host:   simuliert wie im Einzelspieler, schickt 30× pro Sekunde einen Snapshot an jeden
##         Client und sammelt Ereignisse (Effekte, KOs, Blöcke, Banner).
## Client: simuliert nichts selbst. Er schickt seine Eingaben, sagt die eigene Bewegung
##         sofort voraus (Client-Vorhersage), gleicht sie mit dem Host ab (Reconciliation)
##         und zeigt alle anderen Kämpfer mit 100 ms Verzögerung flüssig interpoliert an.

const SNAPSHOT_EVERY := 2          # bei 60 Ticks/s → 30 Snapshots/s
const INTERP_DELAY := 0.1
const SNAP_DISTANCE := 48.0        # größere Abweichungen werden sofort korrigiert

var m: Match
var is_host := false
var is_client := false

# Host
var _tick := 0
var _fx: Array = []                # unzuverlässige Effekt-Ereignisse (im Snapshot)
var _reliable: Array = []          # zuverlässige Ereignisse (eigene Nachricht)
var _controllers := {}             # Peer → NetController

# Client
var _seq := 0
var _sent: Array = []
var _history: Array = []           # [seq, Bewegung, dt]
var _buffers := {}                 # Kämpfer-ID → [[Zeit, Position], …]
var _last_snapshot := -1
var corrections := 0               # Anzahl spürbarer Korrekturen (Statistik)
var snapshots := 0

## Übertragungswege. Standard ist das echte Netzwerk (Net); Tests verbinden
## Host und Client im selben Prozess direkt miteinander.
var send_snapshot_fn: Callable = func(peer: int, snap: Array) -> void: Net.send_snapshot(peer, snap)
var send_events_fn: Callable = func(evs: Array) -> void: Net.send_events(evs)
var send_input_fn: Callable = func(frames: Array) -> void: Net.send_input(frames)


func _init(p_match: Match, role: String) -> void:
	m = p_match
	is_host = role == "host"
	is_client = role == "client"


func register_controller(peer: int, c: NetController) -> void:
	_controllers[peer] = c


# ---------------------------------------------------------------------------
# Host
# ---------------------------------------------------------------------------

func fx(ev: Array) -> void:
	if is_host:
		_fx.append(ev)


func reliable(ev: Array) -> void:
	if is_host:
		_reliable.append(ev)


func receive_input(peer: int, frames: Array) -> void:
	var c: NetController = _controllers.get(peer)
	if c:
		c.receive(frames)


## Ein Mitspieler hat die Verbindung verloren: Ein Bot übernimmt seinen Kämpfer.
func peer_left(peer: int) -> void:
	_controllers.erase(peer)
	for f in m.fighters:
		if f.peer_id == peer:
			f.peer_id = 0
			f.controller = BotController.new(m, int(m.config.get("bot_level", 1)))
			m.overlay.popup(f, "BOT ÜBERNIMMT", Color.WHITE)


func after_host_step() -> void:
	_tick += 1
	if not _reliable.is_empty():
		send_events_fn.call(_reliable)
		_reliable = []
	if _tick % SNAPSHOT_EVERY != 0:
		return
	var header := PackedFloat32Array([
		(1 if m.frozen else 0) | (2 if m.ended else 0), m.countdown, m.time_left,
		m.score[0], m.score[1], m.round_wins[0], m.round_wins[1], m.round_no, m.round_pause])
	var proj := PackedFloat32Array()
	for p in m.projectiles:
		proj.append_array([p.pos.x, p.pos.y])
	var picks := PackedInt32Array()
	for pk in m.pickups:
		picks.append_array([pk.spot, pk.kind])
	for peer in _controllers.keys():
		var c: NetController = _controllers[peer]
		var team := _team_of_peer(int(peer))
		var states := PackedFloat32Array()
		for f in m.fighters:
			# Gegner im Rauschen werden diesem Client gar nicht erst verraten (Anti-Wallhack).
			NetSync.write_fighter(f, states, f.hidden_from(team))
		send_snapshot_fn.call(int(peer), [_tick, c.last_seq, header, states, proj, picks, _fx])
	_fx = []


func _team_of_peer(peer: int) -> int:
	for f in m.fighters:
		if f.peer_id == peer:
			return f.team
	return 0


# ---------------------------------------------------------------------------
# Client
# ---------------------------------------------------------------------------

func client_step(delta: float) -> void:
	m.elapsed += delta
	var local := m.local
	var blocked := m.frozen or m.ended or m.round_pause > 0.0
	if local and local.controller:
		var inp: InputFrame
		if blocked:
			inp = InputFrame.new()
			if local.controller is PlayerController:
				(local.controller as PlayerController).discard()
		else:
			inp = local.controller.get_input(local, delta)
		_seq += 1
		_sent.append(NetSync.pack_input(_seq, inp))
		if _sent.size() > 3:
			_sent.pop_front()
		send_input_fn.call(_sent.duplicate())
		# Eigene Bewegung sofort vorhersagen
		var mv := inp.move.limit_length(1.0)
		if local.alive and local.dash_t <= 0.0 and local.knock_t <= 0.0 and not blocked:
			_history.append([_seq, mv, delta])
			var old := local.position
			local.position = m.arena.move_circle(local.position, mv * local.speed_px() * delta, Fighter.RADIUS)
			local.velocity = (local.position - old) / delta
			if mv.length() > 0.15 and local.last_attack_t > 0.3 and local.shield_t <= 0.0:
				local.facing = mv.normalized()
		else:
			local.velocity = Vector2.ZERO

	# Alle anderen: zwischen zwei Snapshots interpolieren
	var render_t := _now() - INTERP_DELAY
	for f in m.fighters:
		if f == local and local.alive and local.dash_t <= 0.0 and local.knock_t <= 0.0:
			continue
		var buf: Array = _buffers.get(f.id, [])
		if buf.is_empty():
			continue
		var old_p := f.position
		f.position = _sample(buf, render_t)
		f.velocity = (f.position - old_p) / delta
	m.arena.tick(delta)
	for pk in m.pickups:
		pk.t += delta
	m.pickup_layer.queue_redraw()
	m._tick_camera(delta)


func apply_snapshot(s: Array) -> void:
	if not is_client or s.size() < 7:
		return
	var tick := int(s[0])
	if tick <= _last_snapshot:
		return
	_last_snapshot = tick
	snapshots += 1
	var ack := int(s[1])
	var h: PackedFloat32Array = s[2]
	var flags := int(h[0])
	m.frozen = (flags & 1) != 0
	m.ended = (flags & 2) != 0
	m.countdown = h[1]
	m.time_left = h[2]
	m.score = [int(h[3]), int(h[4])]
	m.round_wins = [int(h[5]), int(h[6])]
	m.round_no = int(h[7])
	m.round_pause = h[8]

	var states: PackedFloat32Array = s[3]
	var now := _now()
	for i in m.fighters.size():
		var o := i * NetSync.STATE_LEN
		if o + NetSync.STATE_LEN > states.size():
			break
		var f := m.fighters[i]
		var was_alive := f.alive
		var pos := NetSync.read_fighter(f, states, o)
		if f.net_hidden:
			continue
		var buf: Array = _buffers.get(f.id, [])
		if was_alive != f.alive or buf.is_empty():
			buf.clear()          # Respawn oder erster Snapshot: nicht quer über die Karte gleiten
			f.position = pos
		buf.append([now, pos])
		while buf.size() > 2 and float(buf[1][0]) < now - 1.0:
			buf.pop_front()
		_buffers[f.id] = buf
		if f == m.local:
			_reconcile(pos, ack)

	# Projektile und Power-ups (nur zur Anzeige)
	var proj: PackedFloat32Array = s[4]
	m.projectiles.clear()
	for i in range(0, proj.size() - 1, 2):
		var p := Projectile.new()
		p.pos = Vector2(proj[i], proj[i + 1])
		m.projectiles.append(p)
	var picks: PackedInt32Array = s[5]
	var old_t := {}
	for pk in m.pickups:
		old_t[pk.spot] = pk.t
	m.pickups.clear()
	for i in range(0, picks.size() - 1, 2):
		var pk := Pickup.new()
		pk.spot = picks[i]
		pk.kind = picks[i + 1] as Pickup.Kind
		pk.pos = m.arena.pickup_spots[pk.spot]
		pk.t = float(old_t.get(pk.spot, 0.0))
		m.pickups.append(pk)
	_replay_fx(s[6])


## Abgleich der vorhergesagten eigenen Position mit dem Host: Ausgangspunkt ist die
## Position des Hosts, darauf werden alle noch nicht bestätigten Eingaben erneut angewendet.
func _reconcile(server_pos: Vector2, ack: int) -> void:
	var local := m.local
	while not _history.is_empty() and int(_history[0][0]) <= ack:
		_history.pop_front()
	if not local.alive or local.dash_t > 0.0 or local.knock_t > 0.0 or m.frozen or m.round_pause > 0.0:
		_history.clear()
		local.position = server_pos
		return
	var p := server_pos
	for h in _history:
		var mv: Vector2 = h[1]
		p = m.arena.move_circle(p, mv * local.speed_px() * float(h[2]), Fighter.RADIUS)
	var err := p.distance_to(local.position)
	if err > SNAP_DISTANCE:
		local.position = p
		corrections += 1
	elif err > 0.5:
		local.position = local.position.lerp(p, 0.35)
		if err > 4.0:
			corrections += 1


func _sample(buf: Array, t: float) -> Vector2:
	if t <= float(buf[0][0]):
		return buf[0][1]
	for i in range(buf.size() - 1):
		var a: Array = buf[i]
		var b: Array = buf[i + 1]
		if t <= float(b[0]):
			var k := (t - float(a[0])) / maxf(0.0001, float(b[0]) - float(a[0]))
			return Vector2(a[1]).lerp(Vector2(b[1]), k)
	return buf[buf.size() - 1][1]


## Uhr für die Interpolation: die Simulationszeit des Clients (läuft mit den Physik-Ticks).
func _now() -> float:
	return m.elapsed


func _fighter(id: int) -> Fighter:
	if id >= 0 and id < m.fighters.size():
		return m.fighters[id]
	return null


## Effekte nachspielen, die der Host erzeugt hat.
func _replay_fx(evs: Array) -> void:
	for ev in evs:
		var e: Array = ev
		match String(e[0]):
			"b":
				m.fx.beam(Vector2(e[1], e[2]), Vector2(e[3], e[4]), Color.hex(int(e[5])), float(e[6]))
			"s":
				m.fx.slash(Vector2(e[1], e[2]), Vector2(e[3], e[4]), float(e[5]), Color.hex(int(e[6])), bool(e[7]))
			"r":
				m.fx.ring(Vector2(e[1], e[2]), Color.hex(int(e[3])), float(e[4]))
			"m":
				m.fx.muzzle(Vector2(e[1], e[2]), Color.hex(int(e[3])))
			"k":
				m.fx.sparks(Vector2(e[1], e[2]), Color.hex(int(e[3])), int(e[4]))
			"u":
				m.fx.burst(Vector2(e[1], e[2]), Color.hex(int(e[3])))
			"a":
				var f := _fighter(int(e[1]))
				if f:
					m.fx.afterimage(f)
			"d":
				var target := _fighter(int(e[1]))
				var src := _fighter(int(e[3]))
				if target and src:
					target.take_hit_feedback()
					m.overlay.damage_number(target, float(e[2]), src)
					if target == m.local:
						Game.vibrate(25)
						m.add_shake(2.0)
			"p":
				var t := _fighter(int(e[1]))
				if t:
					m.overlay.popup(t, String(e[2]), Color.hex(int(e[3])))


## Zuverlässige Ereignisse: KOs, Arena-Änderungen, Banner.
func apply_events(evs: Array) -> void:
	if not is_client:
		return
	for ev in evs:
		var e: Array = ev
		match String(e[0]):
			"kill":
				var killer := _fighter(int(e[1]))
				var victim := _fighter(int(e[2]))
				if killer and victim and m.hud:
					m.hud.killfeed(killer, victim)
				if victim == m.local:
					Game.vibrate(90)
				if victim == m.local or killer == m.local:
					m.add_shake(5.0)
			"block":
				m.arena.damage_block(Vector2i(int(e[1]), int(e[2])), float(e[3]))
			"twall":
				m.arena.add_temp_wall(Vector2i(int(e[1]), int(e[2])), float(e[3]))
			"banner":
				if m.hud:
					m.hud.banner(String(e[1]), Color.hex(int(e[2])), float(e[3]))
			"round":
				m.show_round_banner(int(e[1]))
			"end":
				m.show_end_banner(int(e[1]))


## Das Ergebnis vom Host aus eigener Sicht darstellen.
func end_from_host(result: Dictionary) -> void:
	var r := result.duplicate(true)
	var my_team := m.local.team if m.local else 0
	r["local_team"] = my_team
	for s: Dictionary in r.get("stats", []):
		s["local"] = m.local != null and int(s.get("id", -1)) == m.local.id
	Game.on_match_finished(r)
