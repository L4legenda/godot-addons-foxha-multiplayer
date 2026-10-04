@tool
extends Label
## Draw the presence indicator instead of relying on a font glyph.

func _ready() -> void:
	var inset := StyleBoxEmpty.new()
	inset.content_margin_left = 12
	add_theme_stylebox_override("normal", inset)

func _draw() -> void:
	draw_circle(Vector2(3, size.y * 0.5), 2.5, get_theme_color("font_color"), true, -1.0, true)
