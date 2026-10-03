extends Control
## Small authoritative arena: only input travels to the host; the host simulates movement.
const WORLD := Vector2(1200, 600)
const SPEED := 260.0
const PALETTE := [Color("ff8738"), Color("65d9c2"), Color("8ca8ff"), Color("f4ce70"), Color("e59ade"), Color("9cd77b"), Color("69c9ed"), Color("f18e95")]
var client: Node
var positions: Dictionary = {}
var targets: Dictionary = {}
var names: Dictionary = {}
var inputs: Dictionary = {}
var last_input: Dictionary = {}
var pulses: Dictionary = {}
var pulse_deadlines: Dictionary = {}
var _send_time := 0.0
var _connected := false
var _status: Label
var _room: Label
var _copy: Button
var _hint: Label
var _network_note := "Войдите в аккаунт, затем создайте лобби или введите его код."


func _ready() -> void:
	client = FoxhaGameMultiplayer.client
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = preload("res://addons/foxha-game-multiplayer/overlay_theme.tres")
	_build_ui()
	client.transport_ready.connect(_transport_ready)
	client.lobby_changed.connect(_lobby_changed)
	client.message.connect(func(text: String): _network_note = text)
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(_connected_to_host)
	multiplayer.server_disconnected.connect(func(): _connected = false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not OS.has_feature("headless"):
		FoxhaGameMultiplayer.open_list.call_deferred()
	_lobby_changed(client.lobby)


func _build_ui() -> void:
	var title := Label.new()
	title.text = "FOXHA / PLAYGROUND"
	title.position = Vector2(32, 26)
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("ff8738"))
	add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Общая арена · до 8 игроков · WebRTC"
	subtitle.position = Vector2(34, 72)
	subtitle.add_theme_color_override("font_color", Color("919aa8"))
	add_child(subtitle)
	var controls := HBoxContainer.new()
	controls.position = Vector2(32, 110)
	controls.add_theme_constant_override("separation", 12)
	add_child(controls)
	var account := Button.new()
	account.text = "АККАУНТ И ЛОББИ  /  Shift+Tab"
	account.pressed.connect(FoxhaGameMultiplayer.toggle_list)
	controls.add_child(account)
	_copy = Button.new()
	_copy.text = "Скопировать код"
	_copy.pressed.connect(func():
		DisplayServer.clipboard_set(str(client.lobby.get("code", "")))
		_network_note = "Код скопирован — отправьте его второму игроку."
	)
	controls.add_child(_copy)
	_room = Label.new()
	_room.add_theme_font_size_override("font_size", 18)
	controls.add_child(_room)
	_status = Label.new()
	_status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_status.offset_left = 32
	_status.offset_top = -86
	_status.offset_right = -32
	_status.offset_bottom = -55
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_status)
	_hint = Label.new()
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_left = 32
	_hint.offset_top = -50
	_hint.offset_right = -32
	_hint.offset_bottom = -20
	_hint.text = "WASD / стрелки — движение     Space — импульс     Shift+Tab — лобби"
	_hint.add_theme_color_override("font_color", Color("919aa8"))
	add_child(_hint)


func _transport_ready(_peer: WebRTCMultiplayerPeer) -> void:
	positions.clear()
	targets.clear()
	names.clear()
	inputs.clear()
	last_input.clear()
	pulses.clear()
	pulse_deadlines.clear()
	_connected = multiplayer.is_server()
	if _connected:
		_spawn(1, str(client.user.get("displayName", "Хост")))
		_network_note = "Лобби открыто. Передайте код друзьям."
	else:
		_network_note = "Устанавливаем WebRTC-соединение с хостом…"


func _lobby_changed(room: Dictionary) -> void:
	_copy.disabled = room.is_empty()
	_room.text = "Вне лобби" if room.is_empty() else "КОД  " + str(room.code)
	if room.is_empty():
		_connected = false
		positions.clear()
		targets.clear()
		names.clear()
		pulses.clear()
	queue_redraw()


func _spawn(id: int, nickname: String) -> void:
	positions[id] = Vector2(180 + (id - 1) % 4 * 270, 190 + ((id - 1) / 4 as int) * 220)
	names[id] = nickname.strip_edges().left(24)
	inputs[id] = Vector2.ZERO
	last_input[id] = Time.get_ticks_msec()


func _peer_connected(id: int) -> void:
	if multiplayer.is_server():
		_spawn(id, "Игрок #%d" % id)
		_network_note = "Игрок #%d подключился." % id


func _connected_to_host() -> void:
	_connected = true
	_hello.rpc_id(1, str(client.user.get("displayName", "Игрок")))
	_network_note = "Соединение установлено. Двигайтесь — другие игроки видят вас."


func _peer_disconnected(id: int) -> void:
	positions.erase(id)
	targets.erase(id)
	names.erase(id)
	inputs.erase(id)
	last_input.erase(id)
	pulses.erase(id)
	pulse_deadlines.erase(id)


@rpc("any_peer", "call_remote", "reliable")
func _hello(nickname: String) -> void:
	if multiplayer.is_server():
		var sender := multiplayer.get_remote_sender_id()
		if positions.has(sender):
			names[sender] = nickname.strip_edges().left(24)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _move(direction: Vector2) -> void:
	if not multiplayer.is_server() or not direction.is_finite():
		return
	var sender := multiplayer.get_remote_sender_id()
	if positions.has(sender):
		inputs[sender] = direction.limit_length(1.0)
		last_input[sender] = Time.get_ticks_msec()


