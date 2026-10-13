class_name Arena
extends Node2D
## Kachel-Arena: Kollision, Sichtlinien, zerstörbare Blöcke, temporäre Wände,
## Rauschen-Felder und Wegfindung für Bots.

signal block_destroyed(cell: Vector2i)

const TILE := 32
const BLOCK_HP := 2400.0

enum Cell { FLOOR, WALL, BLOCK, TEMP }

var width := 0
var height := 0
var cells := PackedByteArray()
var noise := PackedByteArray()
var block_hp := {}            # Vector2i -> float
var temp_walls := {}          # Vector2i -> float (Restzeit)
var spawns: Array = [[], []]  # Team -> Array[Vector2]
var spawn_cells: Array = []   # [Vector2i, Team]
var pickup_spots: Array[Vector2] = []
var dummy_spots: Array[Vector2] = []
var astar := AStarGrid2D.new()

var _world: Node2D
var _sprites := {}            # Vector2i -> Sprite2D
var _floor_variant := PackedByteArray()
var _noise_layer: Node2D

var _floor_tex: Texture2D = preload("res://assets/tiles/floor.png")
var _wall_tex: Texture2D = preload("res://assets/tiles/wall.png")
var _block_tex: Texture2D = preload("res://assets/tiles/block.png")
var _temp_tex: Texture2D = preload("res://assets/tiles/temp_wall.png")
var _spawn_tex: Texture2D = preload("res://assets/tiles/spawn.png")
var _noise_tex: Texture2D = preload("res://assets/tiles/noise.png")


func setup(map_id: String, world: Node2D) -> void:
	_world = world
	var rows := MapDefs.build_rows(map_id)
	height = rows.size()
	width = rows[0].length()
	cells.resize(width * height)
	noise.resize(width * height)
	_floor_variant.resize(width * height)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in height:
		var row: String = rows[y]
		assert(row.length() == width, "Arena-Zeile %d hat falsche Länge" % y)
		for x in width:
			var c := Vector2i(x, y)
			var i := y * width + x
			cells[i] = Cell.FLOOR
			noise[i] = 0
			_floor_variant[i] = 0 if rng.randf() < 0.55 else rng.randi_range(1, 3)
			match row[x]:
				"#":
					cells[i] = Cell.WALL
				"B":
					cells[i] = Cell.BLOCK
					block_hp[c] = BLOCK_HP
				"~":
					noise[i] = 1
				"a":
					spawns[0].append(cell_center(c))
					spawn_cells.append([c, 0])
				"b":
					spawns[1].append(cell_center(c))
					spawn_cells.append([c, 1])
				"P":
					pickup_spots.append(cell_center(c))
				"D":
					dummy_spots.append(cell_center(c))
	_setup_astar()
	_create_sprites()
	_noise_layer = Node2D.new()
	_noise_layer.name = "Noise"
	_noise_layer.draw.connect(_draw_noise)
	add_child(_noise_layer)
	queue_redraw()


func size_px() -> Vector2:
	return Vector2(width * TILE, height * TILE)


func to_cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.y / TILE))


func cell_center(c: Vector2i) -> Vector2:
	return Vector2(c.x * TILE + TILE * 0.5, c.y * TILE + TILE * 0.5)


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


func cell_type(c: Vector2i) -> int:
	if not in_bounds(c):
		return Cell.WALL
	return cells[c.y * width + c.x]


func is_solid(c: Vector2i) -> bool:
	return cell_type(c) != Cell.FLOOR


func is_noise_at(p: Vector2) -> bool:
	var c := to_cell(p)
	return in_bounds(c) and noise[c.y * width + c.x] == 1


# ---------------------------------------------------------------------------
# Kollision
# ---------------------------------------------------------------------------

## Bewegt einen Kreis um `motion` und schiebt ihn aus festen Kacheln heraus.
func move_circle(pos: Vector2, motion: Vector2, r: float) -> Vector2:
	var steps := maxi(1, ceili(motion.length() / 6.0))
	var step := motion / steps
	var p := pos
	for i in steps:
		p += step
		p = _resolve(p, r)
	return p


func _resolve(pos: Vector2, r: float) -> Vector2:
	var p := pos
	for _iter in 2:
		var cx0 := floori((p.x - r) / TILE)
		var cx1 := floori((p.x + r) / TILE)
		var cy0 := floori((p.y - r) / TILE)
		var cy1 := floori((p.y + r) / TILE)
		for cy in range(cy0, cy1 + 1):
			for cx in range(cx0, cx1 + 1):
				if not is_solid(Vector2i(cx, cy)):
					continue
				var rmin := Vector2(cx * TILE, cy * TILE)
				var rmax := rmin + Vector2(TILE, TILE)
				var closest := p.clamp(rmin, rmax)
				var d := p - closest
				var dist := d.length()
				if dist >= r:
					continue
				if dist > 0.0001:
					p += d / dist * (r - dist)
				else:
					# Mittelpunkt liegt in der Kachel: entlang der kürzesten Achse hinaus.
					var pen := [p.x - rmin.x, rmax.x - p.x, p.y - rmin.y, rmax.y - p.y]
					var best := 0
					for k in range(1, 4):
						if float(pen[k]) < float(pen[best]):
							best = k
					match best:
						0: p.x = rmin.x - r
						1: p.x = rmax.x + r
						2: p.y = rmin.y - r
						3: p.y = rmax.y + r
	return p


## Prüft einen Kreis gegen feste Kacheln (z. B. ob eine Wand gesetzt werden darf).
func circle_hits_solid(p: Vector2, r: float) -> bool:
	return _resolve(p, r) != p


