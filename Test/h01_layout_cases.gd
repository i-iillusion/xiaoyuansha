extends RefCounted

var answer: Variant
func capture(callback: Callable):
	answer = await callback.call()

func frames(t, count := 3):
	for i in count: await t.process_frame

func click(panel: Control):
	var event = InputEventMouseButton.new()
	event.pressed = true
	event.button_index = MOUSE_BUTTON_LEFT
	panel.gui_input.emit(event)

func geometry(t):
	for invalid in [0, 1, 11, -1, 2.0, "5", null]:
		t.check(not SeatLayout.valid_count(invalid), "H01a invalid count rejected")
	for count in range(2, 11):
		for viewer in [0, count - 1]:
			var rectangles = SeatLayout.rectangles(count, Vector2(1280, 580), viewer)
			t.check(rectangles.size() == count - 1 and not rectangles.has(viewer), "H01a observer-relative presentation without renumbering")
			var seats = SeatLayout.view_order(count, viewer)
			t.check(seats[0] == (viewer + 1) % count and seats.back() == (viewer + count - 1) % count, "H01a visual order retains fixed IDs")
			for seat in rectangles:
				var rectangle: Rect2 = rectangles[seat]
				t.check(Rect2(Vector2.ZERO, Vector2(1280, 580)).encloses(rectangle), "H01a panel stays inside logical board")
				t.check(rectangles.keys().all(func(other): return other == seat or not rectangle.intersects(rectangles[other])), "H01a panel bounds do not overlap")
	t.check(SeatLayout.rectangles(11, Vector2(1280, 580)).is_empty(), "H01a invalid layout has no partial seats")
	t.check(SeatLayout.rectangles(10, Vector2(1100, 580)).is_empty(), "H01a insufficient logical extent never creates overlapping seats")
	t.check(SeatLayout.columns(10, 604) == 2 and SeatLayout.columns(10, 1244) == 5, "H01a network gallery responds to width")

func fixture(t, count) -> GameManager:
	GameManager.selected_players = count
	GameManager.selected_mode = GameManager.MODE_FREE_FOR_ALL
	GameManager.selected_general = "稻草人"
	GameManager.random_general = false
	GameManager.random_identity = false
	var game = load("res://Scenes/Game.tscn").instantiate()
	game.auto_start = false
	t.root.add_child(game)
	game.start_game()
	game._halt_countdown()
	game._dodge_override = func(): return false
	game._sacrifice_override = func(): return false
	return game

func local_board(t, count):
	var game = fixture(t, count)
	await frames(t)
	t.check(game.players.size() == count and game._player_positions.size() == count - 1, "H01b actual dynamic opening %d" % count)
	t.check(game.players.all(func(p): return p.identity == "" and p.hand_size() >= 4), "H01b FFA identities and initial cards unchanged")
	var original = game.players.duplicate()
	for i in count - 1:
		var panel = game._other_player_panels[i]
		t.check(panel.get_meta("player") == game.players[i + 1] and panel.get_parent().get_meta("seat") == i + 1, "H01b panel hit target has original player")
		t.check(panel.get_parent().mouse_filter == Control.MOUSE_FILTER_IGNORE and panel.get_meta("avatar_label").text != "", "H01b avatar and transparent layout slot")
	var target = game.players.back()
	var panel = game._other_player_panels.back()
	var full: float = panel.get_meta("hp_bar").size.x
	target.hp -= 1
	game._draw_blank_cards(target, 1)
	game._sync_all_ui()
	t.check(panel.get_meta("hp_bar").size.x < full and panel.get_meta("hp_label").text.contains("4/5"), "H01b last opponent HP refreshes beyond old four-seat limit")
	t.check(panel.get_meta("hand_label").text.contains(str(target.hand_size())), "H01b last opponent hand count refreshes")
	target.hp = -2
	game._sync_all_ui()
	t.check(panel.get_meta("hp_bar").size.x == 0 and panel.get_meta("hp_label").text.contains("-2"), "H01b negative HP text retained, bar stays bounded")
	target.hp = target.max_hp + 1
	game._sync_all_ui()
	t.check(panel.get_meta("hp_bar").size.x == 120 and target.hp == 6, "H01b exceptional HP is not changed by visual clamp")
	target.hp = target.max_hp
	click(panel)
	await frames(t)
	t.check(game._detail_popup_root.visible and game._detail_popup_root.get_child_count() > 0, "H01b actual last-seat detail opens")
	game._detail_popup_root.visible = false
	for child in game._detail_popup_root.get_children(): child.queue_free()
	await frames(t)
	var before = game.players[0].hand_size()
	game._target_confirm_override = func(): return false
	game._enter_targeting_mode(CardData.CardSubType.STRIKE)
	click(panel)
	await frames(t)
	t.check(game.players[0].hand_size() == before and target.hp == 5, "H01b cancelled target does not pay")
	game._target_confirm_override = func(): return true
	for concrete in [false, true]:
		game.turn_manager.strike_count_this_turn = 0
		var card = CardBase.create(CardData.CardSubType.STRIKE) if concrete else null
		if concrete:
			game.players[0].determined_cards.append(card)
			game._pending_determined_card = card
		var health = target.hp
		var cards = game.players[0].hand_size()
		game._enter_targeting_mode(CardData.CardSubType.STRIKE)
		click(panel)
		await frames(t, 6)
		t.check(target.hp == health - 1 and game.players[0].hand_size() == cards - 1, "H01b real last-seat click pays once and damages once")
		if concrete: t.check(game.deck._discard.count(card) == 1, "H01b determined original enters discard once")
	game._on_play_btn_pressed()
	await frames(t)
	t.check(game.get_node("UI").get_children().any(func(node): return node is CardSelector), "H01b real card selection remains reachable")
	for node in game.get_node("UI").get_children():
		if node is CardSelector: node.queue_free()
	game._history_panel.toggle.pressed.emit()
	await frames(t)
	var history_rect = game._history_panel.get_global_rect()
	t.check(game._other_player_panels.all(func(other): return not history_rect.intersects(other.get_global_rect())), "H01b expanded history does not cover player hit areas")
	var old_extent: Vector2 = game._seat_board.size
	game._seat_board.size = Vector2(1440, 760)
	t.check(game._player_positions.all(func(slot): return Rect2(Vector2.ZERO, Vector2(1440, 760)).encloses(slot.get_rect())), "H01b actual resize signal places all slots in new extent")
	game._seat_board.size = old_extent
	t.check(game.players == original and game.players.all(func(p): return p.seat_index == game.players.find(p)), "H01b resize/layout does not reorder fixed IDs")
	target.life_state = Player.LifeState.DEAD
	game._sync_all_ui()
	t.check(panel.modulate != Color.WHITE and panel.get_meta("player") == target and game._player_positions.size() == count - 1, "H01b final-dead presentation retains its fixed seat and panel")
	target.life_state = Player.LifeState.ACTIVE
	var count_before = game.players.size()
	game.start_game()
	t.check(game.players.size() == count_before, "H01b duplicate start cannot append another roster")
	game._game_over = true
	game.queue_free()
	await frames(t)

