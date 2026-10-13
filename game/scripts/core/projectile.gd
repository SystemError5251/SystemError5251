class_name Projectile
extends RefCounted
## Einfaches Projektil (z. B. FIREWALLs Schrotkugeln). Wird vom Match simuliert.

var owner_f: Fighter
var team := 0
var pos := Vector2.ZERO
var dir := Vector2.RIGHT
var speed := 400.0
var max_dist := 100.0
var travelled := 0.0
var damage := 0.0
var radius := 4.0
var alive := true
