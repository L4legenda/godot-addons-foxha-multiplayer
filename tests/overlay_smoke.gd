extends SceneTree
## Run: godot --headless --path . --script res://tests/overlay_smoke.gd

var failures := 0
var checks := 0
var actions: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func _settle() -> void:
	await process_frame
	await process_frame


func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1152, 800)
	var overlay = load("res://addons/foxha-game-multiplayer/player_list.tscn").instantiate()
	root.add_child(overlay)
	await _settle()
	_check(not overlay.visible, "Overlay starts hidden")
	_check(overlay.friends_list.get_child_count() == 3, "Demo friends are present")
	overlay.set_me({"nickname": "Очень длинное имя игрока ".repeat(10)})
	overlay.set_friends([
		{"nickname": "Offline", "status": "offline"},
		{"nickname": "Игрок", "status": "in_game", "game": "Game ".repeat(30)},
		{"nickname": "Legacy"},
	])
	overlay.set_other([{"nickname": "Other", "status": "online"}])
	_check(not overlay.get_node("%Demo").visible, "Live data hides demo label")
	_check(overlay.get_node("%OnlineCount").text == "3 в сети", "Online count includes in-game players")
	_check(overlay.friends_list.get_child(0).get_child(0).get_child(1).get_child(0).text == "Игрок", "In-game players sort first")
	overlay.search.text = "ИГР"
	overlay.search.text_changed.emit(overlay.search.text)
	_check(overlay.friends_list.get_child_count() == 1, "Search is case-insensitive for Cyrillic")
	_check(overlay.other_list.get_child_count() == 0, "Search covers both sections")
	overlay.search.text = "missing"
	overlay.search.text_changed.emit(overlay.search.text)
	_check(overlay.get_node("%Empty").visible, "No results show an empty state")
	overlay.search.clear()
	overlay.search.text_changed.emit("")
	overlay.get_node("%InGame").pressed.emit()
	_check(overlay.friends_list.get_child_count() == 1, "In-game filter works")
	overlay.get_node("%Online").pressed.emit()
	_check(overlay.friends_list.get_child_count() == 2, "Online filter excludes offline players")
	_check(overlay.other_list.get_child_count() == 1, "Online filter retains online players")
	overlay.get_node("%All").pressed.emit()
	_check(overlay.friends_list.get_child_count() == 3, "All filter restores the full list")
	paused = true
	overlay.open()
	await create_timer(0.3).timeout
	_check(overlay.is_open and overlay.visible, "Overlay opens while the game is paused")
	_check(root.gui_get_focus_owner() == overlay.search, "Search receives keyboard focus")
	_check(is_equal_approx(overlay.panel.size.x, 520), "Initial width remains stable with long names")
	var resize_press := InputEventMouseButton.new()
	resize_press.button_index = MOUSE_BUTTON_LEFT
	resize_press.pressed = true
	resize_press.position = overlay.get_node("%ResizeGrip").get_global_rect().get_center()
	overlay._input(resize_press)
	_check(overlay._resizing and not overlay._dragging, "Grip starts resizing instead of dragging")
	var resize_motion := InputEventMouseMotion.new()
	resize_motion.position = resize_press.position + Vector2(140, 20)
	overlay._input(resize_motion)
	_check(is_equal_approx(overlay.panel.size.x, 660), "Dragging grip changes width")
	_check(overlay.panel.size.y > overlay._resize_start_size.y, "Dragging grip changes height")
	resize_press.pressed = false
	overlay._input(resize_press)
	_check(not overlay._resizing, "Mouse release ends resizing")
	overlay.action_requested.connect(func(player: Dictionary, action: String): actions.append([player.nickname, action]))
	var arrow: Button = overlay.friends_list.get_child(0).get_child(0).get_node("Actions")
	arrow.pressed.emit()
	await _settle()
	_check(overlay.get_node("ActionsMenu").visible, "Actions menu opens")
	var menu: PanelContainer = overlay.get_node("ActionsMenu")
	menu.get_child(0).get_node("Invite").pressed.emit()
	_check(actions == [["Игрок", "invite"]], "Invite emits the selected player and action")
	_check(not menu.visible, "Action closes menu")
	arrow.pressed.emit()
	await _settle()
	menu.get_child(0).get_node("Join").pressed.emit()
	_check(actions.back() == ["Игрок", "join"], "Join emits the selected player and action")
	arrow.pressed.emit()
	await _settle()
	overlay.set_friends([{"nickname": "Replacement"}])
	_check(not menu.visible, "Refreshing data safely closes an open menu")
	overlay.close_button.pressed.emit()
	await create_timer(0.3).timeout
	_check(not overlay.visible and paused, "Closing preserves an existing pause")
	paused = false
	overlay.open()
	await _settle()
	_check(is_equal_approx(overlay.panel.size.x, 660), "User size survives close and reopen")
	overlay.close()
	overlay.open()
	await create_timer(0.3).timeout
	_check(overlay.visible and overlay.is_open and paused, "Rapid close/open keeps overlay and pause active")
	overlay.close()
	await create_timer(0.3).timeout
	_check(not overlay.visible and not paused, "Closing restores the original running state")
	overlay.open()
	overlay.close()
	await create_timer(0.3).timeout
	_check(not overlay.visible and not paused, "Closing during initial layout leaves no pending pause")
	var many: Array = []
	for i in 50:
		many.append({"nickname": "Player %02d" % i})
	overlay.set_friends(many)
	overlay.open()
	await create_timer(0.3).timeout
	_check(overlay.friends_list.get_child_count() == 50, "Large lists retain every player")
	_check(overlay.scroll.get_v_scroll_bar().max_value > overlay.scroll.size.y, "Large lists scroll")
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(360, 520)
	await _settle()
	var rect: Rect2 = overlay.panel.get_global_rect()
	_check(rect.position.x >= 0 and rect.end.x <= root.size.x + 1, "Panel fits a narrow viewport")
	_check(rect.position.y >= 0 and rect.end.y <= root.size.y + 1, "Panel fits a short viewport")
	overlay._begin_resize(rect.end)
	overlay._resize_to(Vector2(-1000, -1000))
	_check(overlay.panel.size == overlay.MIN_WINDOW_SIZE, "Resize respects minimum size")
	overlay._resize_to(Vector2(10000, 10000))
	rect = overlay.panel.get_global_rect()
	_check(rect.end.x <= root.size.x and rect.end.y <= root.size.y, "Resize stays inside the viewport")
	overlay.panel.position = Vector2(-1000, 5000)
	overlay._clamp_panel()
	rect = overlay.panel.get_global_rect()
	_check(rect.position.x >= 0 and rect.end.y <= root.size.y + 1, "Dragging is clamped to the viewport")
	overlay.set_friends([])
	overlay.set_other([])
	_check(overlay.get_node("%Empty").visible, "Empty data has an explicit state")
	overlay.close()
	await create_timer(0.3).timeout
	overlay.queue_free()
	await _settle()
	print("Overlay smoke checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
