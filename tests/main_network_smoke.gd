extends SceneTree
var worlds: Array = []
var apis: Array = []
var connections: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, text: String) -> void:
	if not ok:
		push_error(text)
		quit(1)
		assert(ok, text)

func _run() -> void:
	var use_webrtc := "--webrtc" in OS.get_cmdline_user_args()
	var server := ENetMultiplayerPeer.new()
	var port := 19879
	while not use_webrtc and server.create_server(port, 8) != OK:
		port += 1
		_check(port < 19900, "Test port available")
	for index in range(3):
		var branch := SubViewport.new()
		branch.own_world_3d = true
		branch.name = "Instance%d" % index
		root.add_child(branch)
		var api := SceneMultiplayer.new()
		set_multiplayer(api, branch.get_path())
		apis.append(api)
		var world = load("res://main.tscn").instantiate()
		branch.add_child(world)
		# Test transports are independent of any saved account in the autoload.
		var live_client = root.get_node("FoxhaGameMultiplayer").client
		live_client.transport_ready.disconnect(world._start_network)
		live_client.lobby_changed.disconnect(world._lobby_changed)
		worlds.append(world)
		var peer: MultiplayerPeer
		if use_webrtc:
			var rtc := WebRTCMultiplayerPeer.new()
			_check((rtc.create_server() if index == 0 else rtc.create_client(index + 1)) == OK, "Create WebRTC peer")
			peer = rtc
		else:
			peer = server if index == 0 else ENetMultiplayerPeer.new()
			if index != 0:
				_check(peer.create_client("127.0.0.1", port) == OK, "Create guest")
		api.multiplayer_peer = peer
		world._start_network(peer)
	if use_webrtc:
		for index in [1, 2]:
			var host_link := WebRTCPeerConnection.new()
			var guest_link := WebRTCPeerConnection.new()
			_check(host_link.initialize({}) == OK and guest_link.initialize({}) == OK, "Initialize WebRTC")
			connections.append_array([host_link, guest_link])
			host_link.session_description_created.connect(_description.bind(host_link, guest_link))
			guest_link.session_description_created.connect(_description.bind(guest_link, host_link))
			host_link.ice_candidate_created.connect(guest_link.add_ice_candidate)
			guest_link.ice_candidate_created.connect(host_link.add_ice_candidate)
			_check(apis[0].multiplayer_peer.add_peer(host_link, index + 1) == OK, "Add guest to host")
			_check(apis[index].multiplayer_peer.add_peer(guest_link, 1) == OK, "Add host to guest")
			host_link.create_offer()
	var deadline := Time.get_ticks_msec() + 7000
	while Time.get_ticks_msec() < deadline:
		if worlds.all(func(w): return w.players.size() == 3):
			break
		await process_frame
	for world in worlds:
		_check(world.players.size() == 3, "All three instances spawn all players")
		for id in world.players:
			_check(world.players[id].locally_controlled == (id == world._local_id), "Only own player accepts input")
			_check(world.players[id].get_node("CamPivot/Camera3D").current == (id == world._local_id), "Only own camera is current")
	var moving_id: int = worlds[1]._local_id
	worlds[1].players[moving_id].set_physics_process(false)
	worlds[1].players[moving_id].position = Vector3(12, 2, -5)
	worlds[1].players[moving_id].rotation.y = 0.75
	await create_timer(0.3).timeout
	for world in worlds:
		_check(world.players[moving_id].position.is_equal_approx(Vector3(12, 2, -5)), "Guest motion relays through host")
		_check(is_equal_approx(world.players[moving_id].rotation.y, 0.75), "Rotation synchronized")
	apis[1].multiplayer_peer.close()
	await create_timer(0.4).timeout
	_check(not worlds[0].players.has(moving_id) and not worlds[2].players.has(moving_id), "Disconnected player removed everywhere")
	worlds[2]._lobby_changed({})
	_check(worlds[2].players.size() == 1 and not worlds[2]._active, "Leaving restores offline player")
	for api in apis:
		api.multiplayer_peer.close()
	print("3D multiplayer: PASS (3 peers, cameras, movement, rotation, disconnect, leave)")
	quit()

func _description(kind: String, sdp: String, source: WebRTCPeerConnection, target: WebRTCPeerConnection) -> void:
	_check(source.set_local_description(kind, sdp) == OK, "Local SDP")
	_check(target.set_remote_description(kind, sdp) == OK, "Remote SDP")
