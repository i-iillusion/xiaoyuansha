# DEV-UI02: real status panels, detail windows and five-seat LAN frontend.
extends SceneTree

var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1
	print(("PASS " if value else "FAIL ") + message)

func _initialize() -> void:
	_run.call_deferred()

func frames() -> void:
	await process_frame
	await process_frame

func detail(game: GameManager, player: Player) -> PlayerDetailPopup:
	game._open_player_detail(player)
	return game._detail_popup_root.get_child(game._detail_popup_root.get_child_count() - 1)

func _run() -> void:
	var old_count = GameManager.selected_players
	var old_mode = GameManager.selected_mode
	GameManager.selected_players = 5
	GameManager.selected_mode = GameManager.MODE_CLASSIC_IDENTITY
	var game = load("res://Scenes/Game.tscn").instantiate()
	game.auto_start = false
	root.add_child(game)
	game.start_game()
	game._halt_countdown()
	await frames()
	var roles := ["主公", "忠臣", "反贼", "反贼", "内奸"]
	for offset in [0, 1, 2, 4]:
		for seat in 5:
			game.players[seat].identity = roles[(seat + offset) % 5]
			game.players[seat].identity_revealed = game.players[seat].identity == "主公"
		game._sync_all_ui()
		var me: Player = game.players[0]
		check(game._self_info_panel.get_meta("identity_label").text == "【%s】" % me.identity, "own status shows " + me.identity)
		check(detail(game, me)._identity_label.text == "身份：" + me.identity, "own detail shows " + me.identity)
		await frames()
		for seat in range(1, 5):
			var other: Player = game.players[seat]
			var label: Label = game._other_player_panels[seat - 1].get_meta("identity_label")
			check(label.text == ("【%s】" % other.identity if other.identity_revealed else "【?】"), "other status visibility %d/%d" % [offset, seat])
			if not other.identity_revealed:
				check(label.get_theme_color("font_color") == Color(0.6, 0.6, 0.65), "hidden status color does not reveal role")
			check(detail(game, other)._identity_label.text == ("身份：" + other.identity if other.identity_revealed else "身份：？"), "other detail visibility %d/%d" % [offset, seat])
			await frames()
		check(me.identity_revealed == (me.identity == "主公"), "viewing own identity never publicly reveals it")
	var target: Player = game.players[1]
	target.identity = "反贼"
	target.identity_revealed = true
	game._sync_all_ui()
	check(game._other_player_panels[0].get_meta("identity_label").text == "【反贼】", "public identity is shown on refresh")
	check(detail(game, target)._identity_label.text == "身份：反贼", "public identity is shown in detail")
	game.players[0].identity = ""
	game._sync_all_ui()
	check(game._self_info_panel.get_meta("identity_label").text == "", "no identity is invented for a blank role")
	check(detail(game, game.players[0])._identity_label.text == "身份：无", "blank-role detail stays identity-free")
	game._game_over = true
	game.queue_free()
	await frames()
	var roster: Array[Dictionary] = []
	for seat in 5: roster.append({"name": "P%d" % seat, "general": "稻草人"})
	var bridge := LanGameBridge.new()
	root.add_child(bridge)
	bridge.start(roster, GameManager.MODE_CLASSIC_IDENTITY)
	bridge.game._halt_countdown()
	var room = load("res://Scenes/LanRoom.tscn").instantiate()
	root.add_child(room)
	for seat in 5:
		var snapshot = bridge.snapshot(seat)
		room._state_changed(snapshot)
		check(room.body.get_child(0).text.ends_with("身份：" + bridge.game.players[seat].identity), "LAN header shows recipient's own role %d" % seat)
		for row in snapshot.players:
			check(row.identity == (bridge.game.players[row.seat].identity if row.seat == seat or bridge.game.players[row.seat].identity_revealed else ""), "LAN role privacy %d/%d" % [seat, row.seat])
		bridge.game._set_input_player(bridge.game.players[seat])
		check(detail(bridge.game, bridge.game.players[seat])._identity_label.text == "身份：" + bridge.game.players[seat].identity, "remote self-detail %d" % seat)
		await frames()
		check(("身份：" + bridge.game.players[seat].identity) in bridge.snapshot(seat).labels, "remote own detail reaches only recipient %d" % seat)
		check(bridge.snapshot((seat + 1) % 5).labels.is_empty(), "remote detail labels are private %d" % seat)
	room.queue_free()
	bridge.abort()
	await frames()
	GameManager.selected_players = old_count
	GameManager.selected_mode = old_mode
	print("RESULT: %d asserts, %d failures" % [checks, failures])
	quit(1 if failures else 0)
