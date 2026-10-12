extends RefCounted

func run(t):
	var previous = [AiActionPacer.preferred_speed, MainMenu.random_mode,
		GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general,
		GameManager.random_general, GameManager.random_identity]
	var old_scene = t.current_scene
	for invalid in [-1, 3, 1.0, "1", null]:
		t.check(not AiActionPacer.set_preference(invalid) and AiActionPacer.preferred_speed == previous[0], "PACE01b invalid preference rejected")
	var adopt = func(node):
		if node is GameManager and node.get_parent() == t.root:
			node.ready.connect(func():
				node.ai_pacer.wait_override = func(_seconds): await t.process_frame
			, CONNECT_ONE_SHOT)
	t.node_added.connect(adopt)
	for speed in range(3):
		t.check(t.change_scene_to_file("res://Scenes/MainMenu.tscn") == OK, "PACE01b real menu loaded")
		await t.process_frame
		await t.process_frame
		var menu = t.current_scene
		menu._show_start()
		for button in menu._page.get_children():
			if button is Button and button.text == "设置": button.pressed.emit()
		await t.process_frame
		var speeds = menu._page.get_children().filter(func(b): return b is Button and b.text.begins_with("AI速度：") and not b.is_queued_for_deletion())
		t.check(speeds.size() == 3, "PACE01b actual settings exposes three speeds")
		speeds[speed].pressed.emit()
		await t.process_frame
		speeds = menu._page.get_children().filter(func(b): return b is Button and b.text.begins_with("AI速度：") and not b.is_queued_for_deletion())
		t.check(speeds.filter(func(b): return b.button_pressed).size() == 1 and speeds[speed].button_pressed, "PACE01b one selected speed")
		MainMenu.random_mode = true
		menu._start_test_game(2, GameManager.MODE_FREE_FOR_ALL)
		await t.process_frame
		await t.process_frame
		var game = t.current_scene
		t.check(game is GameManager and game.players.size() == 2 and game.ai_pacer.speed == speed, "PACE01b actual menu auto-start applies chosen pace")
		AiActionPacer.set_preference((speed + 1) % 3)
		t.check(game.ai_pacer.speed == speed, "PACE01b active game retains opening configuration")
	t.node_added.disconnect(adopt)
	if is_instance_valid(t.current_scene):
		t.current_scene.queue_free()
		t.current_scene = null
	await t.process_frame
	t.current_scene = old_scene if is_instance_valid(old_scene) else null
	var room = load("res://Scenes/LanRoom.tscn").instantiate()
	t.root.add_child(room)
	# Isolate this fixture's ENet authority from the suite multiplayer.
	var api = SceneMultiplayer.new()
	t.set_multiplayer(api, room.get_path())
	var session = room.session
	var error = ERR_CANT_CREATE
	for attempt in 20:
		error = session.host("PACE", 2, 36000 + randi_range(0, 15000))
		if error == OK: break
	t.check(error == OK, "PACE01b host room transport starts")
	var picker = room.body.get_node_or_null("HostPacePicker")
	t.check(picker is OptionButton, "PACE01b host has actual room speed control")
	if picker != null: picker.item_selected.emit(AiActionPacer.Speed.SLOW)
	t.check(session.pace == AiActionPacer.Speed.SLOW and session.lobby.pace == session.pace, "PACE01b host UI publishes authoritative pace")
	for invalid in [-1, 3, "0", null]:
		t.check(not session.set_pace(invalid), "PACE01b room rejects invalid pace")
	var bridge = LanGameBridge.new()
	room.add_child(bridge)
	bridge.start([{"name": "A", "general": "稻草人"}, {"name": "B", "general": "稻草人"}], GameManager.MODE_FREE_FOR_ALL, session.pace)
	t.check(bridge.game.ai_pacer.speed == AiActionPacer.Speed.SLOW and bridge.snapshot(0).pace == AiActionPacer.Speed.SLOW, "PACE01b authority opening and snapshot share pace")
	session.bridge = bridge
	t.check(not session.set_pace(AiActionPacer.Speed.FAST), "PACE01b active authority cannot change pace")
	session.close()
	var client = ENetMultiplayerPeer.new()
	t.check(client.create_client("127.0.0.1", 24567) == OK, "PACE01b client fixture starts")
	api.multiplayer_peer = client
	session.connected = true
	session._receive_lobby({"count": 2, "members": [], "playing": false, "match": "", "pace": AiActionPacer.Speed.FAST})
	t.check(session.pace == AiActionPacer.Speed.FAST and room.pace_label.text.contains("快"), "PACE01b client displays authority config instead of local preference")
	t.check(room.body.get_node_or_null("HostPacePicker") == null and not session.set_pace(AiActionPacer.Speed.SLOW), "PACE01b client cannot configure room pace")
	session._receive_lobby({"playing": false, "pace": 99})
	t.check(session.pace == AiActionPacer.Speed.FAST, "PACE01b malformed lobby cannot overwrite config")
	session.close()
	var room_path = room.get_path()
	room.queue_free()
	await t.process_frame
	t.set_multiplayer(null, room_path)
	AiActionPacer.preferred_speed = previous[0]
	MainMenu.random_mode = previous[1]
	GameManager.selected_players = previous[2]
	GameManager.selected_mode = previous[3]
	GameManager.selected_general = previous[4]
	GameManager.random_general = previous[5]
	GameManager.random_identity = previous[6]
