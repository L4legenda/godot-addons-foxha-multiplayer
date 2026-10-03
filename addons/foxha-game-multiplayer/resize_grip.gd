extends Control
## Visible bottom-right resize affordance, independent of font glyphs.

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func _draw() -> void:
	var color := Color("#ff7b2c") if get_rect().has_point(get_parent().get_local_mouse_position()) else Color("#90949e")
	for length in [4, 9, 14]:
		draw_line(size - Vector2(length + 2, 2), size - Vector2(2, length + 2), color, 1.5, true)
