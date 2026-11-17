extends RefCounted
const SALLY = "萨利·赛克斯"

func fixture(t, seat := 0):
	var game = load("res://Test/h02_integration_cases.gd").new().fixture(t, 5, GameModes.FREE_FOR_ALL)
	game.lan_enabled = true
	game._nullify_override = func(): return false
	game._dodge_override = func(): return false
	game._sacrifice_actor_override = func(_p, _t, _a): return false
	game._paixiong_override = func(): return false # Explicitly decline Stephen's unrelated optional reaction.
	game._chixiong_activate_override = func(): return true
	game._chixiong_target_override = func(): return false
	game._hand_discard_override = func(snapshot, count, _mandatory): return snapshot.defaults(count)
	for p in game.players:
		p.hand.clear(); p.determined_cards.clear(); p.judgment_cards.clear()
		p.general_name = "稻草人"; p.gender = "male"; p.max_hp = 5; p.hp = 5
	var owner: Player = game.players[seat]
	owner.general_name = SALLY; owner.gender = "female"; owner.max_hp = 3; owner.hp = 3
	owner.sally_jiegui_enabled = true
	for p in game.players: p.capture_game_start_state()
	# Explicit acting boundary, not a claim of upstream natural turns.
	game.turn_manager.current_player_idx = seat
	game.turn_manager.play_actor_idx = seat
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game._set_input_player(owner)
	return game

func dispose(t, game):
	game._game_over = true; game.queue_free()
	for i in 3: await t.process_frame

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	for mode in ["virtual", "real", "disabled", "other_weapon", "hidden", "same", "none", "shield", "discard", "decline"]:
		var game = fixture(t)
		var owner = game.players[0]; var target = game.players[1]
		var payment = CardBase.create(CardData.CardSubType.PEACH)
		if mode == "real":
			owner.sally_jiegui_enabled = false
			owner.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.CHIXIONG_SHUANGGU))
		if mode == "disabled": owner.sally_jiegui_enabled = false
		if mode == "other_weapon": owner.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.LIANNU))
		if mode == "hidden":
			var hidden = CardBase.create(CardData.CardSubType.HIDDEN_EQUIPMENT); hidden.hidden_category = "weapon"
			owner.equip_hidden_card_to_slot("weapon", hidden)
		if mode == "same": target.gender = "female"
		if mode == "none": target.gender = "none"
		if mode == "shield": target.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.QINGGANG_SHIELD))
		var asks: Array = []
		game._chixiong_activate_override = func(): asks.append(true); return mode != "decline"
		if mode == "discard":
			target.hand.append(payment)
			game._chixiong_target_override = func(): return true
		var original = CardBase.create(CardData.CardSubType.STRIKE)
		owner.determined_cards.append(original)
		var events: Array = []
		game.card_action_committed.connect(func(e): events.append(e))
		await game.execute_card_on_target(target, CardData.CardSubType.STRIKE)
		var offered = mode in ["virtual", "real", "discard", "decline"]
		t.check(asks.size() == (1 if offered else 0), "I05e2b effective sword qualification controls actual trigger: " + mode)
		t.check(owner.hand_size() == (1 if mode in ["virtual", "real"] else 0) and target.hp == 4, "I05e2b only Jiegui is enabled: actual reward/payment precedes normal one-damage Strike: " + mode)
		t.check(events.size() == 1 and events[0].card == original and events[0].settlement_completed and game._pending_card_actions.is_empty(), "I05e2b only paid Strike creates a completed USE, no synthetic sword USE: " + mode)
		t.check(game.deck._discard.count(original) == 1 and game.deck._discard.count(payment) == (1 if mode == "discard" else 0), "I05e2b original Strike and selected actual hand resource discard once: " + mode)
		await dispose(t, game)
	for stage in ["activate", "target"]:
		for invalid in ["capability", "weapon", "gender", "source_reset", "target_reset", "phase", "lifecycle"]:
			var game = fixture(t)
			var owner = game.players[0]; var target = game.players[1]
			var original = CardBase.create(CardData.CardSubType.STRIKE); owner.hand.append(original)
			var actions: Array = []; game.card_action_committed.connect(func(e): actions.append(e))
			target.hand.append(CardBase.create(CardData.CardSubType.PEACH))
			var change = func():
				match invalid:
					"capability": owner.sally_jiegui_enabled = false
					"weapon": owner.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.LIANNU))
					"gender": target.gender = owner.gender
					"source_reset": owner.restore_game_start_state()
					"target_reset": target.restore_game_start_state()
					"phase":
						game.turn_manager.current_phase = TurnManager.Phase.END
						game.turn_manager.current_phase = TurnManager.Phase.PLAY
					"lifecycle": game._dying_lifecycle_generation += 1
				return true
			if stage == "activate": game._chixiong_activate_override = change
			else: game._chixiong_target_override = change
			await game.execute_card_on_target(target, CardData.CardSubType.STRIKE)
			t.check(target.hp == 5 and target.hand_size() == 1 and owner.hand_size() == 0, "I05e2b stale virtual eligibility cannot draw/discard/damage: " + stage + "/" + invalid)
			t.check(game.deck._discard.count(original) == 1 and game._pending_card_actions.is_empty(), "I05e2b invalidated parent retains paid original and clears pending USE: " + stage + "/" + invalid)
			t.check(actions.size() == 1 and not actions[0].settlement_completed, "I05e2b technical qualification invalidation abandons completion receipt: " + stage + "/" + invalid)
			await dispose(t, game)
	for stage in ["activate", "target"]:
		var game = fixture(t)
		var owner = game.players[0]; var target = game.players[1]
		owner.hand.append(null); target.hand.append(CardBase.create(CardData.CardSubType.PEACH))
		var die = func(): owner.hp = 0; owner.mark_dead(); return false
		if stage == "activate": game._chixiong_activate_override = die
		else: game._chixiong_target_override = die
		await game.execute_card_on_target(target, CardData.CardSubType.STRIKE)
		t.check(owner.is_dead() and target.hp == 4 and target.hand_size() == 1 and owner.hand_size() == 0, "I05e2b engineering final-source-death invalidates virtual reward, retains original sourceless damage")
		t.check(game._pending_card_actions.is_empty(), "I05e2b final-source-death does not strand paid card parent")
		await dispose(t, game)
	await nested_rewards(t)
	await real_sword_completion(t)
	GameManager.selected_players = saved[0]; GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]; GameManager.random_general = saved[3]; GameManager.random_identity = saved[4]

