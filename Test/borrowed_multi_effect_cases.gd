extends RefCounted

func run(suite):
	var game: GameManager = suite.game
	var tm = game.turn_manager
	var phase = tm.current_phase
	var callback = game._on_phase_changed
	tm.phase_changed.disconnect(callback)
	var resetter = load("res://Test/prep_single_replace_cases.gd").new()
	for concrete in [false, true]:
		for mode in ["plain", "fire", "thunder", "wine", "dodge", "duplicate", "self", "no_halberd", "no_card", "wrong_card", "invalid", "restart"]:
			resetter._reset(suite)
			game.deck._discard.clear()
			tm.current_phase = TurnManager.Phase.PLAY
			tm.current_player_idx = 1
			var first: Player = game.players[1]
			var second: Player = game.players[2]
			var extra: Player = game.players[0]
			first.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.QINGGANG_SWORD if mode == "no_halberd" else CardData.CardSubType.FANGTIAN_HALBERD))
			var sub = CardData.CardSubType.FIRE_STRIKE if mode == "fire" else CardData.CardSubType.THUNDER_STRIKE if mode == "thunder" else CardData.CardSubType.STRIKE
			var resource: CardBase = CardBase.create(CardData.CardSubType.DODGE if mode == "wrong_card" else sub) if concrete else null
			if mode != "no_card":
				if concrete: first.determined_cards.append(resource)
				else: first.hand.append(null)
			var before_hand = first.hand_size()
			if mode == "wine": first.wine_stacks = 1
			if mode == "dodge": extra.hand.append(null)
			game._dodge_override = func(): return mode == "dodge"
			game._ai_response_override = func(view, kind, options): return CardData.CardSubType.DODGE if mode == "dodge" and view.actor == extra.seat_index and kind == "basic" and options.has(CardData.CardSubType.DODGE) else -1
			var events: Array[CardActionEvent] = []
			var completed: Array[CardActionEvent] = []
			var snapshots: Array = []
			var commit = func(event): events.append(event)
			var finish = func(event):
				completed.append(event)
				if event.actor_seat == first.seat_index: snapshots.append([second.hp, extra.hp])
			game.card_action_committed.connect(commit)
			game.card_action_completed.connect(finish)
			var changed: Array[bool] = [false]
			game._sacrifice_actor_override = func(_actor, target, _amount):
				if mode == "restart" and target == second and not changed[0]:
					changed[0] = true
					game.reset_game_over_state()
				return false
			# Give another actor a response card so restart injection occurs in a real damage window.
			if mode == "restart": game.players[4].hand.append(null)
			var targets: Array = [second, extra]
			if mode == "duplicate": targets = [second, second]
			elif mode == "self": targets = [second, first]
			tm.strike_count_this_turn = 1
			var result = await game._resolve_borrowed_strike(first, targets, sub, func(): return mode != "invalid")
			var refused_before_pay = mode in ["duplicate", "self", "no_halberd", "no_card", "invalid"] or (mode == "wrong_card" and concrete)
			var interrupted = mode == "restart"
			suite.check((result == game.CHOICE_INVALID) == (refused_before_pay or interrupted), "F02 borrowed multi effect valid versus rejected/technical invalid")
			suite.check(tm.strike_count_this_turn == 1 and tm.borrowed_sword_count_this_turn == 0, "F02 borrowed multi effect does not pay parent or active strike quota")
			suite.check(first.hand_size() == (before_hand if refused_before_pay else before_hand - 1), "F02 borrowed multi effect one strike payment for entire set")
			if refused_before_pay:
				suite.check(events.is_empty() and completed.is_empty() and game.deck._discard.is_empty() and second.hp == 10 and extra.hp == 10, "F02 borrowed multi illegal input never pays or damages")
			elif interrupted:
				suite.check(events.size() == 1 and not events[0].settlement_completed and completed.is_empty() and extra.hp == 10, "F02 borrowed multi restart abandons old strike and stops remaining targets")
			else:
				var damage = 2 if mode == "wine" else 1
				suite.check(second.hp == 10 - damage and extra.hp == (10 if mode == "dodge" else 10 - damage), "F02 borrowed multi uses same base damage per target, independent dodge")
				suite.check(not events.is_empty(), "F02 borrowed multi legal input commits a strike")
				if events.is_empty():
					game.card_action_committed.disconnect(commit)
					game.card_action_completed.disconnect(finish)
					continue
				suite.check(events[0].actor_seat == first.seat_index and events[0].kind == CardActionEvent.Kind.USE and events[0].sub_type == sub and events[0].settlement_completed, "F02 borrowed multi exactly original first actor strike USE")
				suite.check(events.size() == (2 if mode == "dodge" else 1) and completed.back() == events[0] and snapshots == [[second.hp, extra.hp]], "F02 borrowed multi completes one strike only after all targets and responses")
				suite.check(game.deck._discard.count(events[0].card) == 1 and (not concrete or events[0].card == resource) and first.wine_stacks == 0, "F02 borrowed multi preserves concrete entity and consumes wine once")
			game.card_action_committed.disconnect(commit)
			game.card_action_completed.disconnect(finish)
	game._sacrifice_actor_override = Callable()
	game._dodge_override = func(): return false
	resetter._reset(suite)
	tm.current_phase = phase
	tm.phase_changed.connect(callback)
