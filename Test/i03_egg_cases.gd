extends RefCounted

func fixture(t) -> GameManager:
	var game = load("res://Test/i03_medicine_cases.gd").new().fixture(t)
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game._set_input_player(game.players[0])
	game._play_btn.visible = true
	game.players[0].hp = 1
	return game

func dispose(t, game):
	game._game_over = true
	game.queue_free()
	await t.process_frame

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	for action in ["accept", "cancel", "invalid", "phase", "egg", "hp", "restart", "reentry", "full", "gifted"]:
		var game = fixture(t)
		var p: Player = game.players[0]
		var serial = game._card_action_serial
		if action == "full": p.hp = p.max_hp
		if action == "gifted":
			game.turn_manager.current_player_idx = 1
			game.turn_manager.play_actor_idx = 0
		game._egg_heal_override = func():
			match action:
				"cancel": return 1
				"invalid": return game.CHOICE_INVALID
				"phase": game.turn_manager.current_phase = TurnManager.Phase.DISCARD
				"egg": p.fire_dragon_eggs = 2
				"hp": p.hp = 2
				"restart": game.reset_game_over_state()
				"reentry": await game._on_egg_heal_clicked(p)
			return 0
		await game._on_egg_heal_clicked(p)
		var spent = action in ["accept", "reentry", "full", "gifted"]
		t.check(p.fire_dragon_eggs == (0 if spent else (2 if action == "egg" else 1)), "I03 egg committed once or untouched after decline/stale: " + action)
		t.check(p.hp == (3 if spent else (2 if action == "hp" else 1)), "I03 egg heal is capped at max and only follows valid payment: " + action)
		t.check(not game._egg_heal_pending and game._card_action_serial == serial and p.prep_tokens == 0 and p.hand_size() == 0, "I03 egg is not card use, hand discard, or prep income")
		await dispose(t, game)
	await rescue_order(t)
	await windows(t)
	var game = fixture(t)
	var p: Player = game.players[0]
	p.max_hp = 5
	p.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.HEAL_STAFF))
	game._egg_heal_override = func(): return 0
	await game._on_egg_heal_clicked(p)
	t.check(p.hp == 3 and not p.heal_staff_peach_used, "I03 egg heal is not increased by healing staff")
	await dispose(t, game)
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]

func rescue_order(t):
	for mode in ["early_peach", "egg", "repeat", "decline", "stale_egg"]:
		var game = fixture(t)
		var p: Player = game.players[0]
		game.turn_manager.current_player_idx = 1
		game.turn_manager.current_phase = TurnManager.Phase.PLAY
		for other in game.players: other.hand.clear()
		p.hp = -2 if mode == "repeat" else 0
		p.fire_dragon_eggs = 2 if mode == "repeat" else 1
		if mode == "early_peach": game.players[2].hand.append(null)
		var serial = game._card_action_serial
		var sequence: Array = []
		t.check(not game._rescue_options(p, p).has(game.RESCUE_EGG), "I03 egg cannot insert before its own rescue response")
		game._rescue_choice_override = func(rescuer, victim, options):
			sequence.append(rescuer.seat_index)
			if mode == "early_peach":
				t.check(rescuer == game.players[2] and not options.has(game.RESCUE_EGG), "I03 C has Peach window before A's egg turn")
				return CardData.CardSubType.PEACH
			if mode == "stale_egg": p.fire_dragon_eggs = 2
			return -1 if mode == "decline" else game.RESCUE_EGG
		var result = await game._run_rescue_round(p)
		if mode == "early_peach":
			t.check(p.hp == 1 and p.fire_dragon_eggs == 1 and sequence == [2], "I03 prior Peach saves A; no premature egg expense")
		else:
			t.check(sequence == ([0, 0] if mode == "repeat" else [0]), "I03 only A's normal rescue response offers eggs; may repeat while dying")
			t.check(p.hp == (0 if mode in ["decline", "stale_egg"] else 2), "I03 two-point self rescue follows normal order")
			t.check(game._card_action_serial == serial, "I03 egg rescue publishes no Peach/Wine USE")
		t.check((result == game.CHOICE_INVALID) == (mode == "stale_egg") and game._egg_rescue_turns.is_empty(), "I03 changed egg invalidates pending rescue and cleans response lease")
		await dispose(t, game)

func windows(t):
	for mode in ["play", "cancel", "timeout", "close", "rescue"]:
		var game = fixture(t)
		var p: Player = game.players[0]
		game.lan_enabled = true
		var bridge = LanGameBridge.new()
		bridge.game = game
		t.root.add_child(bridge)
		var done: Array = []
		if mode == "rescue":
			p.hp = 0
			for other in game.players: other.hand.clear()
			var rescue = func(): done.append(await game._run_rescue_round(p))
			rescue.call()
		else:
			game._sync_all_ui()
			await t.process_frame
			t.check(game._egg_heal_btn.get_global_rect().end.y <= t.root.get_visible_rect().end.y, "I03 egg quick action remains inside the actual viewport")
			var open = bridge.snapshot(0).controls.filter(func(control): return control.text == "弃蛋回复2体力")
			t.check(open.size() == 1 and bridge.submit(0, open[0].id), "I03 main egg button opens real controller prompt via bridge")
		await t.process_frame
		var state = bridge.snapshot(0)
		var options = state.controls.filter(func(control): return control.text == "弃蛋回复2体力")
		t.check(options.size() == 1 and bridge.snapshot(1).controls.is_empty(), "I03 egg prompt belongs only to Chris controller")
		var token = options[0].id
		t.check(not bridge.submit(1, token), "I03 wrong peer cannot pay egg")
		if mode in ["play", "rescue"]: t.check(bridge.submit(0, token), "I03 egg payment accepted through real UI command")
		elif mode == "cancel":
			var cancel = state.controls.filter(func(control): return control.text == "取消")[0]
			bridge.submit(0, cancel.id)
		elif mode == "timeout": game._countdown_on_timeout.call()
		else: game._choice_prompt_stack.back().overlay.queue_free()
		for frame in 3: await t.process_frame
		t.check(p.fire_dragon_eggs == (0 if mode in ["play", "rescue"] else 1), "I03 optional timeout/cancel/technical close never spend egg")
		t.check(not bridge.submit(0, token) and game._choice_prompt_stack.is_empty(), "I03 consumed/closed egg token cannot replay")
		if mode == "rescue": t.check(done == [0] and p.hp == 2, "I03 real rescue prompt completes normal self-response")
		bridge.game = null
		bridge.queue_free()
		await dispose(t, game)
