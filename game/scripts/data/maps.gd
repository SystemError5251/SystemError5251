class_name MapDefs
extends RefCounted
## Arena-Definitionen als Text. Es wird nur die obere Hälfte beschrieben;
## die untere Hälfte entsteht durch Punktspiegelung. So sind alle Arenen fair.
##
## Legende:  #  Wand (Server-Rack)      B  zerstörbarer Datenblock
##           ~  Rauschen-Feld           .  Boden
##           a  Spawn Team Blau         b  Spawn Team Orange (entsteht durch Spiegelung)
##           P  Power-up-Punkt          D  Trainings-Dummy

const MAPS := {
	"serverraum": {
		"name": "Serverraum",
		"top": [
			"##############################",
			"#~~~.......B.......~~~.......#",
			"#~~~..##...B....P..~~~..##...#",
			"#.....##..........BB....##...#",
			"#..............##............#",
			"#..BB....~~~...##....###.....#",
			"#a.##....~~~.........#.......#",
			"#.a......~~~.........#...B...#",
			"#.a..........B.............~~#",
		],
	},
	"papierkorb": {
		"name": "Papierkorb",
		"top": [
			"##################",
			"#~~.....B......~~#",
			"#~~..##....B.....#",
			"#.....BB...P.....#",
			"#..a.......####..#",
			"#.....B..........#",
		],
	},
	"labor": {
		"name": "Testlabor",
		"top": [
			"##################",
			"#~~.....B......~~#",
			"#~~..##....B..D..#",
			"#.....BB...P.....#",
			"#..a.......####..#",
			"#.....B.....D....#",
		],
	},
}

const SWAP := {"a": "b", "b": "a"}


## Erzeugt alle Zeilen der Arena (obere Hälfte + punktgespiegelte untere Hälfte).
static func build_rows(map_id: String) -> PackedStringArray:
	var def: Dictionary = MAPS[map_id]
	var top: Array = def["top"]
	var rows := PackedStringArray()
	for r in top:
		rows.append(String(r))
	for i in range(top.size() - 1, -1, -1):
		var src: String = top[i]
		var mirrored := ""
		for x in range(src.length() - 1, -1, -1):
			var ch := src[x]
			if ch == "D":
				ch = "."
			mirrored += String(SWAP.get(ch, ch))
		rows.append(mirrored)
	return rows
