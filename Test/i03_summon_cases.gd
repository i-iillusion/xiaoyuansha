extends RefCounted

func fixture(t) -> GameManager:
	var game = load("res://Test/i03_egg_cases.gd").new().fixture(t)
	game.players[0].hand.assign([null, null, null, null])
	return game

func dispose(t, game):
	game._game_over = true
	game.queue_free()
	await t.process_frame

func seed_dragon(game, owner):
	var body = FireDragonState.create_body()
	var id = game._register_unit_body(UnitRegistry.Kind.FIRE_DRAGON, body, owner)
	game.fire_dragon_state.attach(id)
	return body

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	for mode in ["pay", "exact", "cancel", "duplicate", "range", "partial", "phase", "egg", "reset", "registry", "general", "occupy", "existing", "stale_card", "reentry", "dead", "noegg", "insufficient", "concrete", "gifted"]:
		var game = fixture(t)
		var p: Player = game.players[0]
		var original: CardBase
		var armor: CardBase
		if mode == "exact": p.hand.resize(3)
		if mode == "insufficient": p.hand.resize(2)
		if mode == "noegg": p.fire_dragon_eggs = 0
		if mode == "dead": p.mark_dead()
		if mode == "existing": seed_dragon(game, p)
		if mode == "gifted":
			game.turn_manager.current_player_idx = 1
			game.turn_manager.play_actor_idx = 0
		if mode in ["concrete", "stale_card"]:
			var other: Player = game.players[1]
			other.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.LIANNU))
			original = other.remove_equipment("weapon")
			if mode == "concrete":
				other.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.SILVER_LION))
				armor = other.remove_equipment("armor")
				p.hand.assign([null, null])
				p.determined_cards.assign([original, armor])
		var initial_count = p.hand_size()
		var actions = game._card_action_serial
		var calls: Array = []
		var nested: Array = []
		var registered: Array = []
		game.unit_registered.connect(func(id):
			if mode == "occupy": return
			registered.append(id)
			t.check(p.fire_dragon_eggs == 0 and p.hand_size() == initial_count - 3, "I03 summon announces body only after full card and egg cost"))
		game._hand_discard_override = func(_snapshot, count, mandatory):
			calls.append(count)
			t.check(count == 3 and not mandatory, "I03 summon is a three-original-card optional skill payment")
			match mode:
				"cancel": return []
				"duplicate": return [0, 0, 1]
				"range": return [0, 1, 99]
				"partial": return [0, 1]
				"phase": game.turn_manager.current_phase = TurnManager.Phase.DISCARD
				"egg": p.fire_dragon_eggs = 2
				"reset": game.reset_game_over_state()
				"registry": game._reset_unit_registry()
				"general": p.general_name = "稻草人"
				"occupy":
					# Authorized membership fixture invalidates the still-unpaid action.
					seed_dragon(game, p)
				"stale_card": p.hand[0] = original
				"reentry":
					nested.append(await game._on_summon_dragon_clicked(p))
					await game._on_egg_heal_clicked(p)
				"concrete": return [0, 2, 3]
			return [0, 1, 2]
		var result = await game._on_summon_dragon_clicked(p)
		var paid = mode in ["pay", "exact", "reentry", "concrete", "gifted"]
		t.check(result == (1 if paid else (0 if mode == "cancel" else game.CHOICE_INVALID)), "I03 summon paid, decline and invalid outcomes: " + mode)
		t.check(p.hand_size() == initial_count - (3 if paid else 0), "I03 summon never partially removes hand cost: " + mode)
		t.check(p.fire_dragon_eggs == (0 if paid or mode == "noegg" else (2 if mode == "egg" else 1)), "I03 summon egg payment follows valid card selection: " + mode)
		t.check(game.unit_registry.active_units().size() == (1 if paid or mode in ["existing", "occupy"] else 0), "I03 summon cap and invalidation prevent extra unit: " + mode)
		t.check(game._summon_dragon_pending.is_empty() and game._card_action_serial == actions and p.prep_tokens == 0, "I03 summon releases lease and emits no card USE/prep")
		if mode == "reentry": t.check(nested == [game.CHOICE_INVALID], "I03 nested summon/egg action cannot double pay the same resource")
		if mode in ["dead", "noegg", "insufficient", "existing"]: t.check(calls.is_empty(), "I03 invalid initial summon does not open a fee prompt")
		if paid:
			var body: Player = game.unit_registry.active_units()[0]
			var id = game.unit_registry.id_for(body)
			t.check(body.hp == 3 and body.max_hp == 3 and body.hand_size() == 0 and body.identity == "" and body.seat_index == -1 and not game.players.has(body), "I03 actual summon creates independent three-HP zero-hand identityless body")
			t.check(game.fire_dragon_state.turn_count(id) == 0 and not game.fire_dragon_state.is_revealed_to(id, p) and registered.size() == 1, "I03 summon attaches initial stealth state without inventing an immediate turn")
			if mode == "concrete":
				t.check(game.deck._discard.count(original) == 1 and game.deck._discard.count(armor) == 1 and p.hand == [null] and p.determined_cards.is_empty(), "I03 physical equipment transferred into hand is discarded once as original, never renamed")
				t.check(p.hp == 1, "I03 discarding a hand-held Silver Lion is not losing equipped armor and never heals summoner")
		await dispose(t, game)
	await windows(t)
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]

