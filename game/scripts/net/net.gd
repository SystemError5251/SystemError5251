extends Node
## LAN-Mehrspieler (Konzept 11.4): Verbindung über ENet/UDP, Lobby, Spielsuche im WLAN
## per UDP-Broadcast und alle Netzwerk-Nachrichten während eines Matches.
## Ein Handy ist Host (Listen-Server): Es simuliert das Match und spielt selbst mit.

signal lobby_changed
signal hosts_changed
signal disconnected(reason: String)

const PORT := 47800
const DISCOVERY_PORT := 47801
const PROTOCOL := 1            # bei Änderungen am Netzwerkformat erhöhen
const ANNOUNCE_INTERVAL := 1.0
const HOST_TIMEOUT := 3.5
const MAX_PLAYERS := {"team_crash": 6, "duel": 2}

var active := false
var is_host := false
var my_id := 0
## Lobby-Zustand: vom Host verwaltet und an alle verteilt.
## {mode, host_name, running, players: [{id, name, char, team}]}
var lobby := {}
## Gefundene Spiele im WLAN: IP -> {name, players, max, mode, running, seen}
var found_hosts := {}
var match_ref: Match = null

## Test-Simulation schlechter Verbindungen (nur Client, Startparameter --net-sim=LAG_MS,VERLUST_PROZENT):
## Eingaben und Snapshots werden um sim_lag_ms verzögert, sim_loss Anteil geht verloren.
var sim_lag_ms := 0
var sim_loss := 0.0

## Statistik für Tests und Fortschrittsberichte
var stats := {"snapshots": 0, "snapshot_bytes": 0, "inputs": 0, "events": 0}

var _peer: ENetMultiplayerPeer
var _udp_out: PacketPeerUDP
var _udp_in: PacketPeerUDP
var _announce_t := 0.0
var _hello := {}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func() -> void: _fail("Verbindung fehlgeschlagen. Stimmt die IP?"))
	multiplayer.server_disconnected.connect(func() -> void: _fail("Die Verbindung zum Host wurde getrennt."))


# ---------------------------------------------------------------------------
# Verbinden
# ---------------------------------------------------------------------------

func host(player_name: String, char_id: String) -> Error:
	leave()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(PORT, 5)
	if err != OK:
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	active = true
	is_host = true
	my_id = 1
	lobby = {"mode": "team_crash", "host_name": player_name, "running": false,
		"players": [{"id": 1, "name": player_name, "char": char_id, "team": 0}]}
	_udp_out = PacketPeerUDP.new()
	_udp_out.set_broadcast_enabled(true)
	_udp_out.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_announce_t = 0.0
	lobby_changed.emit()
	return OK


func join(ip: String, player_name: String, char_id: String) -> Error:
	leave()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(ip, PORT)
	if err != OK:
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	active = true
	is_host = false
	lobby = {}
	_hello = {"name": player_name, "char": char_id}
	return OK


func leave() -> void:
	if _peer:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	active = false
	is_host = false
	my_id = 0
	lobby = {}
	if _udp_out:
		_udp_out.close()
	_udp_out = null


func is_in_lobby() -> bool:
	return active and not lobby.is_empty()


## Eigene IPv4-Adressen im lokalen Netz (für „Per IP beitreten“).
func local_ips() -> PackedStringArray:
	var out := PackedStringArray()
	for ip in IP.get_local_addresses():
		if ip.contains(":") or ip.begins_with("127.") or ip.begins_with("169.254."):
			continue
		out.append(ip)
	return out


func _fail(reason: String) -> void:
	var was_active := active
	leave()
	if was_active:
		disconnected.emit(reason)
		Game.on_net_disconnected(reason)


func _on_connected() -> void:
	my_id = multiplayer.get_unique_id()
	_rpc_hello.rpc_id(1, PROTOCOL, String(_hello.get("name", "Spieler")), String(_hello.get("char", "overclock")))


func _on_peer_connected(_id: int) -> void:
	pass  # Der Client meldet sich mit _rpc_hello; erst dann kommt er in die Lobby.


func _on_peer_disconnected(id: int) -> void:
	if not is_host:
		return
	var players: Array = lobby.get("players", [])
	for i in range(players.size() - 1, -1, -1):
		if int(players[i]["id"]) == id:
			players.remove_at(i)
	if match_ref:
		match_ref.net.peer_left(id)
	_rebalance()
	_broadcast_lobby()


# ---------------------------------------------------------------------------
# Spielsuche im WLAN
# ---------------------------------------------------------------------------

func start_browsing() -> void:
	stop_browsing()
	_udp_in = PacketPeerUDP.new()
	# Broadcast-Empfang: Auf Android hält Godot dafür eine Multicast-Sperre (Berechtigung nötig).
	_udp_in.set_broadcast_enabled(true)
	if _udp_in.bind(DISCOVERY_PORT) != OK:
		_udp_in = null
	found_hosts.clear()
	hosts_changed.emit()


