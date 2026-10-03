extends VBoxContainer
## Account and lobby controls embedded in the social overlay.
const ClientScript := preload("res://addons/foxha-game-multiplayer/network_client.gd")
var client: ClientScript
var overlay: CanvasLayer
var _players_button: Button
var _session_button: Button
var _notice: Label
var _auth: VBoxContainer
var _loading: Label
var _lobby: VBoxContainer
var _email: LineEdit
var _password: LineEdit
var _name: LineEdit
var _code: LineEdit
var _submit: Button
var _resend: Button
var _mode_button: Button
var _register := false
var _confirm := false
var _busy := false
var _show_players := false
var _room_status: Label
var _create: Button
var _join: Button
var _join_code: LineEdit
var _capacity: SpinBox
var _capacity_label: Label
var _visibility: OptionButton
var _leave: Button
var _retry: Button
var _members: Label
var _invites: VBoxContainer
var _invitation_ids := ""
var _friends_snapshot := ""
var _members_snapshot := ""


func attach(target: CanvasLayer, network: ClientScript) -> void:
	overlay = target
	client = network
	name = "SessionPanel"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var content: VBoxContainer = overlay.get_node("Panel/Margin/Content")
	content.add_child(self)
	content.move_child(self, 2)
	var tabs := HBoxContainer.new()
	add_child(tabs)
	_players_button = _button(tabs, "Игроки", func(): _show_players = true; _update_visibility())
	_session_button = _button(tabs, "Аккаунт", func(): _show_players = false; _update_visibility())
	var tab_group := ButtonGroup.new()
	for tab: Button in [_players_button, _session_button]:
		tab.toggle_mode = true
		tab.button_group = tab_group
		tab.custom_minimum_size.y = 40
	_notice = _label(self, "")
	_notice.name = "Notice"
	_notice.visible = false
	_notice.add_theme_font_size_override("font_size", 12)
	_notice.add_theme_color_override("font_color", Color("#ffac73"))
	_notice.max_lines_visible = 3
	client.message.connect(func(text: String):
		_notice.text = text
		_notice.tooltip_text = text
		_notice.visible = not text.is_empty())
	_loading = _label(self, "Восстанавливаем вход…")
	_loading.name = "SessionLoading"
	_loading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_loading.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	client.initialization_changed.connect(_update_visibility)
	_auth = VBoxContainer.new()
	_auth.name = "Auth"
	_auth.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_auth.add_theme_constant_override("separation", 10)
	var auth_scroll := ScrollContainer.new()
	auth_scroll.name = "AuthScroll"
	auth_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	auth_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(auth_scroll)
	auth_scroll.add_child(_auth)
	_label(_auth, "Ваш аккаунт Foxha").add_theme_font_size_override("font_size", 20)
	_name = _field(_auth, "Имя игрока", "DisplayName")
	_email = _field(_auth, "Почта", "Email")
	_password = _field(_auth, "Пароль", "Password")
	_password.secret = true
	_code = _field(_auth, "Код из письма", "EmailCode")
	_code.max_length = 6
	_submit = _button(_auth, "Войти", _authenticate)
	_submit.name = "Submit"
	_mode_button = _button(_auth, "Создать аккаунт", _change_mode)
	_resend = _button(_auth, "Отправить код повторно", _resend_code)
	_password.text_submitted.connect(func(_text: String): _authenticate())
	_code.text_submitted.connect(func(_text: String): _authenticate())
	_label(_auth, "Вход и регистрация прямо в игре. Пароль не сохраняется.").add_theme_font_size_override("font_size", 12)
	var scroller := ScrollContainer.new()
	scroller.name = "LobbyScroll"
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroller)
	_lobby = VBoxContainer.new()
	_lobby.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lobby.add_theme_constant_override("separation", 8)
	scroller.add_child(_lobby)
	_room_status = _label(_lobby, "Создайте лобби или введите код.")
	_room_status.add_theme_font_size_override("font_size", 16)
	_capacity_label = _label(_lobby, "Максимум игроков")
	_capacity = SpinBox.new()
	_capacity.min_value = 2
	_capacity.max_value = 20
	_capacity.value = 20
	_lobby.add_child(_capacity)
	_visibility = OptionButton.new()
	for title in ["По коду", "Для друзей", "По приглашению"]:
		_visibility.add_item(title)
	_visibility.select(1)
	_lobby.add_child(_visibility)
	_create = _button(_lobby, "Создать лобби", _create_lobby)
	_join_code = _field(_lobby, "Код лобби", "RoomCode")
	_join_code.max_length = 10
	_join_code.text_submitted.connect(func(_text: String): _join_lobby())
	_join = _button(_lobby, "Присоединиться", _join_lobby)
	_members = _label(_lobby, "")
	_leave = _button(_lobby, "Выйти из лобби", _leave_lobby)
	_retry = _button(_lobby, "Переподключиться", _reconnect)
	_label(_lobby, "ПРИГЛАШЕНИЯ").add_theme_font_size_override("font_size", 11)
	_invites = VBoxContainer.new()
	_lobby.add_child(_invites)
	_label(_invites, "Пока нет приглашений.")
	var logout_button := _button(overlay.get_node("Panel/Margin/Content/Profile/Header"), "", _logout)
	logout_button.name = "Logout"
	logout_button.icon = preload("res://addons/foxha-game-multiplayer/icons/logout.svg")
	logout_button.tooltip_text = "Выйти из аккаунта"
	logout_button.custom_minimum_size = Vector2(40, 40)
	logout_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	logout_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	logout_button.theme_type_variation = &"QuietButton"
	client.user_changed.connect(_user_changed)
	client.lobby_changed.connect(_lobby_changed)
	client.social_changed.connect(_social_changed)
	client.confirmation_required.connect(func(): _confirm = true; _form_mode())
	_user_changed(client.user)
	_lobby_changed(client.lobby)