func network_board(t, count):
	var roster: Array[Dictionary] = []
	for seat in count: roster.append({"name": "P%d" % seat, "general": "稻草人"})
	var bridge = LanGameBridge.new()
	t.root.add_child(bridge)
	bridge.start(roster, GameManager.MODE_FREE_FOR_ALL)
	bridge.game._halt_countdown()
	var viewport = SubViewport.new()
	viewport.size = Vector2i(640, 720)
	t.root.add_child(viewport)
	var room = load("res://Scenes/LanRoom.tscn").instantiate()
	viewport.add_child(room)
	for seat in [0, count - 1]:
		var state = bridge.snapshot(seat)
		room._state_changed(state)
		await frames(t)
		t.check(room._board.get_child_count() == count and room._board.columns == 2, "H01c narrow LAN gallery includes all fixed seats")
		t.check(room._board.size.x <= 640 - 36 and room._board.get_children().all(func(b): return b.has_meta("seat")), "H01c responsive LAN board fits width and preserves target IDs")
		t.check(state.own_cards.size() == bridge.game.players[seat].hand_size() and state.players.all(func(p): return p.identity == ""), "H01c per-observer cards and FFA identity privacy")
	viewport.size = Vector2i(1280, 720)
	await frames(t)
	t.check(room._board.columns == mini(count, 5), "H01c viewport resize relayouts unchanged snapshot")
	var state = bridge.snapshot(0)
	var target = bridge.game.players.back()
	t.check(bridge.submit(0, state.targets[str(target.seat_index)]), "H01c authority accepts last-seat detail token")
	await frames(t)
	t.check(not bridge.snapshot(0).labels.is_empty() and bridge.snapshot(count - 1).labels.is_empty(), "H01c detail text only reaches controlling observer")
	bridge.game._detail_popup_root.visible = false
	for child in bridge.game._detail_popup_root.get_children(): child.queue_free()
	answer = null
	capture(bridge.game._rps_choice.bind(target, "H01 response"))
	await frames(t)
	state = bridge.snapshot(count - 1)
	t.check(bridge.input_owner() == count - 1 and not state.controls.is_empty() and bridge.snapshot(0).controls.is_empty(), "H01c real response belongs to last remote seat")
	t.check(not bridge.submit(0, state.controls[0].id) and bridge.submit(count - 1, state.controls[0].id), "H01c host cannot steal last-seat choice")
	await frames(t)
	t.check(answer != null, "H01c actual last-seat response resolves")
	viewport.queue_free()
	bridge.abort()
	await frames(t)

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	geometry(t)
	for count in range(2, 11):
		await local_board(t, count)
		await network_board(t, count)
	for invalid in [1, 11]:
		var game = fixture(t, invalid)
		t.check(game.players.is_empty() and game._other_player_panels.is_empty(), "H01a rejected opening has no partial roster")
		game.queue_free()
		await frames(t)
	for count in [8, 10]:
		GameManager.selected_players = count
		GameManager.random_general = true
		var game = load("res://Scenes/Game.tscn").instantiate()
		game.auto_start = false
		t.root.add_child(game)
		game.start_game()
		game._halt_countdown()
		t.check(game.players.size() == count and game._other_player_panels.size() == count - 1, "H01a actual random opening fits expanded roster")
		var names = game.players.map(func(p): return p.general_name)
		t.check(names.all(func(name): return names.count(name) == 1 and name != "稻草人"), "H01a expanded random opening remains unique")
		t.check(game.players.all(func(p): return p.max_hp == GeneralData.get_max_hp(p.general_name, count)), "H01a initial HP uses existing general metadata and player count")
		if count == 10:
			t.check(game.players.filter(func(p): return GeneralData.get_implementation_status(p.general_name) == "metadata_only").size() == maxi(0,count-GeneralData.get_available_random_generals().size()), "H01a actual expanded roster supplements exactly the remaining pool gap")
		game._game_over = true
		game.queue_free()
		await frames(t)
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]
