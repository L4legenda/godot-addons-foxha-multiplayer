extends SceneTree

class FakeClient extends "res://addons/foxha-game-multiplayer/network_client.gd":
	var server_room: Variant = {"code": "AABBCCDDEE", "capacity": 8, "members": [{"userId": "test", "peerId": 1}]}
	var fail_leave := false
	var requested_code := ""
	var signal_reads := 0
	func _request(action: String, fields: Dictionary = {}) -> Dictionary:
		await get_tree().process_frame
		match action:
			"heartbeat": return {"ok": true, "data": {"room": server_room}}
			"social": return {"ok": true, "data": {"friends": [], "invitations": []}}
			"receive":
				signal_reads += 1
				return {"ok": true, "data": []}
			"leave":
				requested_code = fields.code
				if fail_leave:
					return _error("offline", "Нет связи", 0)
				server_room = null
				return {"ok": true}
		return {"ok": true, "data": {}}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var client := FakeClient.new()
	root.add_child(client)
	client.set_process(false)
	client.user = {"id": "test", "displayName": "Test"}
	var overlay = load("res://addons/foxha-game-multiplayer/player_list.tscn").instantiate()
	root.add_child(overlay)
	var panel = load("res://addons/foxha-game-multiplayer/session_panel.gd").new()
	panel.attach(overlay, client)
	assert(not panel._leave.visible)
	await client._poll()
	assert(client.lobby.code == "AABBCCDDEE")
	assert(panel._leave.visible and panel._create.disabled)
	assert(client.rtc == null) # Do not steal the transport from another window.
	await client._poll()
	assert(client.signal_reads == 0)
	client.fail_leave = true
	await client.leave_lobby()
	assert(panel._leave.visible and not client.lobby.is_empty())
	client.fail_leave = false
	await client.leave_lobby()
	assert(client.requested_code == "AABBCCDDEE")
	assert(client.lobby.is_empty() and not panel._leave.visible and not panel._create.disabled)
	await client._poll()
	assert(client.lobby.is_empty())
	client.queue_free()
	overlay.queue_free()
	await process_frame
	print("Lobby recovery: PASS (server membership, visible exit, failed exit retry, successful exit)")
	quit()
