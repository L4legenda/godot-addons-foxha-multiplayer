extends SceneTree
## Real addon signaling and WebRTC, with only the HTTP server replaced by an in-memory broker.
class Broker extends RefCounted:
	var members: Array = []
	var signals: Array = []
	var sequence := 0
	func request(id: int, action: String, fields: Dictionary) -> Dictionary:
		var data: Variant = {}
		match action:
			"ice": data = {"iceServers": [], "relayAvailable": true}
			"create", "join":
				members.append({"userId": str(id), "peerId": id})
				data = {"code": "TEST", "members": members, "capacity": 8}
			"heartbeat": data = {"room": {"code": "TEST", "members": members, "capacity": 8} if members.any(func(m): return m.userId == str(id)) else null}
			"signal":
				sequence += 1
				signals.append({"id": sequence, "fromPeerId": id, "toPeerId": fields.toPeerId, "kind": fields.kind, "payload": fields.payload})
			"receive": data = signals.filter(func(s): return s.toPeerId == id and s.id > fields.after)
			"social": data = {"friends": [], "invitations": []}
		# Exactly the value types returned by HTTP JSON, not shared dictionaries.
		return {"ok": true, "data": JSON.parse_string(JSON.stringify(data))}

class Client extends "res://addons/foxha-game-multiplayer/network_client.gd":
	var broker: Broker
	var test_id := 0
	func _request(action: String, fields: Dictionary = {}) -> Dictionary:
		var result := broker.request(test_id, action, fields)
		await get_tree().create_timer(0.05).timeout
		return result

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var broker := Broker.new()
	var clients: Array = []
	var worlds: Array = []
	for index in range(2):
		var branch := SubViewport.new()
		branch.name = "Signaling%d" % index
		branch.own_world_3d = true
		root.add_child(branch)
		set_multiplayer(SceneMultiplayer.new(), branch.get_path())
		var client := Client.new()
		client.test_id = index + 1
		client.broker = broker
		client.game_id = "test"
		client.user = {"id": str(index + 1)}
		branch.add_child(client)
		clients.append(client)
		var world = load("res://main.tscn").instantiate()
		branch.add_child(world)
		var live_client = root.get_node("FoxhaGameMultiplayer").client
		live_client.transport_ready.disconnect(world._start_network)
		live_client.lobby_changed.disconnect(world._lobby_changed)
		client.transport_ready.connect(world._start_network)
		client.lobby_changed.connect(world._lobby_changed)
		worlds.append(world)
	assert(await clients[0].create_lobby(8, "code"))
	assert(await clients[1].join_lobby("TEST"))
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		if worlds.all(func(w): return w.players.size() == 2):
			break
		await process_frame
	if not worlds.all(func(w): return w.players.size() == 2):
		for client in clients:
			print("id=", client.test_id, " sent=", client._outbox.size(), " receivedThrough=", client._after, " remoteSDP=", client._remote_ready, " error=", client._last_error)
			for id in client._peers:
				print("peer=", id, " state=", client._peers[id].get_connection_state())
		push_error("API signaling did not produce two visible players")
		quit(1)
		return
	worlds[1].players[2].set_physics_process(false)
	worlds[1].players[2].position = Vector3(4, 2, -3)
	await create_timer(0.3).timeout
	assert(worlds[0].players[2].position.is_equal_approx(Vector3(4, 2, -3)))
	for client in clients:
		client.set_process(false)
		client._drop_lobby()
	print("Addon signaling -> 3D world: PASS (JSON, polling, SDP, ICE, spawn, movement)")
	quit()
