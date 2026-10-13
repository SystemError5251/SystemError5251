class_name Pickup
extends RefCounted
## Power-up in der Arena: Backup (Heilung), Cache (Tempo), Overflow (Schaden).

enum Kind { BACKUP, CACHE, OVERFLOW }

const NAMES := ["BACKUP", "CACHE", "OVERFLOW"]
const COLORS := [Color("2fbf6a"), Color("27e1ff"), Color("ff4d4d")]

var kind := Kind.BACKUP
var pos := Vector2.ZERO
var spot := 0
var t := 0.0
