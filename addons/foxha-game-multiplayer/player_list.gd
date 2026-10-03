extends CanvasLayer
## Окно списка игроков (часть аддона Foxha Game Multiplayer).
## Открывается/закрывается по Shift+Tab, экран затемняется за 0.3 с,
## окно можно перетаскивать мышью. У каждого игрока справа стрелка
## с выпадающим списком: «Пригласить», «Присоединиться».
##
## Наполняется через set_me()/set_friends()/set_other() — по умолчанию
## показываются заглушки MOCK_*, чтобы окно было видно сразу.

## Запрос действия из выпадающего списка: action — "invite" или "join".
signal action_requested(player: Dictionary, action: String)

const ANIM_TIME := 0.3          ## длительность анимации появления/скрытия, сек
const DIM_ALPHA := 0.65         ## насколько сильно затемняется экран
const PANEL_START_SCALE := 0.94 ## с какого масштаба «выезжает» окно
const ARROW_TURN_TIME := 0.15   ## разворот стрелки при открытии списка, сек
const MENU_WIDTH := 172.0       ## ширина выпадающего списка, px

const ACTION_INVITE := 0
const ACTION_JOIN := 1

const ChevronScript := preload("chevron.gd")

## Ставить игру на паузу, пока окно открыто.
@export var pause_game := true
## Освобождать курсор, пока окно открыто (возвращается при закрытии).
@export var release_mouse := true
## Горячая клавиша окна.
@export var toggle_with_shift_tab := true

# --- заглушки данных: переопределяются через set_me()/set_friends()/set_other() ---
const MOCK_ME := {
	"nickname": "Nickname",
	"avatar_color": Color(0.29, 0.62, 0.96),
}

const MOCK_FRIENDS: Array[Dictionary] = [
	{"nickname": "Nickname", "avatar_color": Color(0.91, 0.44, 0.38)},
	{"nickname": "Nickname", "avatar_color": Color(0.45, 0.78, 0.45)},
	{"nickname": "Nickname", "avatar_color": Color(0.95, 0.72, 0.29)},
]

const MOCK_OTHER: Array[Dictionary] = [
	{"nickname": "Nickname", "avatar_color": Color(0.62, 0.53, 0.9)},
	{"nickname": "Nickname", "avatar_color": Color(0.35, 0.72, 0.78)},
	{"nickname": "Nickname", "avatar_color": Color(0.85, 0.5, 0.75)},
	{"nickname": "Nickname", "avatar_color": Color(0.66, 0.66, 0.7)},
]

@onready var dimmer: ColorRect = $Dimmer
@onready var panel: PanelContainer = $Panel
@onready var me_avatar: ColorRect = $Panel/Margin/Content/Header/Avatar
@onready var me_nickname: Label = $Panel/Margin/Content/Header/Nickname
@onready var friends_list: VBoxContainer = $Panel/Margin/Content/FriendsList
@onready var other_list: VBoxContainer = $Panel/Margin/Content/OtherList

var is_open := false

var _menu: PanelContainer
var _menu_owner: Dictionary = {}
var _active_arrow: Button
var _tween: Tween
var _dragging := false
var _drag_offset := Vector2.ZERO
var _placed := false
var _mouse_mode_before := Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	# Работаем и на паузе: пока окно открыто, игра стоит.
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	dimmer.modulate.a = 0.0
	panel.modulate.a = 0.0
	_build_menu()
	set_me(MOCK_ME)
	set_friends(MOCK_FRIENDS)
	set_other(MOCK_OTHER)


# --- данные -------------------------------------------------------------------

func set_me(player: Dictionary) -> void:
	me_avatar.color = player.get("avatar_color", Color(0.5, 0.5, 0.5))
	me_nickname.text = player.get("nickname", "")


func set_friends(players: Array) -> void:
	_fill_list(friends_list, players)


func set_other(players: Array) -> void:
	_fill_list(other_list, players)


func _fill_list(container: VBoxContainer, players: Array) -> void:
	for child in container.get_children():
		child.queue_free()
		container.remove_child(child)
	for player in players:
		container.add_child(_make_row(player))


