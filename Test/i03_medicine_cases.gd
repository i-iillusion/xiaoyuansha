extends RefCounted

func fixture(t) -> GameManager:
	load("res://Test/h02_integration_cases.gd").new().prepare(5, GameModes.FREE_FOR_ALL)
	GameManager.selected_general = "克里斯·西弗"
	var game = load("res://Scenes/Game.tscn").instantiate()
	game.auto_start = false
	game._medicine_choice_override = func(_p, _options): return "cancel"
	t.root.add_child(game)
	game.start_game()
	game._halt_countdown()
	game.turn_manager.current_phase = TurnManager.Phase.DRAW
	for p in game.players:
		p.hand.clear()
		p.determined_cards.clear()
		if p != game.players[0]: p.hand.assign([null, null])
	return game

func dispose(t, game):
	game._game_over = true
	game.queue_free()
	await t.process_frame

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	for scenario in ["cancel", "zero", "one", "two", "duplicate", "self", "three", "stale", "reentry", "supply", "granted_supply", "concrete", "awake"]:
		var game = fixture(t)
		var p: Player = game.players[0]
		var a: Player = game.players[1]
		var b: Player = game.players[2]
		var resource: CardBase
		if scenario == "concrete":
			resource = CardBase.create(CardData.CardSubType.LIANNU)
			b.equip_card_to_slot("weapon", resource)
			a.hand.clear()
			a.determined_cards.append(b.remove_equipment("weapon"))
		if scenario == "awake":
			a.general_name = "史蒂芬·彼特先斯"
			a.max_hp = 3
			a.hp = 3
			a.hand.assign([null])
			game._awaken_pick_override = func(): return 1
		var nested: Array = []
		var actions_before = game._card_action_serial
		game._medicine_choice_override = func(_actor, _options):
			match scenario:
				"cancel": return "cancel"
				"zero": return []
				"one", "concrete", "awake": return [a]
				"duplicate": return [a, a]
				"self": return [p]
				"three": return [a, b, game.players[3]]
				"stale":
					game.turn_manager.current_phase = TurnManager.Phase.PLAY
					return [a]
				"reentry":
					nested.append(await game._draw_phase_cards(p))
					return [a, b]
			return [a, b]
		game.turn_manager.supply_shortage_active = scenario in ["supply", "granted_supply"]
		var result = await game._draw_phase_cards(p, scenario != "granted_supply")
		var invalid = scenario in ["duplicate", "self", "three", "stale"]
		t.check(result != invalid, "I03 medicine successful, declined and invalid outcomes distinct: " + scenario)
		var expected = 0 if invalid or scenario == "zero" else (1 if scenario in ["one", "concrete", "awake"] else 2)
		t.check(p.hand_size() == expected, "I03 medicine does not add ordinary draw after committed replacement: " + scenario)
		if invalid or scenario in ["cancel", "zero"]:
			t.check(a.hand_size() == 2 and b.hand_size() == 2, "I03 canceled/invalid/zero selections do not move target hands")
		else:
			t.check(a.hand_size() == (0 if scenario == "concrete" else (2 if scenario == "awake" else 1)), "I03 one original card leaves each selected hand")
		if scenario == "concrete": t.check(p.hand[0] == resource and resource.sub_type == CardData.CardSubType.LIANNU, "I03 acquired concrete equipment retains original object and type")
		elif not invalid: t.check(p.hand.all(func(card): return card == null), "I03 acquired/drawn arbitrary hands remain arbitrary")
		if scenario == "reentry": t.check(nested == [false], "I03 reentrant draw rejected before a second payment/replacement")
		if scenario in ["supply", "granted_supply"]: t.check(game.turn_manager.supply_shortage_active == (scenario == "granted_supply"), "I03 gifted draw does not consume source supply flag; own replaced draw consumes it")
		if scenario == "awake": t.check(a.awoken and a.awake_choice == 1, "I03 last target hand finishes forced awakening before returning")
		t.check(game._medicine_pending.is_empty() and p.prep_tokens == 0 and game._card_action_serial == actions_before, "I03 skill movement emits no card USE and releases selection lease")
		await dispose(t, game)
	await window_cases(t)
	await granted_case(t)
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]

func window_cases(t):
	for action in ["accept", "cancel", "timeout", "close", "stale"]:
		var game = fixture(t)
		game.lan_enabled = true
		game._medicine_choice_override = Callable()
		var bridge = LanGameBridge.new()
		bridge.game = game
		t.root.add_child(bridge)
		var answers: Array = []
		var run_draw = func(): answers.append(await game._draw_phase_cards(game.players[0]))
		run_draw.call()
		await t.process_frame
		var panel: Control = game._choice_prompt_stack.back().overlay.get_child(0)
		t.check(panel.get_global_rect().position.x >= 0 and panel.get_global_rect().position.y >= 0, "I03 medicine panel is inside the actual viewport, not negative local coordinates")
		var mine = bridge.snapshot(0)
		var options = mine.controls.filter(func(control): return control.text.begins_with("获得："))
		t.check(not options.is_empty() and bridge.snapshot(1).controls.is_empty(), "I03 medicine window belongs to actual drawing controller")
		var token = options[0].id
		t.check(not bridge.submit(1, token), "I03 another client cannot select a steal target")
		if action == "accept": t.check(bridge.submit(0, token), "I03 controller can select a real medicine target combination")
		elif action == "cancel":
			var decline = mine.controls.filter(func(control): return control.text == "不发动（正常摸牌）")[0]
			t.check(bridge.submit(0, decline.id), "I03 decline follows original drawing")
		elif action == "timeout": game._countdown_on_timeout.call()
		elif action == "close": game._choice_prompt_stack.back().overlay.queue_free()
		else: game.turn_manager.current_phase = TurnManager.Phase.PLAY
		for frame in 3: await t.process_frame
		t.check(answers == [action not in ["close", "stale"]], "I03 technical close/stale is not decline or timeout")
		t.check(game.players[0].hand_size() == (1 if action == "accept" else (2 if action in ["cancel", "timeout"] else 0)), "I03 actual window result moves/draws only authorized cards")
		t.check(not bridge.submit(0, token) and game._choice_prompt_stack.is_empty(), "I03 old medicine token cannot be replayed")
		bridge.game = null
		bridge.queue_free()
		await dispose(t, game)

func granted_case(t):
	var game = fixture(t)
	var source: Player = game.players[0]
	var target: Player = game.players[1]
	source.general_name = "麦克斯·欧尼斯特"
	target.general_name = "克里斯·西弗"
	game.turn_manager.current_phase = TurnManager.Phase.START
	game._meiyong_execution_owner = 9
	game._meiyong_execution_generation = 9
	game._medicine_choice_override = func(actor, _options):
		t.check(actor == target, "I03 gifted draw asks recipient, not current turn owner")
		return [game.players[2]]
	var result = await game._run_meiyong_granted_nonplay(source, target, 9, TurnManager.Phase.DRAW)
	t.check(result == 1 and game.turn_manager.current_phase == TurnManager.Phase.START and game.turn_manager._standalone_play_frame.is_empty(), "I03 gifted medicine completes existing standalone draw frame")
	t.check(target.hand_size() == 3 and game.players[2].hand_size() == 1 and source.hand_size() == 0, "I03 gifted medicine uses recipient's resources and skips its ordinary draw")
	await dispose(t, game)
