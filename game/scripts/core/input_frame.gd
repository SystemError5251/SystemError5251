class_name InputFrame
extends RefCounted
## Eingaben eines Kämpfers für einen Simulations-Tick.
## Spieler (Touch), Bots und später das Netzwerk liefern alle dieses Format.
## Ein Ziel-Vektor von (0, 0) bedeutet „Auto-Aim“ (Antippen statt Ziehen).

var move := Vector2.ZERO
var attack := false
var attack_aim := Vector2.ZERO
var special := false
var special_aim := Vector2.ZERO
var ult := false
var ult_aim := Vector2.ZERO
