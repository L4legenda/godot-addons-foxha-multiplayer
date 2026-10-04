extends Node3D
## 3D sample: each peer moves its own character; the host relays snapshots to guests.
## Prototype movement is client-authoritative, not an anti-cheat implementation.
const PlayerScene := preload("res://player.tscn")
var players: Dictionary = {}
var _active := false
var _connected := false
var _send_time := 0.0
var _local_id := 1
var _network_status: Label


func _ready() -> void:
	_network_status = Label.new()
	_network_status.position = Vector2(18, 155)
	_network_status.add_theme_color_override("font_color", Color("ffac73"))
	_network_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_network_status.add_theme_constant_override("outline_size", 6)
	$Hud.add_child(_network_status)
	FoxhaGameMultiplayer.client.transport_ready.connect(_start_network)
	FoxhaGameMultiplayer.client.lobby_changed.connect(_lobby_changed)
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(_connected_to_server)
	multiplayer.server_disconnected.connect(_offline)
	multiplayer.connection_failed.connect(_offline)
	if FoxhaGameMultiplayer.client.rtc != null:
		_start_network(FoxhaGameMultiplayer.client.rtc)
	else:
		_offline()


func _reset_players(local_id: int) -> void:
	# Keep the actual local character, including transform, velocity and camera state.
	var local_actor: Node = players.get(_local_id)
	for actor in players.values():
		if actor == local_actor:
			continue
		actor.get_parent().remove_child(actor)
		actor.queue_free()
	players.clear()
	_local_id = local_id
	if is_instance_valid(local_actor):
		local_actor.name = "Player_%d" % _local_id
		players[_local_id] = local_actor
	else:
		_spawn(_local_id)


func _spawn(id: int) -> void:
	if players.has(id):
		return
	var actor := PlayerScene.instantiate()
	actor.name = "Player_%d" % id
	actor.locally_controlled = id == _local_id
	actor.position = Vector3((id - 1) % 4 * 2.5, 0.1, -floorf((id - 1) / 4.0) * 3)
	# Players do not push each other differently on separate machines.
	actor.collision_layer = 2
	actor.collision_mask = 1
	$Players.add_child(actor)
	players[id] = actor


func _offline() -> void:
	_active = false
	_connected = false
	_reset_players(1)


func _start_network(_peer: MultiplayerPeer) -> void:
	_active = true
	_connected = multiplayer.is_server()
	_reset_players(multiplayer.get_unique_id())
	if _connected:
		for id in multiplayer.get_peers():
			_spawn(id)


func _lobby_changed(room: Dictionary) -> void:
	if room.is_empty() and _active:
		_offline()


func _peer_connected(id: int) -> void:
	if _active and multiplayer.is_server():
		_spawn(id)


func _peer_disconnected(id: int) -> void:
	if players.has(id):
		var actor: Node = players[id]
		actor.get_parent().remove_child(actor)
		actor.queue_free()
		players.erase(id)


func _connected_to_server() -> void:
	if _active:
		_connected = true


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _submit_pose(location: Vector3, yaw: float) -> void:
	if not _active or not multiplayer.is_server() or not location.is_finite() or not is_finite(yaw):
		return
	var sender := multiplayer.get_remote_sender_id()
	if not players.has(sender):
		return
	players[sender].position = location
	players[sender].rotation.y = yaw


@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_world(state: Dictionary) -> void:
	if not _active or multiplayer.is_server():
		return
	for id in players.keys():
		if id != _local_id and not state.has(id):
			_peer_disconnected(id)
	for id: int in state:
		_spawn(id)
		if id != _local_id:
			players[id].position = state[id][0]
			players[id].rotation.y = state[id][1]


func _physics_process(delta: float) -> void:
	if not _active or not _connected:
		return
	if multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		_offline()
		return
	_send_time += delta
	if _send_time < 0.05:
		return
	_send_time = 0
	if multiplayer.is_server():
		var state: Dictionary = {}
		for id in players:
			state[id] = [players[id].position, players[id].rotation.y]
		for id in multiplayer.get_peers():
			if _can_send(id):
				_receive_world.rpc_id(id, state)
	elif _can_send(1):
		var actor: Node3D = players[_local_id]
		_submit_pose.rpc_id(1, actor.position, actor.rotation.y)


func _can_send(id: int) -> bool:
	var peer := multiplayer.multiplayer_peer
	if peer is WebRTCMultiplayerPeer:
		if not peer.has_peer(id):
			return false
		var connection: Dictionary = peer.get_peer(id)
		for channel: WebRTCDataChannel in connection.get("channels", []):
			if channel.get_ready_state() != WebRTCDataChannel.STATE_OPEN:
				return false
		return connection.get("connected", false)
	return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _process(_delta: float) -> void:
	var room: Dictionary = FoxhaGameMultiplayer.client.lobby
	if room.is_empty():
		_network_status.text = "Одиночный режим · Shift+Tab — подключиться"
	elif not _active:
		_network_status.text = "Вы в лобби, но игровое соединение закрыто. Выйдите из лобби и подключитесь заново."
	elif not _connected:
		var detail: String = FoxhaGameMultiplayer.client.connection_status
		_network_status.text = detail if not detail.is_empty() else "Лобби: %d игроков · устанавливаем игровое соединение…" % room.get("members", []).size()
	else:
		_network_status.text = "В мире: %d · в лобби: %d" % [players.size(), room.get("members", []).size()]
		if not FoxhaGameMultiplayer.client.connection_status.is_empty():
			_network_status.text += " · " + FoxhaGameMultiplayer.client.connection_status
