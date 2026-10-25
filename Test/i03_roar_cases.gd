extends RefCounted

func fixture(t) -> GameManager:
	var game = load("res://Test/i03_summon_cases.gd").new().fixture(t)
	var p: Player = game.players[0]
	game._hand_discard_override = func(_snapshot, _count, _mandatory): return [0, 1, 2]
	await game._on_summon_dragon_clicked(p)
	var id = game.unit_registry.id_for(game.unit_registry.active_units()[0])
	# Approved START-receipt fixture until I03c connects actual independent turns.
	game.fire_dragon_state.begin_turn(id, 1)
	game.fire_dragon_state.begin_turn(id, 2)
	game._sacrifice_override = func(): return false
	game._rescue_choice_override = func(_r, victim, _o):
		t.check(victim != game.unit_registry.entry(id).body, "I03 mechanism death never enters dragon rescue")
		return -1
	return game

func dispose(t, game):
	game._game_over = true
	game.queue_free()
	await t.process_frame

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	for mode in ["pay", "cancel", "phase", "egg", "registry", "target_dead", "reentry", "sage", "silver", "chain", "self", "death_wait", "death_invalid"]:
		var game = await fixture(t)
		var p: Player = game.players[0]
		var body: Player = game.unit_registry.active_units()[0]
		var target: Player = game.players[1]
		var id = game.unit_registry.id_for(body)
		var serial = game._card_action_serial
		var hand = p.hand_size()
		var nested: Array = []
		var deaths: Array = []
		var checkpoints: Array = []
		var armor: CardBase
		game.unit_death_committed.connect(func(unit): deaths.append(unit))
		if mode == "sage":
			armor = CardBase.create(CardData.CardSubType.SAGE_PROTECTION)
			body.equip_card_to_slot("armor", armor)
			body.sage_activated = true
			game._sage_save_override = func():
				t.check(false, "I03 direct mechanism kill cannot offer Sage")
				return true
		if mode == "silver": target.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.SILVER_LION))
		if mode == "chain":
			target.chained = true
			game.players[2].chained = true
		if mode in ["death_wait", "death_invalid"]:
			game.rule_scheduler.enqueue("unit death continuation fixture", func(context, stage):
				t.check(context.victim == body and body.is_dead() and target.hp == 5 and stage == "unit_after_death", "I03 unit final death is committed before parent roar damage")
				await t.process_frame
				checkpoints.append(stage)
				if mode == "death_invalid": game.reset_game_over_state())
		t.check(not game.fire_dragon_state.is_revealed_to(id, p) and not game._roar_options(p).is_empty(), "I03 Q5 still-stealthed dragon can be chosen as roar cost")
		game._roar_choice_override = func(_actor, options):
			var index = options.find(options.filter(func(option): return option.target == (p if mode == "self" else target))[0])
			match mode:
				"cancel": return -1
				"phase": game.turn_manager.current_phase = TurnManager.Phase.DISCARD
				"egg": p.fire_dragon_eggs = 0
				"registry": game._reset_unit_registry()
				"target_dead": target.mark_dead()
				"reentry": nested.append(await game._on_roar_clicked(p))
			return index
		var result = await game._on_roar_clicked(p)
		var paid = mode in ["pay", "reentry", "sage", "silver", "chain", "self", "death_wait", "death_invalid"]
		t.check(result == (1 if paid and mode != "death_invalid" else (0 if mode == "cancel" else game.CHOICE_INVALID)), "I03 roar outcome distinguishes paid/decline/technical invalid: " + mode)
		t.check(p.fire_dragon_eggs == (0 if paid or mode == "egg" else 1), "I03 roar spends exactly one egg only after valid choice")
		if mode != "registry": t.check(body.is_dead() == paid and deaths.size() == (1 if paid else 0), "I03 roar directly retires exactly one dragon")
		t.check(game._card_action_serial == serial and p.prep_tokens == 0 and not game._roar_pending, "I03 roar has no card USE/prep income and releases lock")
		if mode not in ["self", "target_dead"]:
			t.check(target.hp == (4 if mode == "silver" else (-1 if paid and mode != "death_invalid" else 5)), "I03 roar base six fire follows normal armor and dying pipeline")
		if mode != "self": t.check(p.hand_size() == hand, "I03 roar egg/unit costs never discard summoner hand")
		if mode == "reentry": t.check(nested == [game.CHOICE_INVALID], "I03 duplicate roar cannot consume costs twice")
		if mode == "sage": t.check(body.is_dead() and game.deck._discard.count(armor) == 1 and body.hand_size() == 0, "I03 Q4 activated Sage cannot save sacrificed body or draw four")
		if mode == "chain": t.check(game.players[2].hp == -1 and not target.chained and not game.players[2].chained, "I03 roar fire propagates through existing linked damage")
		if mode == "self": t.check(p.is_dead() and deaths.size() == 1, "I03 own-target roar retains source and never cleans sacrificed body twice")
		if mode in ["death_wait", "death_invalid"]: t.check(checkpoints == ["unit_after_death"], "I03 roar awaits unit death checkpoint before continuing or stopping")
		await dispose(t, game)
	await windows(t)
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]

func windows(t):
	for mode in ["pay", "cancel", "timeout", "close"]:
		var game = await fixture(t)
		game.lan_enabled = true
		var bridge = LanGameBridge.new()
		bridge.game = game
		t.root.add_child(bridge)
		game._sync_all_ui()
		await t.process_frame
		t.check(game._roar_btn.get_global_rect().end.y <= t.root.get_visible_rect().end.y, "I03 roar button stays within viewport")
		var open = bridge.snapshot(0).controls.filter(func(c): return c.text == "恶龙咆哮")[0]
		t.check(bridge.submit(0, open.id), "I03 real LAN command opens roar picker")
		await t.process_frame
		var state = bridge.snapshot(0)
		var option = state.controls.filter(func(c): return c.text.ends_with(" → 2号 " + game.players[1].player_name))[0]
		t.check(bridge.snapshot(1).controls.is_empty() and not bridge.submit(1, option.id), "I03 only controller can choose sacrifice and damage target")
		if mode == "pay": bridge.submit(0, option.id)
		elif mode == "cancel": bridge.submit(0, state.controls.filter(func(c): return c.text == "取消咆哮")[0].id)
		elif mode == "timeout": game._countdown_on_timeout.call()
		else: game._choice_prompt_stack.back().overlay.queue_free()
		for frame in 3: await t.process_frame
		t.check(game.players[0].fire_dragon_eggs == (0 if mode == "pay" else 1) and game.unit_registry.active_units().size() == (0 if mode == "pay" else 1), "I03 optional cancel/timeout/close never sacrifice or spend egg")
		t.check(not bridge.submit(0, option.id) and not bridge.submit(0, open.id), "I03 consumed roar commands cannot replay")
		bridge.game = null
		bridge.queue_free()
		await dispose(t, game)
