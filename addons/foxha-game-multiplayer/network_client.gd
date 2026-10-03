extends Node
## HTTPS account/lobby client and host-based WebRTC transport.
## Credentials live only in memory. No account cookie or password is persisted.

signal user_changed(user: Dictionary)
signal lobby_changed(lobby: Dictionary)
signal social_changed(data: Dictionary)
signal confirmation_required
signal message(text: String)
signal transport_ready(peer: WebRTCMultiplayerPeer)

var api_url := "https://games.foxha.ru"
var game_id := ""
var protocol_version := "1"
var allow_local_http := false
## "relay" is useful for diagnostics; normal games use "all".
var ice_transport_policy := "all"
var user: Dictionary = {}
var lobby: Dictionary = {}
var rtc: WebRTCMultiplayerPeer
var _tokens: Dictionary = {}
var _renew_at := 0.0
var _poll_at := 0
var _polling := false
var _refreshing := false
var _generation := 0
var _after := 0
var _ice: Array = []
var _peers: Dictionary = {}
var _remote_ready: Dictionary = {}
var _pending_ice: Dictionary = {}
var _peer_started: Dictionary = {}
var _outbox: Array[Dictionary] = []
var _sending := false
var _send_after := 0
var _web: JavaScriptObject
var _request_id := 0
var _tick := 0
var _last_error := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("web"):
		JavaScriptBridge.eval("""
			if (!window.__foxhaSDK) {
				const replies = new Map();
				window.addEventListener('message', event => {
					if (event.source !== window.parent || event.data?.type !== 'foxha:multiplayer:response') return;
					if (replies.has(event.data.id)) replies.set(event.data.id, JSON.stringify(event.data));
				});
				window.__foxhaSDK = {
					send(json) { const data = JSON.parse(json); replies.set(data.id, ''); window.parent.postMessage(data, '*'); },
					take(id) { const value = replies.get(id) || ''; if (value) replies.delete(id); return value; },
					forget(id) { replies.delete(id); }
				};
			}
		""", true)
		_web = JavaScriptBridge.get_interface("__foxhaSDK")


func initialize() -> void:
	if game_id.is_empty():
		message.emit("Сетевая игра пока не настроена.")
		return
	var result := await _request("me")
	if result.ok:
		user = result.data
		user_changed.emit(user)


func authenticate(register: bool, email: String, password: String, display_name := "") -> bool:
	var generation := _generation
	var result := await _request("auth_register" if register else "auth_login",
		{"email": email, "password": password, "displayName": display_name})
	if generation != _generation:
		return false
	if not result.ok:
		_report(result)
		if result.error.get("code") == "email_not_confirmed":
			confirmation_required.emit()
		return false
	if result.data.get("requiresEmailConfirmation", false):
		confirmation_required.emit()
		message.emit("Введите код из письма.")
		return false
	_use_session(result.data)
	message.emit("Вы вошли в Foxha.")
	return true


func confirm_email(email: String, code: String) -> bool:
	var result := await _request("auth_confirm", {"email": email, "confirmationCode": code})
	if not result.ok:
		_report(result)
		return false
	message.emit("Почта подтверждена. Войдите с вашим паролем.")
	return true


func resend_code(email: String) -> void:
	var result := await _request("auth_resend", {"email": email})
	if result.ok:
		message.emit("Если адрес ожидает подтверждения, код отправлен. Повтор — через 60 секунд.")
	else:
		_report(result)


func _use_session(data: Dictionary) -> void:
	user = data.get("user", {})
	_tokens = data.get("tokens", {})
	_renew_at = Time.get_unix_time_from_system() + 12 * 60
	_last_error = ""
	user_changed.emit(user)


func logout() -> void:
	await _request("logout")
	_generation += 1
	_drop_lobby()
	user = {}
	_tokens = {}
	user_changed.emit(user)


func create_lobby(capacity := 8, visibility := "friends") -> bool:
	if not await _prepare_transport():
		return false
	var result := await _request("create", {"capacity": capacity, "visibility": visibility, "protocolVersion": protocol_version})
	return await _enter_lobby(result)