func stop_browsing() -> void:
	if _udp_in:
		_udp_in.close()
	_udp_in = null


func _process(delta: float) -> void:
	if is_host and active and _udp_out and not bool(lobby.get("running", false)):
		_announce_t -= delta
		if _announce_t <= 0.0:
			_announce_t = ANNOUNCE_INTERVAL
			var info := {"g": "glitchbrawl", "v": PROTOCOL, "name": lobby.get("host_name", "Host"),
				"n": (lobby.get("players", []) as Array).size(), "max": max_players(), "mode": lobby.get("mode", "")}
			_udp_out.put_packet(JSON.stringify(info).to_utf8_buffer())
	if _udp_in:
		var changed := false
		while _udp_in.get_available_packet_count() > 0:
			var pkt := _udp_in.get_packet()
			var ip := _udp_in.get_packet_ip()
			var data: Variant = JSON.parse_string(pkt.get_string_from_utf8())
			if data is Dictionary and data.get("g") == "glitchbrawl" and int(data.get("v", -1)) == PROTOCOL:
				var d: Dictionary = data
				d["seen"] = Time.get_ticks_msec() / 1000.0
				found_hosts[ip] = d
				changed = true
		var now := Time.get_ticks_msec() / 1000.0
		for ip in found_hosts.keys():
			if now - float(found_hosts[ip]["seen"]) > HOST_TIMEOUT:
				found_hosts.erase(ip)
				changed = true
		if changed:
			hosts_changed.emit()


# ---------------------------------------------------------------------------
# Lobby
# ---------------------------------------------------------------------------

func max_players() -> int:
	return int(MAX_PLAYERS.get(lobby.get("mode", "team_crash"), 6))


func my_player() -> Dictionary:
	for p in lobby.get("players", []):
		if int(p["id"]) == my_id:
			return p
	return {}


func choose_char(char_id: String) -> void:
	Game.pending["char"] = char_id
	if is_host:
		_set_char(1, char_id)
	elif active:
		_rpc_choose.rpc_id(1, char_id)


func set_mode(mode: String) -> void:
	if not is_host:
		return
	lobby["mode"] = mode
	# Überzählige Spieler im Duell? Dann bleiben sie in der Lobby, starten aber nicht.
	_rebalance()
	_broadcast_lobby()


func _set_char(id: int, char_id: String) -> void:
	if not CharacterDefs.ORDER.has(char_id):
		return
	for p in lobby.get("players", []):
		if int(p["id"]) == id:
			p["char"] = char_id
	_broadcast_lobby()


## Teams abwechselnd in Beitrittsreihenfolge füllen: Host Blau, 2. Spieler Orange …
func _rebalance() -> void:
	var players: Array = lobby.get("players", [])
	for i in players.size():
		players[i]["team"] = i % 2


func _broadcast_lobby() -> void:
	lobby_changed.emit()
	if is_host and active:
		_rpc_lobby.rpc(lobby)


func _unique_name(wanted: String) -> String:
	var base := wanted.strip_edges().substr(0, 12)
	if base.is_empty():
		base = "Spieler"
	var taken := {}
	for p in lobby.get("players", []):
		taken[String(p["name"])] = true
	if not taken.has(base):
		return base
	for i in range(2, 10):
		var n := "%s %d" % [base.substr(0, 10), i]
		if not taken.has(n):
			return n
	return base


@rpc("any_peer", "call_remote", "reliable")
func _rpc_hello(protocol: int, player_name: String, char_id: String) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	var reason := ""
	if protocol != PROTOCOL:
		reason = "Andere Spielversion – bitte bei allen dieselbe App-Version installieren."
	elif bool(lobby.get("running", false)):
		reason = "Das Match läuft bereits."
	elif (lobby.get("players", []) as Array).size() >= 6:
		reason = "Die Lobby ist voll."
	if reason != "":
		_rpc_kick.rpc_id(id, reason)
		get_tree().create_timer(0.5).timeout.connect(func() -> void:
			if _peer:
				_peer.disconnect_peer(id))
		return
	var players: Array = lobby["players"]
	players.append({"id": id, "name": _unique_name(player_name),
		"char": char_id if CharacterDefs.ORDER.has(char_id) else "overclock", "team": 0})
	_rebalance()
	_broadcast_lobby()


@rpc("authority", "call_remote", "reliable")
func _rpc_lobby(state: Dictionary) -> void:
	lobby = state
	lobby_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_kick(reason: String) -> void:
	_fail(reason)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_choose(char_id: String) -> void:
	if is_host:
		_set_char(multiplayer.get_remote_sender_id(), char_id)