func nested_rewards(t):
	var game = fixture(t)
	var owner = game.players[0]; var target = game.players[1]; var sunny = game.players[2]
	sunny.general_name = "桑尼·斯派"
	game._corruption_rules_enabled = true
	var offered: Array = []
	game._corruption_choice_override = func(_p, batch, stage, valid):
		offered.append([batch.owner, batch.count, stage, valid.call()])
		return 0
	game._rps_override = func(p): return GameManager.RPS_ROCK if p == sunny else GameManager.RPS_SCISSORS
	owner.hand.append(null)
	await game.execute_card_on_target(target, CardData.CardSubType.STRIKE)
	t.check(not offered.is_empty() and offered[0][0] == owner and offered[0][1] == 1 and offered[0][3], "I05e2b virtual weapon reward opens actual one-card Corruption batch")
	t.check(owner.hand_size() == 0 and sunny.hand_size() == 1 and target.hp == 4 and game._pending_card_actions.is_empty(), "I05e2b actual Corruption completes before original Strike continues")
	await dispose(t, game)

	game = fixture(t)
	owner = game.players[0]; target = game.players[1]; sunny = game.players[2]
	sunny.general_name = "桑尼·斯派"; game._corruption_rules_enabled = true
	game._corruption_choice_override = func(_p, _batch, _stage, _valid):
		# Engineering post-commit boundary, not a claim that Corruption equips.
		owner.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.LIANNU))
		return -1
	owner.hand.append(null)
	await game.execute_card_on_target(target, CardData.CardSubType.STRIKE)
	t.check(owner.hand_size() == 1 and not owner.has_virtual_chixiong_effect() and target.hp == 4, "I05e2b committed reward is not rolled back when post-draw reaction changes equipment")
	t.check(game._pending_card_actions.is_empty(), "I05e2b committed virtual effect returns to original parent exactly once")
	await dispose(t, game)
	game = fixture(t)
	owner = game.players[0]; target = game.players[1]
	target.general_name = "史蒂芬·彼特先斯"; target.max_hp = 3; target.hp = 3
	target.capture_game_start_state()
	target.hand.append(CardBase.create(CardData.CardSubType.PEACH)); owner.hand.append(null)
	game._chixiong_target_override = func(): return true
	game._awaken_pick_override = func(): return 1
	await game.execute_card_on_target(target, CardData.CardSubType.STRIKE)
	t.check(game._choice_prompt_stack.is_empty(), "I05e2b nested awakening parent finishes after explicitly declining unrelated Paixiong")
	t.check(target.awoken and target.max_hp == 2 and target.hp == 1 and target.hand_size() == 2, "I05e2b actual target discard awakens fully but does not undo an already-declared Strike")
	t.check(game._pending_card_actions.is_empty(), "I05e2b nested target awakening completes original parent")
	await dispose(t, game)

func real_sword_completion(t):
	for invalid in [false, true]:
		var game = fixture(t)
		var owner = game.players[0]; var target = game.players[1]
		owner.general_name = "里奥·普利威尔"; owner.gender = "male"; owner.sally_jiegui_enabled = false
		target.general_name = SALLY; target.gender = "female"
		owner.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.CHIXIONG_SHUANGGU))
		owner.hand.append(null)
		game._chixiong_activate_override = func(): return GameManager.CHOICE_INVALID if invalid else 0
		var actions: Array = []; game.card_action_committed.connect(func(e): actions.append(e))
		await game.execute_card_on_target(target, CardData.CardSubType.STRIKE)
		t.check(owner.prep_tokens == (0 if invalid else 1), "I05e2b actual Leo gets no Prep for technically interrupted real-sword parent; ordinary decline still completes")
		t.check(actions.size() == 1 and actions[0].settlement_completed == (not invalid) and game._pending_card_actions.is_empty(), "I05e2b real-sword technical invalidation and ordinary decline have distinct completion receipts")
		t.check(game.deck._discard.size() == 1 and target.hp == (5 if invalid else 4), "I05e2b real-sword correction retains paid original and ordinary damage semantics")
		await dispose(t, game)