func join_lobby(code: String) -> bool:
	if not await _prepare_transport():
		return false
	return await _enter_lobby(await _request("join", {"code": code.strip_edges().to_upper(), "protocolVersion": protocol_version}))


func accept_invitation(id: String) -> bool:
	if not await _prepare_transport():
		return false
	return await _enter_lobby(await _request("accept", {"invitationId": id, "protocolVersion": protocol_version}))


func decline_invitation(id: String) -> void:
	var result := await _request("decline", {"invitationId": id})
	if not result.ok:
		_report(result)
	_poll_at = 0


func invite_player(id: String) -> void:
	if lobby.is_empty():
		if not await create_lobby():
			return
	var result := await _request("invite", {"code": lobby.code, "userId": id})
	if result.ok:
		message.emit("Приглашение отправлено.")
	else:
		_report(result)


func leave_lobby() -> void:
	var code: String = lobby.get("code", "")
	_drop_lobby()
	if not code.is_empty():
		var result := await _request("leave", {"code": code})
		if not result.ok and result.get("status", 0) != 404:
			_report(result)


func reconnect() -> void:
	var code: String = lobby.get("code", "")
	if code.is_empty():
		return
	if int(_my_peer_id()) == 1:
		message.emit("Хосту нужно пересоздать лобби и пригласить игроков.")
		return
	await leave_lobby()
	await join_lobby(code)


func _prepare_transport() -> bool:
	if user.is_empty():
		message.emit("Сначала войдите в аккаунт.")
		return false
	if not lobby.is_empty():
		message.emit("Сначала выйдите из текущего лобби.")
		return false
	var probe := WebRTCPeerConnection.new()
	if probe.initialize({}) != OK:
		message.emit("WebRTC недоступен в этой сборке игры.")
		return false
	probe.close()
	var result := await _request("ice")
	if not result.ok:
		_report(result)
		return false
	_ice = result.data.get("iceServers", [])
	if not OS.has_feature("web"):
		# The pinned libjuice native build supports TURN over UDP only.
		var supported: Array = []
		for server: Dictionary in _ice:
			var urls: Array = []
			var source = server.get("urls", [])
			if source is String:
				source = [source]
			for url: String in source:
				if not url.begins_with("turns:") and not "transport=tcp" in url:
					urls.append(url)
			if not urls.is_empty():
				var entry := server.duplicate()
				entry.urls = urls
				supported.append(entry)
		_ice = supported
	if not result.data.get("relayAvailable", false):
		message.emit("Релей недоступен: подключение возможно не во всех сетях.")
	return true


func _enter_lobby(result: Dictionary) -> bool:
	if not result.ok:
		_report(result)
		return false
	lobby = result.data
	_after = 0
	rtc = WebRTCMultiplayerPeer.new()
	var error := rtc.create_server() if _my_peer_id() == 1 else rtc.create_client(_my_peer_id())
	if error != OK:
		await leave_lobby()
		message.emit("Не удалось создать сетевое подключение.")
		return false
	multiplayer.multiplayer_peer = rtc
	_sync_peers()
	lobby_changed.emit(lobby)
	transport_ready.emit(rtc)
	_poll_at = 0
	return true


func _my_peer_id() -> int:
	for member: Dictionary in lobby.get("members", []):
		if member.userId == user.get("id"):
			return int(member.peerId)
	return 0


func _sync_peers() -> void:
	if rtc == null:
		return
	var wanted: Array[int] = []
	for member: Dictionary in lobby.get("members", []):
		var id := int(member.peerId)
		if id != _my_peer_id() and (_my_peer_id() == 1 or id == 1):
			wanted.append(id)
	for id: int in _peers.keys():
		if not wanted.has(id):
			rtc.remove_peer(id)
			_peers.erase(id)
			_remote_ready.erase(id)
			_pending_ice.erase(id)
			_peer_started.erase(id)
	for id: int in wanted:
		if _peers.has(id):
			continue
		var connection := WebRTCPeerConnection.new()
		if connection.initialize({"iceServers": _ice, "iceTransportPolicy": ice_transport_policy}) != OK or rtc.add_peer(connection, id) != OK:
			message.emit("Не удалось подготовить WebRTC.")
			continue
		_peers[id] = connection
		_pending_ice[id] = []
		_peer_started[id] = Time.get_ticks_msec()
		connection.session_description_created.connect(_description_created.bind(id))
		connection.ice_candidate_created.connect(_candidate_created.bind(id))
		if _my_peer_id() == 1:
			connection.create_offer()


