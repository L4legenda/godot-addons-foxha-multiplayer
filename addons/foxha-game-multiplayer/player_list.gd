extends CanvasLayer
## Оверлей друзей Foxha: Shift+Tab, поиск, фильтры и действия игроков.
signal action_requested(player: Dictionary, action: String)

const ANIM_TIME := 0.22
const DIM_ALPHA := 0.72
const PANEL_START_SCALE := 0.97
const MENU_WIDTH := 220.0
const MIN_WINDOW_SIZE := Vector2(260, 480)
const ACTION_INVITE := 0
const ACTION_JOIN := 1
const ACCENT := Color("#ff7b2c")
const MUTED := Color("#90949e")
const ChevronScript := preload("res://addons/foxha-game-multiplayer/chevron.gd")

@export var pause_game := true
@export var release_mouse := true
@export var toggle_with_shift_tab := true

const MOCK_ME := {"nickname": "Foxha", "avatar_color": Color("#df6427"), "status": "online"}
const MOCK_FRIENDS: Array[Dictionary] = [
	{"nickname": "L4legenda", "avatar_color": Color("#ba6039"), "status": "in_game", "game": "Foxha Multiplayer"},
	{"nickname": "OrangeFox", "avatar_color": Color("#936345"), "status": "online"},
	{"nickname": "Север", "avatar_color": Color("#596676"), "status": "offline"},
]
const MOCK_OTHER: Array[Dictionary] = [
	{"nickname": "NightRunner", "avatar_color": Color("#776498"), "status": "in_game", "game": "Foxha Multiplayer"},
	{"nickname": "Pixel", "avatar_color": Color("#3d7877"), "status": "online"},
	{"nickname": "Механик", "avatar_color": Color("#926a35"), "status": "online"},
	{"nickname": "Wanderer", "avatar_color": Color("#646770"), "status": "offline"},
]

@onready var dimmer: ColorRect = $Dimmer
@onready var panel: PanelContainer = $Panel
@onready var me_avatar: PanelContainer = %Avatar
@onready var me_nickname: Label = %Nickname
@onready var friends_list: VBoxContainer = %FriendsList
@onready var other_list: VBoxContainer = %OtherList
@onready var search: LineEdit = %Search
@onready var scroll: ScrollContainer = %Scroll
@onready var title_bar: HBoxContainer = %TitleBar
@onready var close_button: Button = %Close

var is_open := false
var _friends: Array = []
var _other: Array = []
var _filter := "all"
var _menu: PanelContainer
var _menu_title: Label
var _menu_owner: Dictionary = {}
var _active_arrow: Button
var _tween: Tween
var _dragging := false
var _drag_offset := Vector2.ZERO
var _resizing := false
var _resize_origin := Vector2.ZERO
var _resize_start_size := Vector2.ZERO
var _preferred_size := Vector2(520, 640)
var _size_initialized := false
var _placed := false
var _ui_scale := 1.0
var _session_active := false
var _paused_before := false
var _mouse_mode_before := Input.MOUSE_MODE_VISIBLE
var _focus_before: Control
var _demo_friends := true
var _demo_other := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	dimmer.modulate.a = 0.0
	panel.modulate.a = 0.0
	_build_menu()
	close_button.text = ""
	close_button.icon = preload("res://addons/foxha-game-multiplayer/icons/close.svg")
	close_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_button.custom_minimum_size = Vector2(36, 36)
	close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_button.pressed.connect(close)
	search.text_changed.connect(_on_search_changed)
	scroll.get_v_scroll_bar().value_changed.connect(func(_value: float): _close_menu(false))
	var filters := ButtonGroup.new()
	for button: Button in [%All, %InGame, %Online]:
		button.button_group = filters
	%All.pressed.connect(_set_filter.bind("all"))
	%InGame.pressed.connect(_set_filter.bind("in_game"))
	%Online.pressed.connect(_set_filter.bind("online"))
	get_viewport().size_changed.connect(_on_viewport_resized)
	set_me(MOCK_ME)
	_friends = MOCK_FRIENDS.duplicate(true)
	_other = MOCK_OTHER.duplicate(true)
	_refresh_lists()


# Existing public API; status and game are optional.
func set_me(player: Dictionary) -> void:
	var color: Color = player.get("avatar_color", ACCENT)
	var style := _surface(color.darkened(0.3), 4, 0)
	me_avatar.add_theme_stylebox_override("panel", style)
	me_nickname.text = str(player.get("nickname", "Игрок")).strip_edges()
	me_nickname.tooltip_text = me_nickname.text
	%Initial.text = me_nickname.text.left(1).to_upper()
	%MyStatus.text = _status_text(player)
	%MyStatus.add_theme_color_override("font_color", _status_color(player))


