extends RefCounted

func fixture(t):
	var game = load("res://Test/i03_egg_cases.gd").new().fixture(t)
	game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
	game.turn_manager.turn_ended.disconnect(game._on_turn_ended)
	game.players[0].general_name = "稻草人"
	game.players[0].fire_dragon_eggs = 0
	var owner: Player = game.players[1]
	owner.general_name = "克里斯·西弗"
	owner.max_hp = 3
	owner.hp = 3
	game.fire_dragon_state.grant_start_egg(owner)
	owner.hand.assign([null, null, null, null])
	game.turn_manager.current_player_idx = 1
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game.ai_driver.chooser = func(_view, _actions): return -1
	game.ai_pacer.speed = AiActionPacer.Speed.FAST
	return game

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	for mode in ["summon", "concrete", "insufficient", "noegg", "existing", "phase", "hand", "egg", "gifted"]:
		var game = fixture(t)
		var owner: Player = game.players[1]
		var original: CardBase
		if mode == "concrete":
			original = CardBase.create(CardData.CardSubType.LIANNU)
			game.players[2].equip_card_to_slot("weapon", original)
			owner.hand.assign([null, null])
			owner.determined_cards.append(game.players[2].remove_equipment("weapon"))
		if mode == "insufficient": owner.hand.resize(2)
		if mode == "noegg": owner.fire_dragon_eggs = 0
		if mode == "existing": load("res://Test/i03_summon_cases.gd").new().seed_dragon(game, owner)
		if mode == "gifted":
			game.turn_manager.current_player_idx = 2
			game.turn_manager.current_phase = TurnManager.Phase.START
			game.turn_manager.begin_standalone_play(1)
		var waits: Array = []
		if mode in ["phase", "hand", "egg"]:
			game.ai_pacer.speed = AiActionPacer.Speed.STANDARD
			game.ai_pacer.wait_override = func(seconds):
				waits.append(seconds)
				if mode == "phase": game.turn_manager.current_phase = TurnManager.Phase.DISCARD
				if mode == "hand": owner.hand.clear()
				if mode == "egg": owner.fire_dragon_eggs = 0
				await t.process_frame
		if mode == "existing":
			t.check(await game._perform_summon_dragon(owner) == game.CHOICE_INVALID and owner.fire_dragon_eggs == 1 and owner.hand_size() == 4, "I03 shared AI transaction rejects existing dragon without paying")
		else: await game._run_ai_play(owner)
		var summoned = game.action_history.entries.filter(func(e): return e.kind == "unit_summoned")
		var paid = mode in ["summon", "concrete", "gifted"]
		t.check(summoned.size() == (1 if paid else 0) and game._summon_dragon_pending.is_empty(), "I03 AI shared summon transaction settles once: " + mode)
		if paid:
			t.check(owner.fire_dragon_eggs == 0 and owner.hand_size() == (0 if mode == "concrete" else 1) and game.unit_registry.turn_units().size() == 1, "I03 AI pays actual three originals and egg, not controller substitute")
			var dragon = game.unit_registry.turn_units()[0]
			t.check(dragon.hand_size() == 0 and dragon.identity == "" and game.fire_dragon_state.turn_count(game.unit_registry.id_for(dragon)) == 0, "I03 AI summon does not fabricate cards, identity or early unit START")
			if original != null: t.check(game.deck._discard.count(original) == 1, "I03 AI concrete original fee enters discard exactly once")
		if not waits.is_empty(): t.check(waits == [0.6], "I03 AI skill rechecks eligibility after normal presentation gate")
		game._game_over = true
		game.queue_free()
		await t.process_frame
	await roar(t)
	await candidates(t)
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]

func roar(t):
	for stale in [false, true]:
		var game = fixture(t)
		var owner: Player = game.players[1]
		owner.hand.clear()
		for p in game.players:
			if p != owner:
				p.max_hp = 8
				p.hp = 8
		var dragon = load("res://Test/i03_summon_cases.gd").new().seed_dragon(game, owner)
		var id = game.unit_registry.id_for(dragon)
		dragon.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.SAGE_PROTECTION))
		dragon.sage_activated = true
		game._sage_save_override = func():
			t.check(false, "I03 AI mechanism cost cannot offer dragon Sage rescue")
			return true
		game._sacrifice_override = func(): return false
		var options = game._roar_options(owner)
		var selected = game._ai_roar_index(owner, options)
		t.check(selected >= 0 and options[selected].body == dragon and options[selected].target != owner and options[selected].target != dragon, "I03 AI roar selects own sacrifice and non-controller target without changing human legality")
		var target: Player = options[selected].target
		if stale:
			game.ai_pacer.speed = AiActionPacer.Speed.STANDARD
			game.ai_pacer.wait_override = func(_seconds):
				owner.fire_dragon_eggs = 0
				await t.process_frame
		await game._run_ai_play(owner)
		t.check(dragon.is_dead() == not stale and game.unit_registry.contains_active(dragon) == stale and not game._roar_pending, "I03 AI roar rechecks cost then performs direct mechanism death exactly once")
		t.check(target.hp == (8 if stale else 2) and owner.hp == 3 and game.action_history.entries.filter(func(e): return e.kind == "roar").size() == (0 if stale else 1), "I03 AI shared roar deals one actual six-fire packet only after paid cost")
		if not stale: t.check(game.unit_registry.entry(id).removed, "I03 AI roar retires actual unit membership")
		game._game_over = true
		game.queue_free()
		await t.process_frame

func candidates(t):
	var game = fixture(t)
	var owner: Player = game.players[1]
	var dragon = load("res://Test/i03_summon_cases.gd").new().seed_dragon(game, owner)
	var id = game.unit_registry.id_for(dragon)
	var targets: Array[Player] = [owner]
	game.fire_dragon_state.record_use(id, 1, targets) # Candidate-only public visibility fixture.
	dragon.hand.assign([null, null, null, null])
	dragon.hp = 2
	game.turn_manager.current_unit_id = id
	var choices = game._ai_play_candidates(game._ai_observation(dragon))
	t.check(game._get_strike_targets(dragon).has(owner) and game.get_trick_targets(dragon, CardData.CardSubType.DUEL).has(owner), "I03 human unit legality still includes its controller when revealed")
	t.check(not choices.any(func(action): return typeof(action.target) == TYPE_INT and action.target == owner.seat_index), "I03 AI unit filters own controller from targeted negative actions")
	t.check(not choices.any(func(action): return action.sub in [CardData.CardSubType.BARBARIAN_INVASION, CardData.CardSubType.VOLLEY_OF_ARROWS, CardData.CardSubType.DISARM, CardData.CardSubType.LIGHTNING]), "I03 AI unit avoids harmful global actions against its controller")
	t.check(choices.any(func(action): return action.sub == CardData.CardSubType.PEACH), "I03 AI unit still offers own legal self Peach")
	game.turn_manager.current_unit_id = ""
	choices = game._ai_play_candidates(game._ai_observation(owner))
	t.check(game._get_strike_targets(owner).has(dragon) and not choices.any(func(action): return typeof(action.target) == TYPE_STRING and action.target == id), "I03 AI owner filters own dragon without changing human target rules")
	game._game_over = true
	game.queue_free()
	await t.process_frame