func _description_created(kind: String, sdp: String, id: int) -> void:
	if not _peers.has(id):
		return
	if _peers[id].set_local_description(kind, sdp) == OK:
		_queue_signal(id, kind, {"sdp": _filter_sdp(sdp)})


func _candidate_created(mid: String, index: int, sdp: String, id: int) -> void:
	if ice_transport_policy == "relay":
		print("TURN diagnostic: gathered ", sdp.get_slice(" typ ", 1).get_slice(" ", 0))
	if ice_transport_policy == "relay" and not " typ relay" in sdp:
		return
	_queue_signal(id, "ice", {"mid": mid, "index": index, "sdp": sdp})


func _filter_sdp(sdp: String) -> String:
	if ice_transport_policy != "relay":
		return sdp
	# webrtc-native ignores the browser's iceTransportPolicy setting.
	var lines := PackedStringArray()
	for line in sdp.split("\n"):
		if not line.begins_with("a=candidate:") or " typ relay" in line:
			lines.append(line)
	return "\n".join(lines)


func _queue_signal(id: int, kind: String, payload: Dictionary) -> void:
	if lobby.is_empty():
		return
	if _outbox.size() >= 256:
		message.emit("Слишком много сетевых сигналов. Переподключитесь к лобби.")
		return
	_outbox.append({"code": lobby.code, "toPeerId": id, "kind": kind, "payload": JSON.stringify(payload)})


func _apply_signal(data: Dictionary) -> void:
	var id := int(data.get("fromPeerId", 0))
	if not _peers.has(id):
		return
	var parser := JSON.new()
	if parser.parse(str(data.get("payload", ""))) != OK:
		return
	var payload = parser.data
	if not payload is Dictionary:
		return
	var connection: WebRTCPeerConnection = _peers[id]
	if connection.get_connection_state() in [WebRTCPeerConnection.STATE_CLOSED, WebRTCPeerConnection.STATE_FAILED]:
		return
	var kind: String = data.get("kind", "")
	if kind == "ice":
		if ice_transport_policy == "relay" and not " typ relay" in str(payload.get("sdp", "")):
			return
		if not _remote_ready.get(id, false):
			_pending_ice[id].append(payload)
		else:
			connection.add_ice_candidate(str(payload.get("mid", "")), int(payload.get("index", 0)), str(payload.get("sdp", "")))
	elif (kind == "offer" and _my_peer_id() != 1) or (kind == "answer" and _my_peer_id() == 1):
		if connection.set_remote_description(kind, _filter_sdp(str(payload.get("sdp", "")))) == OK:
			_remote_ready[id] = true
			for candidate: Dictionary in _pending_ice[id]:
				connection.add_ice_candidate(str(candidate.get("mid", "")), int(candidate.get("index", 0)), str(candidate.get("sdp", "")))
			_pending_ice[id].clear()


func _drop_lobby() -> void:
	_generation += 1
	if rtc != null:
		if multiplayer.multiplayer_peer == rtc:
			multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		rtc.close()
	rtc = null
	lobby = {}
	_peers.clear()
	_pending_ice.clear()
	_remote_ready.clear()
	_peer_started.clear()
	_outbox.clear()
	_after = 0
	lobby_changed.emit(lobby)


