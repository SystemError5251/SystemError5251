class_name NetController
extends RefCounted
## Steuert auf dem Host den Kämpfer eines Mitspielers anhand seiner übertragenen Eingaben.
## Jedes Paket enthält die letzten Eingaben mehrfach; doppelte werden über die
## Sequenznummer verworfen. Aktionen (Angriff usw.) gehen dadurch auch bei Paketverlust
## nicht verloren.

var peer_id := 0
## Höchste verarbeitete Sequenznummer (wird im Snapshot als Bestätigung zurückgeschickt).
var last_seq := 0
var _move := Vector2.ZERO
var _actions: Array[InputFrame] = []


func _init(p_peer: int = 0) -> void:
	peer_id = p_peer


func receive(frames: Array) -> void:
	for fr in frames:
		var a: PackedFloat32Array = fr
		var seq := NetSync.input_seq(a)
		if seq <= last_seq:
			continue
		last_seq = seq
		var inp := NetSync.unpack_input(a)
		_move = inp.move
		if inp.attack or inp.special or inp.ult:
			_actions.append(inp)


func get_input(_f: Fighter, _delta: float) -> InputFrame:
	var out := InputFrame.new()
	out.move = _move
	for a in _actions:
		if a.attack and not out.attack:
			out.attack = true
			out.attack_aim = a.attack_aim
		if a.special and not out.special:
			out.special = true
			out.special_aim = a.special_aim
		if a.ult and not out.ult:
			out.ult = true
			out.ult_aim = a.ult_aim
	_actions.clear()
	return out
