extends SceneTree
## Uses disposable accounts supplied by FOXHA_PROBE_USERS (JSON file); never embed credentials.
var arena: Control
var folder: String
var role: String
var client: Node

func _initialize() -> void:
	_run.call_deferred()

func _save(name: String, text: String) -> void:
	var file := FileAccess.open(folder.path_join(name), FileAccess.WRITE)
	file.store_string(text)

func _fail(text: String) -> void:
	push_error(text)
	_save(role + ".result", "FAIL: " + text)
	quit(1)

func _run() -> void:
	folder = OS.get_environment("FOXHA_PROBE_DIR")
	role = OS.get_environment("FOXHA_PROBE_ROLE")
	var accounts = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("FOXHA_PROBE_USERS")))
	var account: Dictionary = accounts[0 if role == "host" else 1]
	client = root.get_node("FoxhaGameMultiplayer").client
	client.ice_transport_policy = "relay"
	arena = load("res://prototype/prototype.tscn").instantiate()
	root.add_child(arena)
	if not await client.authenticate(false, account.email, account.password):
		_fail("Login failed")
		return
	var previous: Dictionary = await client._request("heartbeat")
	if previous.ok and previous.data.get("room") is Dictionary:
		await client._request("leave", {"code": previous.data.room.code})
	if role == "host":
		if not await client.create_lobby(8, "code"):
			_fail("Create failed")
			return
		_save("room.txt", client.lobby.code)
	else:
		var until := Time.get_ticks_msec() + 45000
		while not FileAccess.file_exists(folder.path_join("room.txt")) and Time.get_ticks_msec() < until:
			await process_frame
		if not FileAccess.file_exists(folder.path_join("room.txt")) or not await client.join_lobby(FileAccess.get_file_as_string(folder.path_join("room.txt"))):
			_fail("Join failed")
			return
	var deadline := Time.get_ticks_msec() + 45000
	while arena.positions.size() < 2 and Time.get_ticks_msec() < deadline:
		await process_frame
	if arena.positions.size() < 2:
		_fail("Two-player snapshot not received through TURN")
		return
	if role == "guest":
		arena.set_physics_process(false)
		var peer_id: int = client.multiplayer.get_unique_id()
		var start: Vector2 = arena.positions[peer_id]
		for i in 25:
			arena._move.rpc_id(1, Vector2.RIGHT)
			await create_timer(0.05).timeout
		if (arena.positions[peer_id] as Vector2).distance_to(start) < 100:
			_fail("Authoritative movement was not replicated")
			return
		arena._pulse.rpc_id(1)
		var pulse_until := Time.get_ticks_msec() + 3000
		while not arena.pulses.has(peer_id) and Time.get_ticks_msec() < pulse_until:
			await process_frame
		if not arena.pulses.has(peer_id):
			_fail("Pulse not replicated")
			return
		_save("guest.result", "PASS: relay connection, snapshots, movement, pulse")
		await create_timer(1).timeout
	else:
		while not FileAccess.file_exists(folder.path_join("guest.result")) and Time.get_ticks_msec() < deadline:
			await process_frame
		if not FileAccess.file_exists(folder.path_join("guest.result")) or not FileAccess.get_file_as_string(folder.path_join("guest.result")).begins_with("PASS"):
			_fail("Guest verification failed")
			return
		_save("host.result", "PASS: two players connected through coturn")
		await create_timer(2).timeout
	print(role, ": prototype relay integration PASS")
	await client.leave_lobby()
	await client.logout()
	quit(0)
