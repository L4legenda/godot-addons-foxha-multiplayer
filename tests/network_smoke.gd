extends SceneTree
## FOXHA_TEST_GAME=<uuid> godot --headless --path . --script res://tests/network_smoke.gd
const Client := preload("res://addons/foxha-game-multiplayer/network_client.gd")
var received: Dictionary = {}
var relayed := false
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, text: String) -> void:
	if not value:
		failures += 1
		push_error(text)


func _actor(node_name: String) -> Client:
	var client := Client.new()
	client.name = node_name
	client.game_id = OS.get_environment("FOXHA_TEST_GAME")
	client.api_url = "http://127.0.0.1:5099"
	client.allow_local_http = true
	set_multiplayer(MultiplayerAPI.create_default_interface(), NodePath("/root/" + node_name))
	root.add_child(client)
	client.message.connect(func(text: String): print(node_name, ": ", text))
	return client


func _run() -> void:
	var actors: Array[Client] = []
	for i in 8:
		var actor := _actor("NetworkPlayer%d" % i)
		actors.append(actor)
		_check(await actor.authenticate(true, "player-%d-%d@example.com" % [i, Time.get_ticks_usec()], "NetworkTest-2026!", "Player %d" % i), "Player registration")
	if failures:
		quit(1)
		return
	var host := actors[0]
	_check(await host.create_lobby(8, "code"), "Host creates room")
	if host.lobby.is_empty():
		quit(1)
		return
	for i in range(1, actors.size()):
		_check(await actors[i].join_lobby(host.lobby.code), "Guest joins room")
	var deadline := Time.get_ticks_msec() + 25000
	while Time.get_ticks_msec() < deadline:
		if host.multiplayer.get_peers().size() == 7:
			break
		await process_frame
	_check(host.multiplayer.get_peers().size() == 7, "Host has seven WebRTC peers")
	for i in range(1, actors.size()):
		_check(actors[i].multiplayer.get_peers().has(1), "Guest is connected to host")
	if failures == 0:
		for i in range(1, actors.size()):
			var actor := actors[i]
			actor.multiplayer.peer_packet.connect(func(_id: int, bytes: PackedByteArray):
				if bytes.get_string_from_utf8() == "foxha-p2p":
					received[actor.name] = true
				elif bytes.get_string_from_utf8() == "foxha-relay":
					relayed = true
			)
			host.multiplayer.send_bytes("foxha-p2p".to_utf8_buffer(), actor._my_peer_id())
		deadline = Time.get_ticks_msec() + 5000
		while received.size() < 7 and Time.get_ticks_msec() < deadline:
			await process_frame
		_check(received.size() == 7, "All seven guests received a gameplay packet")
		actors[1].multiplayer.send_bytes("foxha-relay".to_utf8_buffer(), actors[2]._my_peer_id())
		deadline = Time.get_ticks_msec() + 3000
		while not relayed and Time.get_ticks_msec() < deadline:
			await process_frame
		_check(relayed, "Guest-to-guest gameplay is relayed by host")
	for actor in actors:
		await actor.leave_lobby()
		await actor.logout()
		actor.queue_free()
	await process_frame
	print("Eight-player network integration: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