func _label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _field(parent: Node, placeholder: String, node_name: String) -> LineEdit:
	var field := LineEdit.new()
	field.name = node_name
	field.placeholder_text = placeholder
	field.max_length = 254
	field.custom_minimum_size.y = 38
	parent.add_child(field)
	return field


func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _form_mode() -> void:
	_name.visible = _register and not _confirm
	_password.visible = not _confirm
	_code.visible = _confirm
	_resend.visible = _confirm
	_submit.text = "Подтвердить" if _confirm else ("Зарегистрироваться" if _register else "Войти")
	_mode_button.text = "Вернуться ко входу" if _confirm or _register else "Создать аккаунт"


func _change_mode() -> void:
	if _busy:
		return
	_register = not _register if not _confirm else false
	_confirm = false
	_password.clear()
	_form_mode()


func _authenticate() -> void:
	if _busy:
		return
	_busy = true
	_submit.disabled = true
	if _confirm:
		if await client.confirm_email(_email.text, _code.text):
			_confirm = false
			_register = false
			_form_mode()
	else:
		var password := _password.text
		_password.clear()
		await client.authenticate(_register, _email.text, password, _name.text)
	_busy = false
	_submit.disabled = false


func _resend_code() -> void:
	_resend.disabled = true
	await client.resend_code(_email.text)
	_resend.disabled = false


func _user_changed(data: Dictionary) -> void:
	_players_button.disabled = data.is_empty()
	_session_button.text = "Аккаунт" if data.is_empty() else "Лобби"
	if data.is_empty():
		_friends_snapshot = ""
		_members_snapshot = ""
		_show_players = false
		overlay.set_me({"nickname": "Гость", "status": "offline"})
		overlay.set_friends([])
		overlay.set_other([])
	else:
		overlay.set_me({"nickname": data.get("displayName", "Игрок"), "status": "online"})
	_form_mode()
	_update_visibility()