# ---------------------------------------------------------------------------
# Match starten und beenden
# ---------------------------------------------------------------------------

## Startet das Match für alle (nur Host). Freie Plätze werden mit Bots gefüllt.
func start_match(extra := {}) -> void:
	if not is_host:
		return
	var mode := String(lobby.get("mode", "team_crash"))
	var cfg := {"mode": mode, "seed": randi(), "net": true, "roster": _build_roster(mode),
		"bot_level": int(Game.settings.get("bot_level", 1))}
	cfg.merge(extra, true)
	lobby["running"] = true
	_broadcast_lobby()
	_rpc_start.rpc(cfg)
	_begin_match(cfg)


func _build_roster(mode: String) -> Array:
	var team_size := int(Match.MODES[mode]["team_size"])
	var names: Array = Match.BOT_NAMES.duplicate()
	names.shuffle()
	var roster: Array = []
	for team in 2:
		var humans: Array = []
		for p in lobby.get("players", []):
			if int(p["team"]) == team:
				humans.append(p)
		for slot in team_size:
			if slot < humans.size():
				var h: Dictionary = humans[slot]
				roster.append({"peer": int(h["id"]), "name": String(h["name"]), "char": String(h["char"]),
					"team": team, "slot": slot})
			else:
				roster.append({"peer": 0, "name": String(names.pop_back()),
					"char": CharacterDefs.ORDER[randi() % CharacterDefs.ORDER.size()], "team": team, "slot": slot})
	return roster


@rpc("authority", "call_remote", "reliable")
func _rpc_start(cfg: Dictionary) -> void:
	_begin_match(cfg)


func _begin_match(cfg: Dictionary) -> void:
	var c := cfg.duplicate(true)
	c["net_role"] = "host" if is_host else "client"
	c["my_peer"] = my_id
	Game.start_net_match(c)


## Host: alle zurück in die Lobby (nach dem Ergebnis-Bildschirm).
func return_to_lobby() -> void:
	if not is_host:
		return
	lobby["running"] = false
	_broadcast_lobby()
	_rpc_to_lobby.rpc()
	Game.goto_lan()


@rpc("authority", "call_remote", "reliable")
func _rpc_to_lobby() -> void:
	Game.goto_lan()


# ---------------------------------------------------------------------------
# Nachrichten im Match (werden an MatchNet weitergereicht)
# ---------------------------------------------------------------------------

func send_input(frames: Array) -> void:
	if not active or is_host:
		return
	if sim_loss > 0.0 and randf() < sim_loss:
		return
	if sim_lag_ms > 0:
		get_tree().create_timer(sim_lag_ms / 1000.0, true, true, true).timeout.connect(func() -> void:
			if active:
				_rpc_input.rpc_id(1, frames))
		return
	_rpc_input.rpc_id(1, frames)


func send_snapshot(peer: int, snap: Array) -> void:
	if active and is_host:
		stats["snapshots"] = int(stats["snapshots"]) + 1
		stats["snapshot_bytes"] = int(stats["snapshot_bytes"]) + var_to_bytes(snap).size()
		_rpc_snapshot.rpc_id(peer, snap)


func send_events(evs: Array) -> void:
	if active and is_host:
		_rpc_events.rpc(evs)


func send_end(result: Dictionary) -> void:
	if active and is_host:
		lobby["running"] = false
		_rpc_end.rpc(result)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _rpc_input(frames: Array) -> void:
	stats["inputs"] = int(stats["inputs"]) + 1
	if is_host and match_ref and match_ref.net:
		match_ref.net.receive_input(multiplayer.get_remote_sender_id(), frames)


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _rpc_snapshot(snap: Array) -> void:
	if sim_loss > 0.0 and randf() < sim_loss:
		return
	if sim_lag_ms > 0:
		get_tree().create_timer(sim_lag_ms / 1000.0, true, true, true).timeout.connect(func() -> void:
			_apply_snapshot(snap))
		return
	_apply_snapshot(snap)


func _apply_snapshot(snap: Array) -> void:
	stats["snapshots"] = int(stats["snapshots"]) + 1
	if match_ref and match_ref.net:
		match_ref.net.apply_snapshot(snap)


@rpc("authority", "call_remote", "reliable")
func _rpc_events(evs: Array) -> void:
	stats["events"] = int(stats["events"]) + evs.size()
	if match_ref and match_ref.net:
		match_ref.net.apply_events(evs)


@rpc("authority", "call_remote", "reliable")
func _rpc_end(result: Dictionary) -> void:
	lobby["running"] = false
	if match_ref and match_ref.net:
		match_ref.net.end_from_host(result)
	else:
		Game.on_match_finished(result)