@rpc("authority", "call_remote", "unreliable_ordered")
func _snapshot(state: Dictionary, labels: Dictionary, active_pulses: Dictionary) -> void:
	targets = state
	names = labels
	pulses = active_pulses
	for id in positions.keys():
		if not state.has(id):
			positions.erase(id)
	for id in state:
		if not positions.has(id):
			positions[id] = state[id]


@rpc("any_peer", "call_remote", "reliable")
func _pulse() -> void:
	if multiplayer.is_server():
		_start_pulse(multiplayer.get_remote_sender_id())


func _start_pulse(id: int) -> void:
	var now := Time.get_ticks_msec()
	if positions.has(id) and now >= int(pulse_deadlines.get(id, 0)):
		pulses[id] = 1.0
		pulse_deadlines[id] = now + 1000


func _unhandled_key_input(event: InputEvent) -> void:
	if _connected and not FoxhaGameMultiplayer.is_list_open() and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_SPACE:
		if multiplayer.is_server():
			_start_pulse(1)
		else:
			_pulse.rpc_id(1)


func _direction() -> Vector2:
	if FoxhaGameMultiplayer.is_list_open():
		return Vector2.ZERO
	return Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	).limit_length(1.0)


func _physics_process(delta: float) -> void:
	if not _connected or client.lobby.is_empty():
		return
	var direction := _direction()
	_send_time += delta
	if multiplayer.is_server():
		inputs[1] = direction
		last_input[1] = Time.get_ticks_msec()
		for id in positions:
			var move: Vector2 = inputs.get(id, Vector2.ZERO)
			if Time.get_ticks_msec() - int(last_input.get(id, 0)) > 500:
				move = Vector2.ZERO
			positions[id] = (positions[id] + move * SPEED * delta).clamp(Vector2(24, 24), WORLD - Vector2(24, 24))
		for id in pulses.keys():
			pulses[id] = maxf(0, float(pulses[id]) - delta * 1.5)
			if pulses[id] == 0:
				pulses.erase(id)
		if _send_time >= 0.05:
			_send_time = 0
			for id in multiplayer.get_peers():
				if _can_send(id):
					_snapshot.rpc_id(id, positions, names, pulses)
	elif _send_time >= 0.033:
		_send_time = 0
		if _can_send(1):
			_move.rpc_id(1, direction)


func _can_send(id: int) -> bool:
	if client.rtc == null or not client.rtc.has_peer(id):
		return false
	var peer: Dictionary = client.rtc.get_peer(id)
	for channel: WebRTCDataChannel in peer.get("channels", []):
		if channel.get_ready_state() != WebRTCDataChannel.STATE_OPEN:
			return false
	return peer.get("connected", false)


func _process(delta: float) -> void:
	if _connected and not multiplayer.is_server():
		for id in targets:
			positions[id] = (positions.get(id, targets[id]) as Vector2).lerp(targets[id], minf(1, delta * 18))
	var role := "Хост" if _connected and multiplayer.is_server() else ("Подключён" if _connected else "Ожидание")
	_status.text = "%s · %d / 8 игроков    |    %s" % [role, positions.size(), _network_note]
	_status.tooltip_text = _network_note
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("0c1016"))
	var arena := Rect2(Vector2(32, 174), Vector2(maxf(200, size.x - 64), maxf(160, size.y - 280)))
	draw_style_box(_arena_style(), arena)
	for x in range(1, 20):
		var line_x := arena.position.x + arena.size.x * x / 20
		draw_line(Vector2(line_x, arena.position.y), Vector2(line_x, arena.end.y), Color("202631"))
	for y in range(1, 10):
		var line_y := arena.position.y + arena.size.y * y / 10
		draw_line(Vector2(arena.position.x, line_y), Vector2(arena.end.x, line_y), Color("202631"))
	var font := ThemeDB.fallback_font
	if positions.is_empty():
		var prompt := "Создайте лобби или присоединитесь по коду"
		draw_string(font, arena.get_center() - Vector2(font.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x / 2, 0), prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("798393"))
	for id in positions:
		var point: Vector2 = arena.position + positions[id] / WORLD * arena.size
		var color: Color = PALETTE[(int(id) - 1) % PALETTE.size()]
		var pulse := float(pulses.get(id, 0))
		if pulse > 0:
			draw_arc(point, 24 + (1 - pulse) * 80, 0, TAU, 48, Color(color, pulse), 3, true)
		draw_circle(point + Vector2(0, 6), 20, Color(0, 0, 0, 0.35))
		draw_circle(point, 18, color, true, -1, true)
		draw_circle(point - Vector2(4, 5), 5, Color(1, 1, 1, 0.35), true, -1, true)
		if _connected and id == multiplayer.get_unique_id():
			draw_arc(point, 25, 0, TAU, 40, Color("ffffff"), 2, true)
		var nickname := str(names.get(id, "Игрок"))
		var width := font.get_string_size(nickname, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_string(font, point + Vector2(-width / 2, -35), nickname, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("eef1f6"))


func _arena_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color("141a23")
	box.border_color = Color("34303a")
	box.set_border_width_all(1)
	box.set_corner_radius_all(14)
	return box
