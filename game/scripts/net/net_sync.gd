class_name NetSync
extends RefCounted
## Kompakte Kodierung von Eingaben und Kämpfer-Zuständen für das Netzwerk (Konzept 11.3).
## Alles wird als PackedFloat32Array übertragen: klein, schnell und ohne Objekt-Overhead.

## Werte pro Kämpfer im Snapshot (siehe write_fighter / read_fighter).
const STATE_LEN := 22
const F_ALIVE := 1
const F_HIDDEN := 2
const F_DASH := 4
const F_KNOCK := 8
## Platzhalter-Position für versteckte Gegner: Der Client erfährt nicht, wo sie sind.
const HIDDEN_POS := -99999.0

const INPUT_LEN := 10
const I_ATTACK := 1
const I_SPECIAL := 2
const I_ULT := 4


static func pack_input(seq: int, inp: InputFrame) -> PackedFloat32Array:
	var flags := 0
	if inp.attack:
		flags |= I_ATTACK
	if inp.special:
		flags |= I_SPECIAL
	if inp.ult:
		flags |= I_ULT
	return PackedFloat32Array([seq, inp.move.x, inp.move.y, flags, inp.attack_aim.x, inp.attack_aim.y,
		inp.special_aim.x, inp.special_aim.y, inp.ult_aim.x, inp.ult_aim.y])


static func input_seq(a: PackedFloat32Array) -> int:
	return int(a[0])


static func unpack_input(a: PackedFloat32Array) -> InputFrame:
	var inp := InputFrame.new()
	if a.size() < INPUT_LEN:
		return inp
	inp.move = Vector2(a[1], a[2]).limit_length(1.0)
	var flags := int(a[3])
	inp.attack = (flags & I_ATTACK) != 0
	inp.attack_aim = Vector2(a[4], a[5]).limit_length(1.0)
	inp.special = (flags & I_SPECIAL) != 0
	inp.special_aim = Vector2(a[6], a[7]).limit_length(1.0)
	inp.ult = (flags & I_ULT) != 0
	inp.ult_aim = Vector2(a[8], a[9]).limit_length(1.0)
	return inp


static func write_fighter(f: Fighter, out: PackedFloat32Array, hidden: bool) -> void:
	var flags := 0
	if f.alive:
		flags |= F_ALIVE
	if hidden:
		flags |= F_HIDDEN
	if f.dash_t > 0.0:
		flags |= F_DASH
	if f.knock_t > 0.0:
		flags |= F_KNOCK
	var pos := Vector2(HIDDEN_POS, HIDDEN_POS) if hidden else f.position
	out.append_array([pos.x, pos.y, f.facing.angle(), f.hp, flags, f.ammo, f.ult, f.shield_t, f.invuln_t,
		f.marked_t, f.overclock_t, f.overheat_t, f.respawn_t, f.cache_t, f.overflow_t, f.slow_t,
		f.special_cd, f.kos, f.deaths, f.damage_dealt, f.last_attack_t, f.attack_cd])


## Überträgt den Zustand auf den Kämpfer (ohne Position) und gibt die Position zurück.
static func read_fighter(f: Fighter, a: PackedFloat32Array, o: int) -> Vector2:
	var flags := int(a[o + 4])
	var was_alive := f.alive
	f.alive = (flags & F_ALIVE) != 0
	if was_alive and not f.alive:
		f.death_fx = 0.0
	f.net_hidden = (flags & F_HIDDEN) != 0
	f.dash_t = 0.05 if (flags & F_DASH) != 0 else 0.0
	f.knock_t = 0.05 if (flags & F_KNOCK) != 0 else 0.0
	f.hp = a[o + 3]
	f.ammo = a[o + 5]
	f.ult = a[o + 6]
	f.shield_t = a[o + 7]
	f.invuln_t = a[o + 8]
	f.marked_t = a[o + 9]
	f.overclock_t = a[o + 10]
	f.overheat_t = a[o + 11]
	f.respawn_t = a[o + 12]
	f.cache_t = a[o + 13]
	f.overflow_t = a[o + 14]
	f.slow_t = a[o + 15]
	f.special_cd = a[o + 16]
	f.kos = int(a[o + 17])
	f.deaths = int(a[o + 18])
	f.damage_dealt = a[o + 19]
	f.last_attack_t = a[o + 20]
	f.attack_cd = a[o + 21]
	if not f.net_hidden and (not f.is_local or f.last_attack_t < 0.3 or f.shield_t > 0.0):
		f.facing = Vector2.from_angle(a[o + 2])
	return Vector2(a[o], a[o + 1])