func _update_visibility() -> void:
	var logged_in := not client.user.is_empty()
	var loading := client.initializing
	_loading.visible = loading
	_players_button.get_parent().visible = not loading
	_players_button.set_pressed_no_signal(_show_players)
	_session_button.set_pressed_no_signal(not _show_players)
	overlay._close_menu(false)
	var content: VBoxContainer = overlay.get_node("Panel/Margin/Content")
	content.get_node("Profile").visible = logged_in and not loading
	content.get_node("Heading").visible = false
	content.get_node("Filters").visible = false
	for part in ["Search", "Scroll"]:
		content.get_node(part).visible = logged_in and _show_players and not loading
	size_flags_vertical = Control.SIZE_FILL if logged_in and _show_players else Control.SIZE_EXPAND_FILL
	_auth.get_parent().visible = not logged_in and not loading
	get_node("LobbyScroll").visible = logged_in and not _show_players and not loading


func _lobby_changed(data: Dictionary) -> void:
	var joined := not data.is_empty()
	_create.disabled = joined or _busy
	_join.disabled = joined or _busy
	_join_code.visible = not joined
	_join.visible = not joined
	_capacity.visible = not joined
	_capacity_label.visible = not joined
	_visibility.visible = not joined
	_leave.visible = joined
	_retry.visible = joined and client._my_peer_id() != 1
	_room_status.text = "Лобби " + str(data.get("code", "")) if joined else "Создайте лобби или введите код."
	_members.text = "%d / %d игроков" % [data.get("members", []).size(), data.get("capacity", 20)] if joined else ""
	if joined:
		var players: Array = []
		for member: Dictionary in data.get("members", []):
			if member.userId != client.user.get("id"):
				players.append({"id": member.userId, "nickname": "Игрок #" + str(member.peerId), "status": "in_game"})
		var snapshot := JSON.stringify(players)
		if snapshot != _members_snapshot:
			_members_snapshot = snapshot
			overlay.set_other(players)
	else:
		if _members_snapshot != "[]":
			_members_snapshot = "[]"
			overlay.set_other([])


func _social_changed(data: Dictionary) -> void:
	var friends: Array = []
	for friend: Dictionary in data.get("friends", []):
		var presence: Dictionary = friend.get("presence", {})
		friends.append({"id": friend.id, "nickname": friend.displayName,
			"status": presence.get("status", "offline"), "roomCode": presence.get("roomCode"),
			"can_join": presence.get("canJoin", false)})
	var snapshot := JSON.stringify(friends)
	if snapshot != _friends_snapshot:
		_friends_snapshot = snapshot
		overlay.set_friends(friends)
	var invites: Array = data.get("invitations", [])
	var ids := JSON.stringify(invites)
	if ids == _invitation_ids:
		return
	_invitation_ids = ids
	for child in _invites.get_children():
		_invites.remove_child(child)
		child.queue_free()
	if invites.is_empty():
		_label(_invites, "Пока нет приглашений.")
	for invite: Dictionary in invites:
		_label(_invites, "Лобби " + str(invite.roomCode))
		_button(_invites, "Принять", _accept.bind(str(invite.id)))
		_button(_invites, "Отклонить", client.decline_invitation.bind(str(invite.id)))


func _create_lobby() -> void:
	if _busy:
		return
	_busy = true
	_lobby_changed(client.lobby)
	await client.create_lobby(int(_capacity.value), ["code", "friends", "invite"][_visibility.selected])
	_busy = false
	_lobby_changed(client.lobby)


func _join_lobby() -> void:
	if _busy:
		return
	_busy = true
	_lobby_changed(client.lobby)
	await client.join_lobby(_join_code.text)
	_busy = false
	_lobby_changed(client.lobby)


func _accept(id: String) -> void:
	if _busy:
		return
	_busy = true
	await client.accept_invitation(id)
	_busy = false


func _leave_lobby() -> void:
	await client.leave_lobby()


func _reconnect() -> void:
	if _busy:
		return
	_busy = true
	await client.reconnect()
	_busy = false


func _logout() -> void:
	await client.logout()