func _process(_delta: float) -> void:
	if user.is_empty() or game_id.is_empty():
		return
	var now := Time.get_ticks_msec()
	if not _polling and now >= _poll_at:
		_poll_at = now + 1000
		_poll()
	if not _sending and not _outbox.is_empty() and now >= _send_after:
		_flush_signal()
	for id: int in _peer_started.keys():
		var connection: WebRTCPeerConnection = _peers[id]
		if connection.get_connection_state() == WebRTCPeerConnection.STATE_CONNECTED:
			_peer_started.erase(id)
		elif now - int(_peer_started[id]) > 30000:
			_peer_started.erase(id)
			message.emit("Не удалось подключиться за 30 секунд. Проверьте сеть и переподключитесь.")


func _poll() -> void:
	_polling = true
	var generation := _generation
	if not _tokens.is_empty() and Time.get_unix_time_from_system() >= _renew_at:
		await _refresh()
	var result := await _request("heartbeat")
	if generation != _generation:
		_polling = false
		return
	if not result.ok:
		_report(result)
		_poll_at = Time.get_ticks_msec() + 5000
		if result.get("status", 0) == 401:
			_tokens = {}
			user = {}
			_drop_lobby()
			user_changed.emit(user)
	else:
		var server_room = result.data.get("room")
		if not lobby.is_empty():
			if server_room == null:
				_drop_lobby()
				message.emit("Лобби закрыто или время ожидания истекло.")
			elif server_room.code == lobby.code:
				lobby = server_room
				_sync_peers()
				lobby_changed.emit(lobby)
				var code: String = lobby.code
				var signals := await _request("receive", {"code": code, "after": _after})
				if generation == _generation and lobby.get("code") == code:
					if signals.ok:
						for data: Dictionary in signals.data:
							_apply_signal(data)
							_after = maxi(_after, int(data.id))
					else:
						_report(signals)
		_tick += 1
		if _tick % 3 == 1:
			var social := await _request("social")
			if social.ok and generation == _generation:
				social_changed.emit(social.data)
	_polling = false


func _flush_signal() -> void:
	_sending = true
	var item: Dictionary = _outbox.pop_front()
	var result := await _request("signal", item)
	if not result.ok and lobby.get("code") == item.code:
		var attempts := int(item.get("_attempts", 0)) + 1
		if attempts <= 3 and (result.get("status", 0) == 0 or result.get("status", 0) >= 500 or result.get("status", 0) == 429):
			item._attempts = attempts
			_outbox.push_front(item)
			_send_after = Time.get_ticks_msec() + attempts * 2000
		else:
			_report(result)
	_sending = false


func _refresh() -> void:
	if _refreshing:
		while _refreshing:
			await get_tree().process_frame
		return
	_refreshing = true
	var generation := _generation
	var result := await _request("auth_refresh", {"refreshToken": _tokens.get("refreshToken", "")})
	if generation != _generation:
		_refreshing = false
		return
	if result.ok:
		_use_session(result.data)
	else:
		_renew_at = Time.get_unix_time_from_system() + 10
	_refreshing = false


func _report(result: Dictionary) -> void:
	var text: String = result.get("error", {}).get("message", "Не удалось выполнить запрос.")
	if text != _last_error:
		_last_error = text
		message.emit(text)


func _error(code: String, text: String, status := 0) -> Dictionary:
	return {"ok": false, "error": {"code": code, "message": text}, "status": status}


