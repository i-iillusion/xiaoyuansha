extends RefCounted

func run(suite):
	var game: GameManager = suite.game
	var tm = game.turn_manager
	var phase = tm.current_phase
	var bank = game._bank_remaining
	var callback = game._on_phase_changed
	tm.phase_changed.disconnect(callback)
	var resetter = load("res://Test/prep_single_replace_cases.gd").new()
	for concrete in [false, true]:
		for mode in ["normal", "fire", "refuse", "limit", "missing_weapon", "no_card", "wrong_card", "restart", "virtual"]:
			resetter._reset(suite)
			game.deck._discard.clear()
			tm.current_phase = TurnManager.Phase.PLAY
			var user: Player = game.players[0]
			var first: Player = game.players[2]
			var second: Player = game.players[3]
			var weapon = CardBase.create(CardData.CardSubType.QINGGANG_SWORD)
			if mode != "missing_weapon": first.equip_card_to_slot("weapon", weapon)
			first.hand.append(null)
			var original = CardBase.create(CardData.CardSubType.DODGE if mode == "wrong_card" else CardData.CardSubType.BORROWED_SWORD) if concrete else null
			if mode != "no_card":
				if concrete: user.determined_cards.append(original)
				else: user.hand.append(null)
			if mode == "virtual":
				user.general_name = "安普提·斯丢皮得"
				game._yes_ah_active = true
			if mode == "limit": tm.borrowed_sword_count_this_turn = 2
			tm.strike_count_this_turn = 1
			game._borrowed_second_target_override = func(options): return options.find(second)
			game._borrowed_strike_override = func(_p, _t, _options):
				if mode == "restart": game.reset_game_over_state()
				return -1 if mode == "refuse" else CardData.CardSubType.FIRE_STRIKE if mode == "fire" else CardData.CardSubType.STRIKE
			var events: Array[CardActionEvent] = []
			var finished: Array[CardActionEvent] = []
			var commit = func(e): events.append(e)
			var finish = func(e): finished.append(e)
			game.card_action_committed.connect(commit)
			game.card_action_completed.connect(finish)
			var rejected = mode in ["limit", "missing_weapon", "no_card"] or (mode == "wrong_card" and concrete)
			suite.check(not game.get_trick_targets(user, CardData.CardSubType.BORROWED_SWORD).has(user) and (mode == "missing_weapon" or game.get_trick_targets(user, CardData.CardSubType.BORROWED_SWORD).has(first)), "F02 original Borrow first target excludes self and has weapon, caster distance irrelevant")
			await game.execute_card_on_target(first, CardData.CardSubType.BORROWED_SWORD)
			suite.check(events.size() == (0 if rejected else 1 if mode in ["refuse", "restart"] else 2), "F02 original Borrow one parent and required strike fact only, invalid before pay has none")
			suite.check(user.hand_size() == (0 if mode == "no_card" else 1 if mode == "refuse" or rejected or mode == "virtual" else 0), "F02 original Borrow physical/virtual pay and refused original weapon hand ownership")
			suite.check(tm.borrowed_sword_count_this_turn == (2 if mode == "limit" else 0 if rejected else 1) and tm.strike_count_this_turn == 1, "F02 original Borrow counts parent once, never normal strike")
			suite.check(second.hp == (9 if not rejected and mode not in ["refuse", "restart"] else 10), "F02 original Borrow uses first actor range and real damage")
			if not rejected:
				suite.check(events[0].settlement_completed == (mode != "restart") and events[0].is_virtual == (mode == "virtual") and events[0].from_hand == (mode != "virtual"), "F02 original Borrow completion and physical/virtual metadata")
				suite.check(game.deck._discard.count(events[0].card) == (0 if mode == "virtual" else 1) and (not concrete or mode == "virtual" or events[0].card == original), "F02 original Borrow preserves original entity, virtual has no physical discard")
				if mode != "restart": suite.check(finished.back() == events[0], "F02 original Borrow parent completes after required strike")
			game.card_action_committed.disconnect(commit)
			game.card_action_completed.disconnect(finish)
	# Actual target UI entry/cancel/revalidation at distant first target.
	for mode in ["cancel", "confirm", "weapon"]:
		resetter._reset(suite)
		tm.current_phase = TurnManager.Phase.PLAY
		var user: Player = game.players[0]
		var first: Player = game.players[2]
		var second: Player = game.players[3]
		user.hand.append(null)
		var original = CardBase.create(CardData.CardSubType.QINGGANG_SWORD)
		first.equip_card_to_slot("weapon", original)
		first.hand.append(null)
		game._borrowed_second_target_override = func(options): return options.find(second)
		game._borrowed_strike_override = func(_a, _t, _o): return CardData.CardSubType.STRIKE
		game._target_confirm_override = func():
			if mode == "weapon":
				first.remove_equipment("weapon")
				first.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.QINGGANG_SWORD))
			return mode != "cancel"
		await game.play_card(CardData.CardSubType.BORROWED_SWORD)
		suite.check(game._is_targeting and game._targeting_card_sub == CardData.CardSubType.BORROWED_SWORD and user.hand_size() == 1, "F02 original Borrow enters shared first-target mode without payment")
		await game._on_target_click(first)
		suite.check(user.hand_size() == (0 if mode == "confirm" else 1) and tm.borrowed_sword_count_this_turn == (1 if mode == "confirm" else 0) and second.hp == (9 if mode == "confirm" else 10), "F02 original Borrow distant first confirmation works, cancel/stale weapon never pay")
		if game._is_targeting: game._on_cancel_target_pressed()
		await suite.process_frame
	game._target_confirm_override = Callable()
	# Concrete-card click retains exact pending object, never substitutes another arbitrary card.
	for accepted in [false, true]:
		resetter._reset(suite)
		game.deck._discard.clear()
		tm.current_phase = TurnManager.Phase.PLAY
		var user: Player = game.players[0]
		var first: Player = game.players[2]
		var second: Player = game.players[3]
		var card = CardBase.create(CardData.CardSubType.BORROWED_SWORD)
		var retained = CardBase.create(CardData.CardSubType.DODGE)
		user.determined_cards.append_array([retained, card])
		user.hand.append(null)
		first.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.QINGGANG_SWORD))
		first.hand.append(null)
		game._borrowed_second_target_override = func(options): return options.find(second)
		game._borrowed_strike_override = func(_a, _t, _o): return CardData.CardSubType.STRIKE
		game._target_confirm_override = func(): return accepted
		await game._on_determined_card_clicked(card)
		suite.check(game._is_targeting and game._pending_determined_card == card and user.hand_size() == 3, "F02 original Borrow concrete click selects exact original, no premature payment")
		await game._on_target_click(first)
		suite.check(user.hand == [null] and user.determined_cards.has(retained) and user.determined_cards.has(card) == not accepted, "F02 original Borrow confirmation consumes pending original, preserves arbitrary and other concrete card")
		suite.check(game.deck._discard.count(card) == (1 if accepted else 0) and tm.borrowed_sword_count_this_turn == (1 if accepted else 0), "F02 original Borrow concrete UI confirms once or cancels before pay")
		if game._is_targeting: game._on_cancel_target_pressed()
		await suite.process_frame
	game._target_confirm_override = Callable()
	# A weapon alone is insufficient if no second target can legally receive the required strike.
	resetter._reset(suite)
	game.deck._discard.clear()
	tm.current_phase = TurnManager.Phase.PLAY
	var caster: Player = game.players[0]
	var blocked_first: Player = game.players[2]
	caster.hand.append(null)
	blocked_first.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.QINGGANG_SWORD))
	for target in game.players:
		if target != blocked_first: target.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.TENGJIA))
	suite.check(game.get_trick_targets(caster, CardData.CardSubType.BORROWED_SWORD).is_empty() and not game.can_declare_trick(caster, CardData.CardSubType.BORROWED_SWORD), "F02 original Borrow no legal second target means no first target/candidate")
	await game.execute_card_on_target(blocked_first, CardData.CardSubType.BORROWED_SWORD)
	suite.check(caster.hand_size() == 1 and tm.borrowed_sword_count_this_turn == 0 and game.deck._discard.is_empty(), "F02 original Borrow unresolvable first target rejected before payment")
	# Third use rejected before payment; counters belong to actual play actor.
	resetter._reset(suite)
	tm.current_phase = TurnManager.Phase.PLAY
	var user: Player = game.players[1]
	var first: Player = game.players[2]
	var second: Player = game.players[3]
	tm.play_actor_idx = 1
	user.hand.append_array([null, null, null])
	first.hand.append_array([null, null])
	first.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.QINGGANG_SWORD))
	game._borrowed_second_target_override = func(options): return options.find(second)
	game._borrowed_strike_override = func(_a, _t, _o): return CardData.CardSubType.STRIKE
	for n in range(3): await game.execute_card_on_target(first, CardData.CardSubType.BORROWED_SWORD)
	suite.check(user.hand_size() == 1 and first.hand_size() == 0 and second.hp == 8 and tm.borrowed_sword_count_this_turn == 2, "F02 original Borrow two uses then third rejected, no ordinary kill cap")
	tm.play_actor_idx = 0
	suite.check(tm.borrowed_sword_count_this_turn == 0, "F02 original Borrow quota not charged to granted-phase turn owner")
	game._borrowed_second_target_override = Callable()
	game._borrowed_strike_override = Callable()
	resetter._reset(suite)
	game._bank_remaining = bank
	tm.current_phase = phase
	tm.phase_changed.connect(callback)
