extends SceneTree

class DelayedClient extends "res://addons/foxha-game-multiplayer/network_client.gd":
	signal release_heartbeat
	func _request(action: String, _fields: Dictionary = {}) -> Dictionary:
		if action == "heartbeat":
			await release_heartbeat
			return {"ok": true, "data": {"room": null}}
		return {"ok": true, "data": {}}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var branch := Node.new()
	branch.name = "RaceTest"
	root.add_child(branch)
	set_multiplayer(SceneMultiplayer.new(), branch.get_path())
	var client := DelayedClient.new()
	branch.add_child(client)
	client.set_process(false)
	client.user = {"id": "host"}
	client._poll() # Response was captured before the room existed.
	var room := {"code": "TEST", "members": [{"userId": "host", "peerId": 1}]}
	assert(await client._enter_lobby({"ok": true, "data": room}))
	client.release_heartbeat.emit()
	await process_frame
	if client.rtc == null or client.lobby.is_empty():
		push_error("Stale heartbeat destroyed the newly created game transport")
		quit(1)
		return
	client._drop_lobby()
	branch.queue_free()
	print("Lobby entry race: PASS (stale heartbeat cannot close new transport)")
	quit()