func _request(action: String, fields: Dictionary = {}) -> Dictionary:
	if game_id.is_empty():
		return _error("game_not_configured", "Сетевая игра пока не настроена.")
	var data := fields.duplicate()
	data.action = action
	if not action.begins_with("auth_") and not _tokens.is_empty():
		data.accessToken = _tokens.get("accessToken", "")
	if OS.has_feature("web"):
		_request_id += 1
		data.id = "foxha-sdk-" + str(_request_id)
		data.type = "foxha:multiplayer"
		_web.send(JSON.stringify(data))
		var until := Time.get_ticks_msec() + 15000
		while Time.get_ticks_msec() < until:
			var raw: String = _web.take(data.id)
			if not raw.is_empty():
				var reply = JSON.parse_string(raw)
				var error = reply.get("error")
				if error != null:
					if error is Dictionary:
						return {"ok": false, "error": error, "status": 401 if error.get("code") in ["unauthorized", "game_session_expired"] else 400}
					return _error(str(error), "Запрос не выполнен.")
				return {"ok": true, "data": reply.get("result")}
			await get_tree().process_frame
		_web.forget(data.id)
		return _error("timeout", "Сервер не ответил. Попробуйте ещё раз.")
	var local := api_url.begins_with("http://127.0.0.1:") or api_url.begins_with("http://localhost:")
	if not api_url.begins_with("https://") and not (allow_local_http and local):
		return _error("https_required", "Для входа требуется защищённое HTTPS-соединение.")
	var route := _route(action, data)
	if route.is_empty():
		return _error("invalid_action", "Неизвестное действие.")
	var request := HTTPRequest.new()
	request.timeout = 15.0
	request.body_size_limit = 2 * 1024 * 1024
	add_child(request)
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	if data.has("accessToken"):
		headers.append("Authorization: Bearer " + str(data.accessToken))
	var body: String = JSON.stringify(route.body) if route.has("body") else ""
	var started := request.request(api_url.trim_suffix("/") + route.path, headers, route.method, body)
	if started != OK:
		request.queue_free()
		return _error("network_error", "Не удалось отправить запрос.")
	var response: Array = await request.request_completed
	request.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return _error("network_error", "Нет связи с сервером. Проверьте интернет.")
	var status := int(response[1])
	var text := (response[3] as PackedByteArray).get_string_from_utf8()
	var parsed = null
	if not text.strip_edges().is_empty():
		var parser := JSON.new()
		if parser.parse(text) != OK:
			return _error("invalid_response", "Сервер вернул неверный ответ.", status)
		parsed = parser.data
	if status >= 200 and status < 300:
		return {"ok": true, "data": parsed}
	if parsed is Dictionary and parsed.get("error") is Dictionary:
		return {"ok": false, "error": parsed.error, "status": status}
	return _error("request_failed", "Сервер вернул ошибку %d." % status, status)


func _route(action: String, data: Dictionary) -> Dictionary:
	var base := "/api/games/" + game_id.uri_encode() + "/multiplayer"
	var auth := "/api/games/" + game_id.uri_encode() + "/game-auth"
	var room_path := base + "/rooms/" + str(data.get("code", "")).uri_encode()
	var invite_path := base + "/invitations/" + str(data.get("invitationId", "")).uri_encode()
	var get := HTTPClient.METHOD_GET
	var post := HTTPClient.METHOD_POST
	match action:
		"auth_login", "auth_register": return {"path": auth + "/" + action.trim_prefix("auth_"), "method": post, "body": {"email": data.email, "password": data.password, "displayName": data.get("displayName", "")}}
		"auth_confirm": return {"path": auth + "/confirm", "method": post, "body": {"email": data.email, "code": data.confirmationCode}}
		"auth_resend": return {"path": auth + "/resend", "method": post, "body": {"email": data.email}}
		"auth_refresh": return {"path": auth + "/refresh", "method": post, "body": {"refreshToken": data.refreshToken}}
		"me", "social", "ice": return {"path": base + "/" + action, "method": get}
		"heartbeat", "logout": return {"path": base + "/" + action, "method": post}
		"create": return {"path": base + "/rooms", "method": post, "body": {"capacity": data.capacity, "visibility": data.visibility, "protocolVersion": protocol_version}}
		"join": return {"path": room_path + "/join", "method": post, "body": {"protocolVersion": protocol_version}}
		"get": return {"path": room_path, "method": get}
		"leave": return {"path": room_path, "method": HTTPClient.METHOD_DELETE}
		"receive": return {"path": room_path + "/signals?after=" + str(data.get("after", 0)), "method": get}
		"signal": return {"path": room_path + "/signals", "method": post, "body": {"kind": data.kind, "payload": data.payload, "toPeerId": data.toPeerId}}
		"invite": return {"path": room_path + "/invitations", "method": post, "body": {"userId": data.userId}}
		"accept": return {"path": invite_path + "/accept", "method": post, "body": {"protocolVersion": protocol_version}}
		"decline": return {"path": invite_path, "method": HTTPClient.METHOD_DELETE}
	return {}
