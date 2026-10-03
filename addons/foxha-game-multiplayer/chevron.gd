class_name Chevron
extends Button
## Стрелка «вниз» у игрока в списке: по нажатию открывается выпадающий список действий.
## Рисуется линиями, чтобы не зависеть от глифов шрифта.

var opened := false:
	set(value):
		opened = value
		queue_redraw()

@export var color: Color = Color(1, 1, 1, 0.85):
	set(value):
		color = value
		queue_redraw()

@export var thickness: float = 2.0:
	set(value):
		thickness = value
		queue_redraw()


func _init() -> void:
	theme_type_variation = &"QuietButton"
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _draw() -> void:
	var center := size * 0.5
	var direction := -1.0 if opened else 1.0
	var points := PackedVector2Array([
		center + Vector2(-4, -2 * direction),
		center + Vector2(0, 2 * direction),
		center + Vector2(4, -2 * direction),
	])
	draw_polyline(points, Color("#ff7b2c") if opened or is_hovered() else color, thickness, true)
