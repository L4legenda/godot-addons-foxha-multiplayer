extends Node3D
## 3D sample: each peer moves its own character; the host relays snapshots to guests.
## Prototype movement is client-authoritative, not an anti-cheat implementation.
const PlayerScene := preload("res://player.tscn")
var players: Dictionary = {}
var _active := false
var _connected := false
var _send_time := 0.0
var _local_id := 1


func _ready() -> void:
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


func _clear_players() -> void:
	for actor in players.values():
		actor.get_parent().remove_child(actor)
		actor.queue_free()
	players.clear()


func _spawn(id: int) -> void:
	if players.has(id):
		return
	var actor := PlayerScene.instantiate()
	actor.name = "Player_%d" % id
	actor.locally_controlled = id == _local_id
	actor.position = Vector3((id - 1) % 4 * 2.5, 0.1, -float((id - 1) / 4 as int) * 3)
	# Players do not push each other differently on separate machines.
	actor.collision_layer = 2
	actor.collision_mask = 1
	$Players.add_child(actor)
	players[id] = actor


func _offline() -> void:
	_active = false
	_connected = false
	_local_id = 1
	_clear_players()
	_spawn(1)


func _start_network(_peer: MultiplayerPeer) -> void:
	_active = true
	_connected = multiplayer.is_server()
	_local_id = multiplayer.get_unique_id()
	_clear_players()
	_spawn(_local_id)
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
