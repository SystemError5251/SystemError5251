class_name UiKit
extends RefCounted
## Gemeinsame UI-Bausteine im Pixel-/Neon-Stil.

const BG := Color("0b0f1a")
const PANEL := Color("141b2d")
const PANEL_LIGHT := Color("1d2742")
const CYAN := Color("27e1ff")
const MAGENTA := Color("ff3df2")
const YELLOW := Color("ffe14d")
const TEXT := Color("e6ebff")
const MUTED := Color("8a93b8")
const BLUE := Color("2d8cff")
const ORANGE := Color("ff8a1f")


static func style(bg: Color, border: Color, border_w := 1, margin := 6.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.anti_aliasing = false
	sb.set_content_margin_all(margin)
	return sb


static func make_theme(font: Font) -> Theme:
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 8
	t.set_stylebox("normal", "Button", style(PANEL, Color(CYAN, 0.55)))
	t.set_stylebox("hover", "Button", style(PANEL_LIGHT, CYAN))
	t.set_stylebox("pressed", "Button", style(Color("0d3a4a"), CYAN, 2))
	t.set_stylebox("disabled", "Button", style(Color("10141f"), Color("2a3048")))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", CYAN)
	t.set_color("font_disabled_color", "Button", Color("4a5272"))
	t.set_font_size("font_size", "Button", 16)
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.75))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_stylebox("panel", "PanelContainer", style(Color(PANEL, 0.92), Color(CYAN, 0.35)))
	t.set_stylebox("panel", "Panel", style(Color(PANEL, 0.92), Color(CYAN, 0.35)))
	# CheckButton im selben Stil
	t.set_stylebox("normal", "CheckButton", style(PANEL, Color(CYAN, 0.35)))
	t.set_stylebox("hover", "CheckButton", style(PANEL_LIGHT, CYAN))
	t.set_stylebox("pressed", "CheckButton", style(PANEL_LIGHT, CYAN))
	t.set_stylebox("hover_pressed", "CheckButton", style(PANEL_LIGHT, CYAN))
	t.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())
	t.set_font_size("font_size", "CheckButton", 8)
	return t


static func button(text: String, min_size := Vector2(200, 28), primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	if primary:
		b.add_theme_stylebox_override("normal", style(Color("1a2f4a"), YELLOW, 2))
		b.add_theme_stylebox_override("hover", style(Color("244063"), YELLOW, 2))
		b.add_theme_stylebox_override("pressed", style(Color("3a3410"), YELLOW, 2))
		b.add_theme_color_override("font_color", YELLOW)
		b.add_theme_color_override("font_hover_color", Color("fff2a8"))
	return b


static func label(text: String, size := 8, color := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l


## Zeichnet Text mit RGB-Versatz (Glitch-Look).
static func draw_glitch_text(ci: CanvasItem, font: Font, center: Vector2, text: String, size: int,
		col: Color, alpha := 1.0) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := (center - Vector2(w * 0.5, -size * 0.35)).round()
	var o := maxf(1.0, size / 16.0)
	ci.draw_string(font, p + Vector2(o, o), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.7 * alpha))
	ci.draw_string(font, p + Vector2(-o, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(CYAN, 0.8 * alpha))
	ci.draw_string(font, p + Vector2(o, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(MAGENTA, 0.8 * alpha))
	ci.draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(col, alpha))


static func format_time(t: float) -> String:
	var s := maxi(0, ceili(t))
	return "%d:%02d" % [s / 60, s % 60]
