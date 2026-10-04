extends SceneTree

class FakeClient extends "res://addons/foxha-game-multiplayer/network_client.gd":
	var accepted := ""
	var declined := ""
	var fail_accept := false
	func accept_invitation(id: String) -> bool:
		accepted = id
		if fail_accept:
			message.emit("Приглашение истекло")
			return false
		return true
	func decline_invitation(id: String) -> void:
		declined = id
	func leave_lobby() -> void:
		lobby = {}
		lobby_changed.emit(lobby)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var client := FakeClient.new()
	root.add_child(client)
	client.set_process(false)
	client.user = {"id": "me"}
	var notifications = load("res://addons/foxha-game-multiplayer/invitation_notifications.gd").new()
	notifications.client = client
	root.add_child(notifications)
	var social := {"friends": [{"id": "friend", "displayName": "Foxha"}],
		"invitations": [{"id": "one", "roomCode": "ABC123", "fromUserId": "friend"}]}
	client.social_changed.emit(social)
	await process_frame
	for frame in 5:
		await process_frame
	assert(notifications._card.size.y < 300, "Invitation must fit its content")
	notifications._card.size.y = 900
	client.social_changed.emit(social)
	for frame in 5:
		await process_frame
	assert(notifications._card.size.y < 300, "Invitation must shrink after relayout")
	assert(notifications._card.visible)
	assert(notifications._details.text.contains("Foxha"))
	assert(notifications._sound.stream.data.size() > 0)
	assert(notifications._seen.size() == 1)
	client.user_changed.emit(client.user)
	client.social_changed.emit(social)
	assert(notifications._seen.size() == 1)
	assert(notifications._invitations.size() == 1)
	client.fail_accept = true
	await notifications._respond(true)
	assert(notifications._card.visible and not notifications._accept.disabled)
	assert(notifications._status.text == "Приглашение истекло")
	client.fail_accept = false
	client.lobby = {"code": "OLD"}
	client.lobby_changed.emit(client.lobby)
	assert(notifications._accept.text.begins_with("Выйти"))
	await notifications._respond(true)
	assert(client.accepted == "one" and client.lobby.is_empty())
	assert(not notifications._card.visible)
	client.social_changed.emit(social)
	await notifications._respond(false)
	assert(client.declined == "one")
	client.social_changed.emit({"invitations": []})
	assert(not notifications._card.visible)
	client.social_changed.emit(social)
	client.user_changed.emit({})
	assert(not notifications._card.visible and notifications._seen.is_empty())
	notifications.free()
	client.free()
	print("Invitation notifications: PASS")
	quit()