func _make_row(player: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var avatar := ColorRect.new()
	avatar.custom_minimum_size = Vector2(28, 28)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	avatar.color = player.get("avatar_color", Color(0.5, 0.5, 0.5))
	row.add_child(avatar)

	var nickname := Label.new()
	nickname.text = player.get("nickname", "")
	nickname.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nickname.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(nickname)

	var arrow: Button = ChevronScript.new()
	arrow.custom_minimum_size = Vector2(26, 26)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arrow.tooltip_text = "Пригласить / Присоединиться"
	arrow.pressed.connect(_open_actions.bind(player, arrow))
	row.add_child(arrow)

	return row


# --- выпадающий список действий -----------------------------------------------

func _build_menu() -> void:
	var menu_style := StyleBoxFlat.new()
	menu_style.bg_color = Color(0.09, 0.1, 0.12, 0.98)
	menu_style.set_border_width_all(1)
	menu_style.border_color = Color(1, 1, 1, 0.25)
	menu_style.set_corner_radius_all(6)
	menu_style.shadow_color = Color(0, 0, 0, 0.45)
	menu_style.shadow_size = 8
	menu_style.set_content_margin_all(4)

	_menu = PanelContainer.new()
	_menu.name = "ActionsMenu"
	_menu.visible = false
	_menu.add_theme_stylebox_override("panel", menu_style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_menu.add_child(box)
	_add_menu_item(box, "Пригласить", ACTION_INVITE)
	_add_menu_item(box, "Присоединиться", ACTION_JOIN)

	add_child(_menu)


func _add_menu_item(box: VBoxContainer, title: String, id: int) -> void:
	var item := Button.new()
	item.text = title
	item.alignment = HORIZONTAL_ALIGNMENT_LEFT
	item.focus_mode = Control.FOCUS_NONE
	item.custom_minimum_size = Vector2(MENU_WIDTH, 30)
	item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	item.add_theme_stylebox_override("normal", _menu_item_style(Color(0, 0, 0, 0)))
	item.add_theme_stylebox_override("hover", _menu_item_style(Color(1, 1, 1, 0.12)))
	item.add_theme_stylebox_override("pressed", _menu_item_style(Color(1, 1, 1, 0.2)))
	item.add_theme_color_override("font_color", Color(0.9, 0.92, 0.96))
	item.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	item.add_theme_font_size_override("font_size", 15)
	item.pressed.connect(_on_action_selected.bind(id))
	box.add_child(item)


func _menu_item_style(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


func _open_actions(player: Dictionary, arrow: Button) -> void:
	if _menu.visible and _active_arrow == arrow:
		_close_menu()
		return
	_menu_owner = player
	_set_arrow_open(_active_arrow, false)
	_active_arrow = arrow
	_set_arrow_open(arrow, true)
	_place_menu(arrow)
	_menu.visible = true

	# После первого показа размеры посчитаны окончательно — уточняем позицию.
	await get_tree().process_frame
	if _menu.visible and _active_arrow == arrow:
		_place_menu(arrow)


func _place_menu(arrow: Button) -> void:
	var arrow_rect := arrow.get_global_rect()
	var menu_size := _menu.get_combined_minimum_size()
	var view_size := get_viewport().get_visible_rect().size

	# По умолчанию — под стрелкой, выровнено по её правому краю.
	var pos := Vector2(arrow_rect.end.x - menu_size.x, arrow_rect.end.y + 2.0)
	if pos.y + menu_size.y > view_size.y:
		pos.y = arrow_rect.position.y - menu_size.y - 2.0
	pos.x = clampf(pos.x, 4.0, maxf(4.0, view_size.x - menu_size.x - 4.0))
	_menu.position = pos.round()


func _close_menu() -> void:
	if not _menu.visible and _active_arrow == null:
		return
	_menu.visible = false
	_set_arrow_open(_active_arrow, false)
	_active_arrow = null


func _set_arrow_open(arrow: Button, open: bool) -> void:
	if arrow == null:
		return
	arrow.pivot_offset = arrow.size * 0.5
	var turn := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	turn.tween_property(arrow, "rotation", PI if open else 0.0, ARROW_TURN_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_action_selected(id: int) -> void:
	var player := _menu_owner
	_close_menu()
	if player.is_empty():
		return
	# TODO: заглушка — здесь будет приглашение/подключение к игроку.
	var action := "invite" if id == ACTION_INVITE else "join"
	print("[foxha-game-multiplayer] действие '%s' для '%s'" % [action, player.get("nickname", "?")])
	action_requested.emit(player, action)


# --- открытие / закрытие ------------------------------------------------------

func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open() -> void:
	if is_open:
		return
	is_open = true
	visible = true

	if pause_game:
		get_tree().paused = true
	if release_mouse:
		_mouse_mode_before = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Даём контейнерам посчитать размер окна, затем центрируем его.
	await get_tree().process_frame
	if not _placed:
		var viewport_size := get_viewport().get_visible_rect().size
		panel.position = ((viewport_size - panel.size) * 0.5).round()
		_placed = true
	panel.pivot_offset = panel.size * 0.5

	_animate(1.0)


func close() -> void:
	if not is_open:
		return
	is_open = false
	_dragging = false
	_close_menu()
	_animate(0.0)


func _animate(target: float) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()

	_tween = create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(dimmer, "modulate:a", DIM_ALPHA * target, ANIM_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(panel, "modulate:a", target, ANIM_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(panel, "scale", Vector2.ONE * lerpf(PANEL_START_SCALE, 1.0, target), ANIM_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	if target <= 0.0:
		_tween.finished.connect(_on_hidden)


func _on_hidden() -> void:
	visible = false
	if not is_open:
		if pause_game:
			get_tree().paused = false
		if release_mouse:
			Input.mouse_mode = _mouse_mode_before


# --- ввод: Shift+Tab, Esc, перетаскивание -------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if toggle_with_shift_tab and _is_shift_tab(event):
			toggle()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and is_open:
			# Esc сначала закрывает выпадающий список, потом уже окно.
			if _menu.visible:
				_close_menu()
			else:
				close()
			get_viewport().set_input_as_handled()
		return

	if not is_open:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _menu.visible:
				# Клик мимо списка закрывает его и не идёт дальше (не тянет окно).
				if not _menu.get_global_rect().has_point(event.position):
					_close_menu()
					get_viewport().set_input_as_handled()
			elif panel.get_global_rect().has_point(event.position):
				_dragging = true
				_drag_offset = panel.global_position - event.position
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		panel.global_position = event.position + _drag_offset


func _is_shift_tab(event: InputEventKey) -> bool:
	# Разные платформы присылают Shift+Tab либо как TAB+shift, либо как BACKTAB.
	var code := event.keycode
	var physical := event.physical_keycode
	if code == KEY_BACKTAB or physical == KEY_BACKTAB:
		return true
	return event.shift_pressed and (code == KEY_TAB or physical == KEY_TAB)