func set_friends(players: Array) -> void:
	_friends = players.duplicate(true)
	_demo_friends = false
	_refresh_lists()


func set_other(players: Array) -> void:
	_other = players.duplicate(true)
	_demo_other = false
	_refresh_lists()


func _status(player: Dictionary) -> String:
	return str(player.get("status", "online"))


func _status_text(player: Dictionary) -> String:
	match _status(player):
		"in_game":
			var game := str(player.get("game", "")).strip_edges()
			return "В игре" + (" · " + game if not game.is_empty() else "")
		"offline":
			return "Не в сети"
		_:
			return "В сети"


func _status_color(player: Dictionary) -> Color:
	match _status(player):
		"in_game": return ACCENT
		"offline": return Color("#727782")
		_: return Color("#c1c7ce")


func _rank(player: Dictionary) -> int:
	match _status(player):
		"in_game": return 0
		"offline": return 2
		_: return 1


func _matching(players: Array) -> Array:
	var result: Array = []
	var query := search.text.strip_edges().to_lower()
	for player: Dictionary in players:
		if not query.is_empty() and not str(player.get("nickname", "")).to_lower().contains(query):
			continue
		if _filter == "in_game" and _status(player) != "in_game":
			continue
		if _filter == "online" and _status(player) == "offline":
			continue
		result.append(player)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if _rank(a) != _rank(b):
			return _rank(a) < _rank(b)
		return str(a.get("nickname", "")).naturalnocasecmp_to(str(b.get("nickname", ""))) < 0
	)
	return result


func _refresh_lists() -> void:
	_close_menu(false)
	var friends := _matching(_friends)
	var others := _matching(_other)
	_fill_list(friends_list, friends)
	_fill_list(other_list, others)
	%FriendsTitle.text = "ДРУЗЬЯ  /  %d" % friends.size()
	%OtherTitle.text = "ДРУГИЕ ИГРОКИ  /  %d" % others.size()
	%FriendsTitle.visible = not friends.is_empty()
	%OtherTitle.visible = not others.is_empty()
	friends_list.visible = not friends.is_empty()
	other_list.visible = not others.is_empty()
	%Empty.visible = friends.is_empty() and others.is_empty()
	%Empty/Title.text = "Игроки не найдены" if not search.text.is_empty() or _filter != "all" else "Здесь появятся игроки"
	%Empty/Hint.text = "Измените запрос или выберите другой фильтр." if not search.text.is_empty() or _filter != "all" else "Список обновится, когда появятся друзья и другие игроки."
	var online := 0
	for player: Dictionary in _friends + _other:
		if _status(player) != "offline":
			online += 1
	%OnlineCount.text = "%d в сети" % online
	%Demo.visible = _demo_friends or _demo_other


func _on_search_changed(_text: String) -> void:
	_refresh_lists()
	scroll.scroll_vertical = 0


func _set_filter(value: String) -> void:
	_filter = value
	_refresh_lists()
	scroll.scroll_vertical = 0


func _fill_list(container: VBoxContainer, players: Array) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
	for player: Dictionary in players:
		var row := _make_row(player)
		row.name = "Player%d" % container.get_child_count()
		container.add_child(row)


func _make_row(player: Dictionary) -> PanelContainer:
	var row := PanelContainer.new()
	row.custom_minimum_size.y = 64
	var normal := _surface(Color("#1a1c20"), 4, 10)
	var hover := _surface(Color("#27221f"), 4, 10)
	row.add_theme_stylebox_override("panel", normal)
	row.mouse_entered.connect(func(): row.add_theme_stylebox_override("panel", hover))
	row.mouse_exited.connect(func(): row.add_theme_stylebox_override("panel", normal))
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_theme_constant_override("separation", 12)
	row.add_child(box)
	var avatar := PanelContainer.new()
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar.custom_minimum_size = Vector2(40, 40)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var color: Color = player.get("avatar_color", Color("#595d66"))
	var avatar_style := _surface(color.darkened(0.4), 3, 0)
	avatar_style.border_width_bottom = 2
	avatar_style.border_color = _status_color(player)
	avatar.add_theme_stylebox_override("panel", avatar_style)
	box.add_child(avatar)
	var initial := Label.new()
	initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	initial.text = str(player.get("nickname", "?")).strip_edges().left(1).to_upper()
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial.add_theme_font_size_override("font_size", 19)
	avatar.add_child(initial)
	var identity := VBoxContainer.new()
	identity.mouse_filter = Control.MOUSE_FILTER_PASS
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	identity.add_theme_constant_override("separation", 3)
	box.add_child(identity)
	var nickname := Label.new()
	nickname.name = "Nickname"
	nickname.text = str(player.get("nickname", "Игрок")).strip_edges()
	nickname.tooltip_text = nickname.text
	nickname.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nickname.add_theme_font_size_override("font_size", 15)
	if _status(player) == "offline":
		nickname.add_theme_color_override("font_color", MUTED)
	identity.add_child(nickname)
	var status_label := preload("status_label.gd").new()
	status_label.text = _status_text(player)
	status_label.tooltip_text = _status_text(player)
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", _status_color(player))
	identity.add_child(status_label)
	var arrow: Button = ChevronScript.new()
	arrow.name = "Actions"
	arrow.custom_minimum_size = Vector2(32, 32)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arrow.tooltip_text = "Действия · " + nickname.text
	arrow.pressed.connect(_open_actions.bind(player, arrow))
	box.add_child(arrow)
	return row


