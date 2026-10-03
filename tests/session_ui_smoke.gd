extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1152, 800)
	var addon = root.get_node("FoxhaGameMultiplayer")
	var overlay = addon.player_list
	var panel = overlay.get_node("Panel/Margin/Content/SessionPanel")
	addon.open_list()
	await create_timer(0.3).timeout
	assert(is_equal_approx(overlay.panel.size.x, 260))
	assert(panel._auth.is_visible_in_tree())
	assert(panel._password.secret)
	assert(not overlay.pause_game)
	panel._change_mode()
	await process_frame
	assert(panel._name.visible and panel._register)
	assert(is_equal_approx(overlay.panel.size.x, 260))
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
	addon.close_list()
	await create_timer(0.3).timeout
	print("Session UI: PASS")
	quit()
