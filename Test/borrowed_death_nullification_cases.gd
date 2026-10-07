extends RefCounted

func run(suite):
	var game: GameManager = suite.game
	var tm = game.turn_manager
	var phase = tm.current_phase
	var mode_before = game.game_mode
	var identities: Array = []
	for player in game.players: identities.append(player.identity)
	var callback = game._on_phase_changed
	tm.phase_changed.disconnect(callback)
	game.game_mode = GameManager.MODE_CLASSIC_IDENTITY
	var resetter = load("res://Test/prep_single_replace_cases.gd").new()
	for concrete in [false, true]:
		for case_name in ["odd", "even_refuse", "even_kill", "even_empty", "invalid_after_cost", "restart_cost", "original_odd", "original_even_refuse", "original_even_kill"]:
			var mode: String = case_name.trim_prefix("original_")
			resetter._reset(suite)
			game.deck._discard.clear()
			tm.current_phase = TurnManager.Phase.PLAY
			var user: Player = game.players[0]
			var first: Player = game.players[1]
			var second: Player = game.players[2]
			for seat in range(5): game.players[seat].identity = ["反贼", "主公", "忠臣", "反贼", "内奸"][seat]
			user.general_name = "安普提·斯丢皮得"
			user.hp = 1
			var weapon = CardBase.create(CardData.CardSubType.QINGGANG_SWORD)
			first.equip_card_to_slot("weapon", weapon)
			if mode != "even_empty": first.hand.append(null)
			var counter = CardBase.create(CardData.CardSubType.NULLIFICATION)
			if mode in ["even_refuse", "even_kill", "even_empty"]: game.players[4].determined_cards.append(counter)
			game._borrowed_second_target_override = func(options): return options.find(second)
			var choices: Array[int] = [0]
			game._borrowed_strike_override = func(_actor, _target, _options):
				choices[0] += 1
				return CardData.CardSubType.STRIKE if mode == "even_kill" else -1
			game._nullify_override = func(): return user.is_alive()
			game._yes_ah_override = func(): return "skill"
			game._sacrifice_override = func(): return false
			game._sacrifice_actor_override = Callable()
			game._dodge_override = func(): return false
			game._rps_override = func(actor): return game.RPS_ROCK if actor == user else game.RPS_PAPER
			var valid: Array[bool] = [true]
			game._ai_response_override = func(view, kind, options):
				if mode == "restart_cost" and kind == "rescue": game.reset_game_over_state()
				if kind == "nullification":
					if mode == "invalid_after_cost": valid[0] = false
					if view.actor == 4 and options.has(CardData.CardSubType.NULLIFICATION) and mode in ["even_refuse", "even_kill", "even_empty"]: return CardData.CardSubType.NULLIFICATION
				return -1
			# Cost rescue goes through the real dying window. No automatic rescue or weapon-save fixture.
			game._rescue_choice_override = func(_rescuer, _victim, _options):
				if mode == "restart_cost": game.reset_game_over_state()
				return -1
			var parent = CardBase.create(CardData.CardSubType.BORROWED_SWORD) if concrete else null
			if concrete: user.determined_cards.append(parent)
			else: user.hand.append(null)
			var spare = CardBase.create(CardData.CardSubType.DODGE)
			user.determined_cards.append(spare)
			var actual: CardBase
			var events: Array[CardActionEvent] = []
			var completed: Array[CardActionEvent] = []
			var commit = func(event): events.append(event)
			var finish = func(event): completed.append(event)
			game.card_action_committed.connect(commit)
			game.card_action_completed.connect(finish)
			var action: CardActionEvent
			if case_name.begins_with("original_"):
				await game.execute_card_on_target(first, CardData.CardSubType.BORROWED_SWORD)
				suite.check(not events.is_empty(), "F02 Q20 original entry commits actual paid Borrow before lethal nullification")
				if events.is_empty():
					game.card_action_committed.disconnect(commit)
					game.card_action_completed.disconnect(finish)
					continue
				action = events[0]
				actual = action.card
			else:
				actual = HandPayment.take_card(user, CardData.CardSubType.BORROWED_SWORD)
				game.deck.discard(actual)
				action = game._record_card_action(user, actual, CardActionEvent.Kind.USE, true, false)
				await game._resolve_paid_borrowed_sword(user, first, [action], func(): return valid[0])
			var invalid = mode in ["invalid_after_cost", "restart_cost"]
			suite.check((user.is_dying() and not user.is_dead() and user.hand_size() == 1 if mode == "restart_cost" else user.is_dead() and user.hand_size() == 0) and not game._game_over, "F02 Q20 final death clears cards; technical restart never fabricates final death")
			suite.check(actual.sub_type == CardData.CardSubType.BORROWED_SWORD and game.deck._discard.count(actual) == 1 and (not concrete or actual == parent) and game.deck._discard.count(spare) == (0 if mode == "restart_cost" else 1), "F02 Q20 original paid borrow and final death discard preserve physical originals")
			suite.check(first.get_equipment_card("weapon") == weapon and not game.deck._discard.has(weapon) and not user.determined_cards.has(weapon), "F02 Q20 dead caster never receives/discards weapon, first target keeps equipped original")
			suite.check(second.hp == (9 if mode == "even_kill" else 10) and choices[0] == (1 if mode in ["even_refuse", "even_kill"] else 0), "F02 Q20 odd cancels, even asks strike, empty refuses without choosing")
			suite.check(action.settlement_completed == not invalid and tm.borrowed_sword_count_this_turn == 1 and tm.strike_count_this_turn == 0, "F02 Q20 valid completion versus technical abandonment, only borrowed quota")
			if not invalid:
				suite.check(events.size() == (2 if mode == "odd" else 4 if mode == "even_kill" else 3) and events[1].is_virtual and not events[1].from_hand and events[1].sub_type == CardData.CardSubType.NULLIFICATION, "F02 Q20 lethal virtual nullification is real use fact, no invented physical response")
				suite.check(events[1].settlement_completed and not game.deck._discard.has(events[1].card) and completed.back() == action, "F02 Q20 virtual response completed in whole chain before parent")
				if mode != "odd": suite.check(game.deck._discard.count(counter) == 1 and events[2].card == counter and events[2].settlement_completed, "F02 Q20 real counter-nullification retains original card and chain completion")
			else:
				suite.check(events.size() == (1 if mode == "restart_cost" else 2) and completed.is_empty(), "F02 Q20 cost restart creates no response, later invalidity abandons already real response without completion")
			game.card_action_committed.disconnect(commit)
			game.card_action_completed.disconnect(finish)
	game.game_mode = mode_before
	for seat in range(game.players.size()): game.players[seat].identity = identities[seat]
	game._borrowed_second_target_override = Callable()
	game._borrowed_strike_override = Callable()
	game._yes_ah_override = Callable()
	game._rps_override = Callable()
	resetter._reset(suite)
	tm.current_phase = phase
	tm.phase_changed.connect(callback)