func _surface(bg: Color, radius: int, padding: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(padding)
	return style


func _build_menu() -> void:
	var style := _surface(Color("#17191d"), 5, 6)
	style.set_border_width_all(1)
	style.border_color = Color("#70401f")
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 12
	_menu = PanelContainer.new()
	_menu.name = "ActionsMenu"
	_menu.theme = panel.theme
	_menu.visible = false
	_menu.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_menu.add_child(box)
	_menu_title = Label.new()
	_menu_title.custom_minimum_size = Vector2(MENU_WIDTH, 26)
	_menu_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_menu_title.add_theme_color_override("font_color", MUTED)
	_menu_title.add_theme_font_size_override("font_size", 12)
	box.add_child(_menu_title)
	_add_menu_item(box, "Пригласить в игру", ACTION_INVITE)
	_add_menu_item(box, "Присоединиться", ACTION_JOIN)
	add_child(_menu)


func _add_menu_item(box: VBoxContainer, title: String, id: int) -> void:
	var item := Button.new()
	item.name = "Invite" if id == ACTION_INVITE else "Join"
	item.text = title
	item.alignment = HORIZONTAL_ALIGNMENT_LEFT
	item.custom_minimum_size = Vector2(MENU_WIDTH, 38)
	item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	item.theme_type_variation = &"QuietButton"
	item.pressed.connect(_on_action_selected.bind(id))
	box.add_child(item)


func _open_actions(player: Dictionary, arrow: Button) -> void:
	if _menu.visible and _active_arrow == arrow:
		_close_menu()
		return
	_menu_owner = player
	_set_arrow_open(_active_arrow, false)
	_active_arrow = arrow
	_set_arrow_open(arrow, true)
	_menu_title.text = "  " + str(player.get("nickname", "Игрок")).strip_edges()
	_menu.scale = Vector2.ONE * _ui_scale
	_place_menu(arrow)
	_menu.visible = true
	_menu.get_child(0).get_node("Invite").grab_focus()
	await get_tree().process_frame
	if _menu.visible and is_instance_valid(arrow) and _active_arrow == arrow:
		_place_menu(arrow)


func _place_menu(arrow: Button) -> void:
	var rect := arrow.get_global_rect()
	var menu_size := _menu.get_combined_minimum_size() * _ui_scale
	var view := get_viewport().get_visible_rect().size
	var pos := Vector2(rect.end.x - menu_size.x, rect.end.y + 5)
	if pos.y + menu_size.y > view.y - 8:
		pos.y = rect.position.y - menu_size.y - 5
	pos.x = clampf(pos.x, 8, maxf(8, view.x - menu_size.x - 8))
	pos.y = clampf(pos.y, 8, maxf(8, view.y - menu_size.y - 8))
	_menu.position = pos.round()


func _close_menu(restore_focus := true) -> void:
	if not is_instance_valid(_menu):
		return
	_menu.visible = false
	if is_instance_valid(_active_arrow):
		_set_arrow_open(_active_arrow, false)
		if restore_focus and is_open:
			_active_arrow.grab_focus()
	_active_arrow = null


func _set_arrow_open(arrow: Button, opened: bool) -> void:
	if is_instance_valid(arrow):
		arrow.set("opened", opened)


func _on_action_selected(id: int) -> void:
	var player := _menu_owner
	_close_menu()
	if not player.is_empty():
		action_requested.emit(player, "invite" if id == ACTION_INVITE else "join")


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
	if not _session_active:
		_session_active = true
		_paused_before = get_tree().paused
		_mouse_mode_before = Input.mouse_mode
		_focus_before = get_viewport().gui_get_focus_owner()
	if pause_game:
		get_tree().paused = true
	if release_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await get_tree().process_frame
	if not is_open:
		return
	_layout_panel()
	if search.is_visible_in_tree():
		search.grab_focus()
	else:
		get_viewport().gui_release_focus()
	_animate(1.0)


func close() -> void:
	if not is_open:
		return
	is_open = false
	_dragging = false
	_resizing = false
	_close_menu(false)
	_animate(0.0)


func _layout_panel() -> void:
	var view := get_viewport().get_visible_rect().size
	_ui_scale = minf(1.0, minf(maxf(1, view.x - 24) / MIN_WINDOW_SIZE.x, maxf(1, view.y - 24) / MIN_WINDOW_SIZE.y))
	if not _size_initialized:
		_preferred_size.y = clampf((view.y - 48) / _ui_scale, MIN_WINDOW_SIZE.y, 720)
		_size_initialized = true
	var maximum := ((view - Vector2(16, 16)) / _ui_scale).max(MIN_WINDOW_SIZE)
	panel.size = _preferred_size.clamp(MIN_WINDOW_SIZE, maximum)
	panel.pivot_offset = Vector2.ZERO
	panel.scale = Vector2.ONE * _ui_scale
	if not _placed:
		panel.position = ((view - panel.size * _ui_scale) * 0.5).round()
		_placed = true
	_clamp_panel()


func _clamp_panel() -> void:
	var view := get_viewport().get_visible_rect().size
	var extent := panel.size * _ui_scale
	panel.position.x = clampf(panel.position.x, 8, maxf(8, view.x - extent.x - 8))
	panel.position.y = clampf(panel.position.y, 8, maxf(8, view.y - extent.y - 8))


func _on_viewport_resized() -> void:
	_resizing = false
	_dragging = false
	_close_menu(false)
	if _tween and _tween.is_valid():
		_tween.kill()
	_placed = false
	_layout_panel()
	if is_open:
		panel.modulate.a = 1.0
		dimmer.modulate.a = DIM_ALPHA
	elif _session_active:
		_on_hidden()


func _begin_resize(pointer: Vector2) -> void:
	_close_menu(false)
	_dragging = false
	_resizing = true
	if _tween and _tween.is_valid():
		_tween.kill()
	panel.modulate.a = 1.0
	dimmer.modulate.a = DIM_ALPHA
	panel.scale = Vector2.ONE * _ui_scale
	_resize_origin = pointer
	_resize_start_size = panel.size


func _resize_to(pointer: Vector2) -> void:
	var view := get_viewport().get_visible_rect().size
	var maximum := ((view - panel.position - Vector2(8, 8)) / _ui_scale).max(MIN_WINDOW_SIZE)
	_preferred_size = (_resize_start_size + (pointer - _resize_origin) / _ui_scale).clamp(MIN_WINDOW_SIZE, maximum)
	panel.size = _preferred_size
	_clamp_panel()


func _animate(target: float) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	if target > 0 and panel.modulate.a < 0.01:
		panel.scale = Vector2.ONE * _ui_scale * PANEL_START_SCALE
	_tween = create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(dimmer, "modulate:a", DIM_ALPHA * target, ANIM_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(panel, "modulate:a", target, ANIM_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(panel, "scale", Vector2.ONE * _ui_scale * lerpf(PANEL_START_SCALE, 1.0, target), ANIM_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if target <= 0:
		_tween.finished.connect(_on_hidden)


func _on_hidden() -> void:
	if is_open:
		return
	visible = false
	_restore_game()


func _restore_game() -> void:
	if not _session_active:
		return
	_session_active = false
	if pause_game:
		get_tree().paused = _paused_before
	if release_mouse:
		Input.mouse_mode = _mouse_mode_before
	if is_instance_valid(_focus_before) and _focus_before.is_inside_tree():
		_focus_before.grab_focus()


func _exit_tree() -> void:
	_restore_game()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if toggle_with_shift_tab and _is_shift_tab(event):
			toggle()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and is_open:
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
				if not _menu.get_global_rect().has_point(event.position):
					_close_menu()
					get_viewport().set_input_as_handled()
			elif %ResizeGrip.get_global_rect().has_point(event.position):
				_begin_resize(event.position)
				get_viewport().set_input_as_handled()
			elif title_bar.get_global_rect().has_point(event.position) and not close_button.get_global_rect().has_point(event.position):
				_dragging = true
				_drag_offset = panel.position - event.position
				get_viewport().set_input_as_handled()
		else:
			_dragging = false
			if _resizing:
				_resizing = false
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _resizing:
		_resize_to(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		panel.position = event.position + _drag_offset
		_clamp_panel()
		get_viewport().set_input_as_handled()


func _is_shift_tab(event: InputEventKey) -> bool:
	return event.keycode == KEY_BACKTAB or event.physical_keycode == KEY_BACKTAB or (event.shift_pressed and (event.keycode == KEY_TAB or event.physical_keycode == KEY_TAB))
