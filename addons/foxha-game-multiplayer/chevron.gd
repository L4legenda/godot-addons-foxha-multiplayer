class_name Chevron
extends Button
## Стрелка «вниз» у игрока в списке: по нажатию открывается выпадающий список действий.
## Рисуется линиями, чтобы не зависеть от глифов шрифта. При открытии меню
## окно списка разворачивает стрелку вверх (rotation = PI).

@export var color: Color = Color(1, 1, 1, 0.85):
	set(value):
		color = value
		queue_redraw()

@export var thickness: float = 2.0:
	set(value):
		thickness = value
		queue_redraw()


func _init() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _draw() -> void:
	var points := PackedVector2Array([
		Vector2(size.x * 0.18, size.y * 0.34),
		Vector2(size.x * 0.50, size.y * 0.66),
		Vector2(size.x * 0.82, size.y * 0.34),
	])
	draw_polyline(points, color, thickness, true)