## Verfolgt eine Strecke bis zur ersten festen Kachel.
## Ergebnis: {hit: bool, pos: Vector2 (letzter freier Punkt), cell: Vector2i}
func cast_segment(a: Vector2, b: Vector2) -> Dictionary:
	var dist := a.distance_to(b)
	var steps := maxi(1, ceili(dist / 4.0))
	var prev := a
	for i in range(1, steps + 1):
		var p := a.lerp(b, float(i) / steps)
		var c := to_cell(p)
		if is_solid(c):
			return {"hit": true, "pos": prev, "cell": c}
		prev = p
	return {"hit": false, "pos": b, "cell": Vector2i(-1, -1)}


func has_los(a: Vector2, b: Vector2) -> bool:
	return not bool(cast_segment(a, b)["hit"])


# ---------------------------------------------------------------------------
# Zerstörbare Blöcke & temporäre Wände
# ---------------------------------------------------------------------------

## Gibt true zurück, wenn der Block dabei zerstört wurde.
func damage_block(c: Vector2i, amount: float) -> bool:
	if cell_type(c) != Cell.BLOCK:
		return false
	var hp: float = block_hp.get(c, BLOCK_HP)
	hp -= amount
	block_hp[c] = hp
	var spr: Sprite2D = _sprites.get(c)
	if hp <= 0.0:
		cells[c.y * width + c.x] = Cell.FLOOR
		block_hp.erase(c)
		astar.set_point_solid(c, false)
		if spr:
			spr.queue_free()
			_sprites.erase(c)
		block_destroyed.emit(c)
		return true
	if spr and hp < BLOCK_HP * 0.5:
		spr.frame = 1
	return false


func add_temp_wall(c: Vector2i, duration: float) -> bool:
	if cell_type(c) != Cell.FLOOR:
		return false
	cells[c.y * width + c.x] = Cell.TEMP
	temp_walls[c] = duration
	astar.set_point_solid(c, true)
	var spr := _make_sprite(c, _temp_tex, 1, 0)
	spr.modulate = Color(1, 1, 1, 0)
	spr.create_tween().tween_property(spr, "modulate:a", 1.0, 0.15)
	return true


func tick(delta: float) -> void:
	for c in temp_walls.keys():
		var t: float = temp_walls[c] - delta
		if t <= 0.0:
			temp_walls.erase(c)
			cells[c.y * width + c.x] = Cell.FLOOR
			astar.set_point_solid(c, false)
			var spr: Sprite2D = _sprites.get(c)
			if spr:
				spr.queue_free()
				_sprites.erase(c)
		else:
			temp_walls[c] = t
			var spr2: Sprite2D = _sprites.get(c)
			if spr2 and t < 1.0:
				spr2.visible = int(t * 10.0) % 2 == 0


# ---------------------------------------------------------------------------
# Wegfindung
# ---------------------------------------------------------------------------

func _setup_astar() -> void:
	astar.region = Rect2i(0, 0, width, height)
	astar.cell_size = Vector2(TILE, TILE)
	astar.offset = Vector2(TILE * 0.5, TILE * 0.5)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for y in height:
		for x in width:
			if is_solid(Vector2i(x, y)):
				astar.set_point_solid(Vector2i(x, y), true)


func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var a := to_cell(from)
	var b := to_cell(to)
	if not in_bounds(a) or not in_bounds(b) or astar.is_point_solid(a):
		return PackedVector2Array()
	return astar.get_point_path(a, b, true)


# ---------------------------------------------------------------------------
# Darstellung
# ---------------------------------------------------------------------------

func _create_sprites() -> void:
	for y in height:
		for x in width:
			var c := Vector2i(x, y)
			match cell_type(c):
				Cell.WALL:
					_make_sprite(c, _wall_tex, 3, (x * 7 + y * 3) % 3)
				Cell.BLOCK:
					_make_sprite(c, _block_tex, 2, 0)


func _make_sprite(c: Vector2i, tex: Texture2D, frames: int, frame: int) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.hframes = frames
	spr.frame = frame
	spr.centered = false
	spr.offset = Vector2(0, -40)
	# Position = Unterkante der Kachel, damit die Y-Sortierung mit den Kämpfern passt.
	spr.position = Vector2(c.x * TILE, c.y * TILE + TILE)
	_world.add_child(spr)
	_sprites[c] = spr
	return spr


func _draw() -> void:
	# Hintergrund außerhalb der Arena
	var pad := 400.0
	draw_rect(Rect2(-pad, -pad, width * TILE + pad * 2, height * TILE + pad * 2), Color("080b14"))
	for y in height:
		for x in width:
			var v := _floor_variant[y * width + x]
			draw_texture_rect_region(_floor_tex, Rect2(x * TILE, y * TILE, TILE, TILE),
				Rect2(v * TILE, 0, TILE, TILE))
	for sc in spawn_cells:
		var c: Vector2i = sc[0]
		var team: int = sc[1]
		draw_texture_rect_region(_spawn_tex, Rect2(c.x * TILE, c.y * TILE, TILE, TILE),
			Rect2(team * TILE, 0, TILE, TILE), Color(1, 1, 1, 0.8))


var _noise_frame := 0
var _noise_t := 0.0


func _process(delta: float) -> void:
	_noise_t += delta
	if _noise_t > 0.12:
		_noise_t = 0.0
		_noise_frame = (_noise_frame + 1) % 4
		_noise_layer.queue_redraw()


func _draw_noise() -> void:
	for y in height:
		for x in width:
			if noise[y * width + x] == 1:
				var f := (_noise_frame + x + y * 3) % 4
				_noise_layer.draw_texture_rect_region(_noise_tex, Rect2(x * TILE, y * TILE, TILE, TILE),
					Rect2(f * TILE, 0, TILE, TILE))
