extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1152, 800)
	# Isolate the form test from the player's saved account and live API.
	var client = load("res://addons/foxha-game-multiplayer/network_client.gd").new()
	root.add_child(client)
	client.set_process(false)
	var overlay = load("res://addons/foxha-game-multiplayer/player_list.tscn").instantiate()
	root.add_child(overlay)
	overlay.pause_game = false
	var panel = load("res://addons/foxha-game-multiplayer/session_panel.gd").new()
	panel.attach(overlay, client)
	overlay.open()
	await create_timer(0.3).timeout
	assert(is_equal_approx(overlay.panel.size.x, 520))
	assert(panel._auth.is_visible_in_tree())
	assert(panel._password.secret)
	assert(not overlay.pause_game)
	client.initializing = true
	client.initialization_changed.emit()
	await process_frame
	await process_frame
	assert(panel._loading.size.x > 400 and panel._loading.get_line_count() == 1)
	client.initializing = false
	client.initialization_changed.emit()
	panel._change_mode()
	await process_frame
	assert(panel._name.visible and panel._register)
	assert(is_equal_approx(overlay.panel.size.x, 520))
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://foxha-register-preview.png")
	panel._change_mode()
	assert(not panel._register)
	panel.client.confirmation_required.emit()
	assert(panel._code.visible and not panel._password.visible)
	panel._change_mode()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://foxha-login-preview.png")
	overlay.close()
	await create_timer(0.3).timeout
	overlay.free()
	client.free()
	print("Session UI: PASS")
	quit()
