extends CanvasLayer
## Incoming invitations remain actionable without opening the overlay.
const ClientScript = preload("network_client.gd")
var client: ClientScript
var _seen: Dictionary = {}
var _invitations: Array = []
var _friends: Array = []
var _busy := false
var _user_id := ""
var _card: PanelContainer
var _title: Label
var _details: Label
var _status: Label
var _accept: Button
var _decline: Button
var _sound: AudioStreamPlayer


func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS
	_card = PanelContainer.new()
	_card.theme = preload("overlay_theme.tres")
	var style := StyleBoxFlat.new()
	style.bg_color = Color("171411")
	style.border_color = Color("ff7417")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	_card.add_theme_stylebox_override("panel", style)
	add_child(_card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_card.add_child(column)
	_title = Label.new()
	_title.text = "Приглашение в игру"
	_title.add_theme_color_override("font_color", Color("ffac73"))
	column.add_child(_title)
	_details = Label.new()
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_details)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 12)
	column.add_child(_status)
	var buttons := VBoxContainer.new()
	column.add_child(buttons)
	_accept = Button.new()
	_accept.pressed.connect(_respond.bind(true))
	buttons.add_child(_accept)
	_decline = Button.new()
	_decline.text = "Отклонить · F7"
	_decline.pressed.connect(_respond.bind(false))
	buttons.add_child(_decline)
	for button in [_accept, _decline]:
		button.custom_minimum_size.y = 38
	_sound = AudioStreamPlayer.new()
	_sound.stream = _make_chime()
	_sound.volume_db = -14
	add_child(_sound)
	client.social_changed.connect(_on_social)
	_user_id = str(client.user.get("id", ""))
	client.user_changed.connect(_on_user)
	client.lobby_changed.connect(func(_lobby): _render())
	client.message.connect(func(text):
		if _busy:
			_status.text = text)
	get_viewport().size_changed.connect(_layout)
	# Wrapped labels update their minimum height after the container is sorted.
	_card.minimum_size_changed.connect(_layout)
	_card.hide()
	_layout()


func _layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	# Reset height as well: Control otherwise retains the large initial height
	# measured while the wrapped labels had not received their final width.
	_card.size = Vector2(minf(360, maxf(200, viewport_size.x - 32)), 0)
	_card.position = Vector2(maxf(0, viewport_size.x - _card.size.x - 16), 16)


func _on_user(user: Dictionary) -> void:
	var id := str(user.get("id", ""))
	if id == _user_id:
		return
	_user_id = id
	_seen.clear()
	_invitations.clear()
	_render()


func _on_social(data: Dictionary) -> void:
	_friends = data.get("friends", [])
	_invitations = data.get("invitations", []).duplicate(true)
	var incoming := false
	for invitation: Dictionary in _invitations:
		var id := str(invitation.get("id", ""))
		if not id.is_empty() and not _seen.has(id):
			_seen[id] = true
			incoming = true
	if incoming:
		_sound.play()
	_render()


func _render() -> void:
	_card.visible = not _invitations.is_empty()
	if _invitations.is_empty():
		return
	var invite: Dictionary = _invitations[0]
	var sender := "Игрок"
	for friend: Dictionary in _friends:
		if friend.get("id", "") == invite.get("fromUserId", "missing"):
			sender = str(friend.get("displayName", "Игрок"))
	_title.text = "Приглашение в игру" + (" · %d" % _invitations.size() if _invitations.size() > 1 else "")
	_details.text = "%s приглашает вас в лобби %s" % [sender, str(invite.get("roomCode", ""))]
	_accept.text = "Принять · F6" if client.lobby.is_empty() else "Выйти из лобби и принять · F6"
	_accept.disabled = _busy
	_decline.disabled = _busy
	if not _busy:
		_status.text = "F6 — принять, F7 — отклонить. Shift+Tab — открыть оверлей."
	_layout()


func _unhandled_key_input(event: InputEvent) -> void:
	if not _card.visible or _busy or not event is InputEventKey:
		return
	if not event.pressed or event.echo or event.alt_pressed or event.ctrl_pressed or event.meta_pressed:
		return
	if event.keycode in [KEY_F6, KEY_F7]:
		get_viewport().set_input_as_handled()
		_respond(event.keycode == KEY_F6)


func _respond(accept: bool) -> void:
	if _busy or _invitations.is_empty():
		return
	var id := str(_invitations[0].get("id", ""))
	_busy = true
	_render()
	_status.text = "Подключаемся…" if accept else "Отклоняем приглашение…"
	if accept:
		if not client.lobby.is_empty():
			await client.leave_lobby()
		if client.lobby.is_empty() and await client.accept_invitation(id):
			_invitations = _invitations.filter(func(item): return str(item.get("id", "")) != id)
	else:
		# The next social update confirms removal; retain the card on failure.
		await client.decline_invitation(id)
	var result_text := _status.text
	_busy = false
	_render()
	_status.text = result_text


func _make_chime() -> AudioStreamWAV:
	# A short two-note chime, generated locally without external assets.
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = 22050
	var samples := PackedByteArray()
	var count := int(0.28 * sound.mix_rate)
	samples.resize(count * 2)
	for i in count:
		var t := float(i) / sound.mix_rate
		var local_t := fmod(t, 0.14)
		var envelope := minf(local_t / 0.008, 1.0) * maxf(0, 1.0 - local_t / 0.14)
		var frequency := 660.0 if t < 0.14 else 880.0
		var sample := int(sin(TAU * frequency * t) * envelope * 16000)
		samples.encode_s16(i * 2, sample)
	sound.data = samples
	return sound
