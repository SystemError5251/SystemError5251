class_name CharacterDefs
extends RefCounted
## Startwerte aller Charaktere (siehe docs/KONZEPT.md, Abschnitt 5).
## Reichweiten und Tempo sind in Kacheln angegeben (1 Kachel = 32 px).

const TILE := 32.0

const ORDER: Array[String] = ["overclock", "ping", "firewall"]

const DEFS := {
	"overclock": {
		"name": "OVERCLOCK",
		"role": "Bruiser",
		"role_color": Color("ffe14d"),
		"sprite": "res://assets/characters/overclock.png",
		"hp": 5000.0,
		"speed": 3.0,
		"attack": {"kind": "melee", "damage": 420.0, "hits": 3, "hit_interval": 0.1, "range": 1.8,
			"arc": 110.0, "reload": 1.1, "cooldown": 0.4},
		# armor: Schadensfaktor während des Dashs (0.5 = halber Schaden)
		"special": {"kind": "dash", "cooldown": 4.5, "distance": 4.0, "damage": 700.0, "duration": 0.22,
			"armor": 0.5},
		"ult": {"kind": "overclock", "charge": 3000.0, "duration": 5.0, "boost": 1.4, "overheat": 2.0},
		"text": {
			"attack": "Faustkombo: 3 × 420 Schaden, der 3. Schlag stößt zurück",
			"special": "Turbo-Dash: 4 Kacheln, 700 Schaden, halber Schaden im Dash",
			"ult": "Übertaktung: 5 s +40 % Tempo & Angriff",
		},
		"bars": {"hp": 0.8, "speed": 0.9, "range": 0.2},
	},
	"ping": {
		"name": "PING",
		"role": "Scharfschütze",
		"role_color": Color("3cff8a"),
		"sprite": "res://assets/characters/ping.png",
		"hp": 2600.0,
		"speed": 2.8,
		"attack": {"kind": "beam", "damage": 1100.0, "range": 10.0, "reload": 1.6, "cooldown": 0.45},
		"special": {"kind": "backjump", "cooldown": 7.0, "distance": 3.0, "duration": 0.18},
		"ult": {"kind": "traceroute", "charge": 3300.0, "damage": 1400.0, "range": 14.0, "mark": 4.0},
		"text": {
			"attack": "Signal: Strahl, 1100 Schaden, Reichweite 10",
			"special": "Rücksprung: 3 Kacheln weg vom Gegner",
			"ult": "Traceroute: Strahl durch Wände, markiert 4 s",
		},
		"bars": {"hp": 0.45, "speed": 0.75, "range": 1.0},
	},
	"firewall": {
		"name": "FIREWALL",
		"role": "Tank",
		"role_color": Color("ff8a1f"),
		"sprite": "res://assets/characters/firewall.png",
		"hp": 5200.0,
		"speed": 2.6,
		"attack": {"kind": "shotgun", "damage": 340.0, "pellets": 4, "spread": 34.0, "range": 4.2,
			"projectile_speed": 15.0, "reload": 1.7, "cooldown": 0.45},
		"special": {"kind": "shield", "cooldown": 8.0, "duration": 2.5, "arc": 140.0},
		"ult": {"kind": "portblock", "charge": 4500.0, "length": 5, "distance": 2.5, "duration": 6.0},
		"text": {
			"attack": "Burst-Paket: 4 × 340 Schaden, kurze Reichweite",
			"special": "Frontschild: blockt 2,5 s alles von vorne",
			"ult": "Port Block: Wand aus 5 Kacheln für 6 s",
		},
		"bars": {"hp": 1.0, "speed": 0.6, "range": 0.45},
	},
	"dummy": {
		"name": "DUMMY",
		"role": "Trainingsziel",
		"role_color": Color("9aa0c0"),
		"sprite": "res://assets/characters/dummy.png",
		"hp": 5000.0,
		"speed": 0.0,
		"attack": {"kind": "none", "damage": 0.0, "range": 0.0, "reload": 1.0, "cooldown": 1.0},
		"special": {"kind": "none", "cooldown": 1.0},
		"ult": {"kind": "none", "charge": 1.0},
		"text": {"attack": "", "special": "", "ult": ""},
		"bars": {"hp": 1.0, "speed": 0.0, "range": 0.0},
	},
}


static func get_def(id: String) -> Dictionary:
	return DEFS[id]


## Reichweite des Basisangriffs in Pixeln (für Bots und Auto-Aim).
static func attack_range_px(id: String) -> float:
	var atk: Dictionary = DEFS[id]["attack"]
	return float(atk["range"]) * TILE