func windows(t):
	for mode in ["pay", "cancel", "timeout", "close", "phase"]:
		var game = fixture(t)
		game.lan_enabled = true
		var p: Player = game.players[0]
		var bridge = LanGameBridge.new()
		bridge.game = game
		t.root.add_child(bridge)
		game._sync_all_ui()
		await t.process_frame
		var rect = game._summon_dragon_btn.get_global_rect()
		t.check(rect.position.x >= 0 and rect.end.x <= t.root.get_visible_rect().end.x and rect.end.y <= t.root.get_visible_rect().end.y, "I03 summon shares action row and stays inside viewport")
		var open = bridge.snapshot(0).controls.filter(func(c): return c.text == "召唤火龙")
		t.check(open.size() == 1 and bridge.submit(0, open[0].id), "I03 controller opens real summon hand selection")
		await t.process_frame
		var state = bridge.snapshot(0)
		var cards = state.controls.filter(func(c): return "任意牌（未具体化）" in c.text)
		t.check(cards.size() == 4 and bridge.snapshot(1).controls.is_empty(), "I03 summon private hand picker is owner-only")
		t.check(not bridge.submit(1, cards[0].id), "I03 another peer cannot pay summon fee")
		if mode == "pay":
			# Refresh each token: a toggle changes the visible command epoch.
			for index in 3:
				state = bridge.snapshot(0)
				var card = state.controls.filter(func(c): return c.text.begins_with(str(index + 1) + " · "))[0]
				t.check(bridge.submit(0, card.id), "I03 controller selects an original fee slot")
			var confirm = bridge.snapshot(0).controls.filter(func(c): return c.text == "确认弃牌")[0]
			t.check(bridge.submit(0, confirm.id), "I03 confirm pays three cards and one egg in one continuation")
		elif mode == "cancel":
			var cancel = state.controls.filter(func(c): return c.text == "取消发动")[0]
			bridge.submit(0, cancel.id)
		elif mode == "timeout": game._countdown_on_timeout.call()
		elif mode == "phase": game.turn_manager.current_phase = TurnManager.Phase.DISCARD
		else: game._choice_prompt_stack.back().overlay.queue_free()
		for frame in 3: await t.process_frame
		t.check(p.hand_size() == (1 if mode == "pay" else 4) and p.fire_dragon_eggs == (0 if mode == "pay" else 1), "I03 UI cancel/timeout/technical invalidation charges neither fee")
		t.check(game.unit_registry.active_units().size() == (1 if mode == "pay" else 0) and game._choice_prompt_stack.is_empty(), "I03 actual summon window creates only a fully paid body")
		t.check(not bridge.submit(0, cards[0].id) and not bridge.submit(0, open[0].id), "I03 old selection and summon tokens cannot replay")
		bridge.game = null
		bridge.queue_free()
		await dispose(t, game)
