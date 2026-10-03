extends SceneTree

class FakeClient extends "res://addons/foxha-game-multiplayer/network_client.gd":
	var path := "user://foxha-persistence-smoke.cfg"
	var reply: Dictionary = {}
	var calls: Array[Dictionary] = []
	func _session_path() -> String:
		return path
	func _request(action: String, fields: Dictionary = {}) -> Dictionary:
		calls.append({"action": action, "fields": fields})
		var result := reply.duplicate(true)
		await get_tree().process_frame
		return result

func session(refresh: String) -> Dictionary:
	return {"user": {"id": "test"}, "tokens": {"accessToken": "access-memory-only", "refreshToken": refresh, "refreshExpiresAt": "2099-01-01T00:00:00Z"}}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var client := FakeClient.new()
	root.add_child(client)
	client.set_process(false)
	client.game_id = "test-game"
	client._clear_saved_session()
	client._use_session(session("first"))
	var content := FileAccess.get_file_as_string(client.path)
	assert("first" in content and not "access-memory-only" in content and not "password" in content)
	client._use_session(session("rotated"))
	assert("rotated" in FileAccess.get_file_as_string(client.path))
	client.free()
	client = FakeClient.new()
	root.add_child(client)
	client.set_process(false)
	client.game_id = "test-game"
	client.reply = {"ok": true, "data": session("restored")}
	var overlay = load("res://addons/foxha-game-multiplayer/player_list.tscn").instantiate()
	root.add_child(overlay)
	var panel = load("res://addons/foxha-game-multiplayer/session_panel.gd").new()
	panel.attach(overlay, client)
	client.initialize()
	assert(client.initializing and panel._loading.visible and not panel._auth.get_parent().visible)
	assert(not panel.get_node("LobbyScroll").visible)
	await client.initialize() # Opening UI/repeated initialization must not rotate twice.
	assert(client.calls.size() == 1)
	while client.initializing:
		await process_frame
	assert(not panel._loading.visible and not panel._auth.get_parent().visible)
	assert(panel.get_node("LobbyScroll").visible)
	assert(client.calls[0].action == "auth_refresh" and client.calls[0].fields.refreshToken == "rotated")
	assert(client.user.id == "test" and client._tokens.accessToken == "access-memory-only")
	assert("restored" in FileAccess.get_file_as_string(client.path))
	client.reply = {"ok": false, "status": 0}
	await client._restore_session()
	assert(client._restore_pending and FileAccess.file_exists(client.path))
	client.reply = {"ok": true, "data": session("retried")}
	await client._restore_session()
	assert(not client._restore_pending and "retried" in FileAccess.get_file_as_string(client.path))
	client.reply = {"ok": false, "status": 401}
	await client._restore_session()
	assert(not FileAccess.file_exists(client.path) and not client._restore_pending)
	client._use_session(session("logout-test"))
	client.reply = {"ok": true}
	await client.logout()
	assert(client.user.is_empty() and client._tokens.is_empty() and not FileAccess.file_exists(client.path))
	assert(panel._auth.get_parent().visible and not panel._loading.visible)
	client._use_session(session("race-test"))
	client.reply = {"ok": true, "data": session("must-not-return")}
	client._restore_session()
	await client.logout()
	await process_frame
	assert(client.user.is_empty() and not FileAccess.file_exists(client.path))
	overlay.free()
	client.free()
	var real_client = load("res://addons/foxha-game-multiplayer/network_client.gd").new()
	real_client.game_id = "one"
	var first_path: String = real_client._session_path()
	real_client.game_id = "two"
	assert(first_path != real_client._session_path())
	real_client.game_id = "one"
	real_client.api_url = "https://other.example"
	assert(first_path != real_client._session_path())
	real_client.free()
	print("Session persistence: PASS (restart, rotation, offline retry, expiry, logout, race, isolation)")
	quit()
