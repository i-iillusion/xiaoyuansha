extends RefCounted

func _buttons(node, result: Array[Button]):
	if node is Button: result.append(node)
	for child in node.get_children(): _buttons(child, result)

func run(suite):
	var game: GameManager = suite.game
	var tm = game.turn_manager
	var phase = tm.current_phase
	var bank = game._bank_remaining
	var callback = game._on_phase_changed
	tm.phase_changed.disconnect(callback)
	var resetter = load("res://Test/prep_single_replace_cases.gd").new()
	for concrete in [false, true]:
		for mode in ["normal", "fire", "thunder", "wine", "dodge", "refuse", "empty", "nullified", "invalid", "restart", "limit", "own_turn"]:
			resetter._reset(suite)
			game.deck._discard.clear()
			tm.current_phase = TurnManager.Phase.PLAY
			tm.current_player_idx = 1
			var user: Player = game.players[1]
			var first: Player = game.players[2]
			var second: Player = game.players[3]
			var weapon = CardBase.create(CardData.CardSubType.QINGGANG_SWORD)
			first.equip_card_to_slot("weapon", weapon)
			var sub = CardData.CardSubType.STRIKE
			if mode == "fire": sub = CardData.CardSubType.FIRE_STRIKE
			elif mode == "thunder": sub = CardData.CardSubType.THUNDER_STRIKE
			var required: CardBase = CardBase.create(sub) if concrete else null
			if mode != "empty":
				if concrete: first.determined_cards.append(required)
				else: first.hand.append(null)
			if mode == "wine": first.wine_stacks = 1
			if mode == "own_turn":
				tm.current_player_idx = 2
				tm.play_actor_idx = 1
			tm.strike_count_this_turn = 1
			if mode == "limit": tm.borrowed_sword_count_this_turn = 2
			if mode == "dodge": second.hand.append(null)
			game._dodge_override = func(): return mode == "dodge"
			game._ai_response_override = func(view, kind, options):
				if kind == "dodge" and mode == "dodge": return CardData.CardSubType.DODGE
				if kind == "nullification" and mode == "nullified" and view.actor == 4 and options.has(CardData.CardSubType.NULLIFICATION): return CardData.CardSubType.NULLIFICATION
				return -1
			if mode == "nullified": game.players[4].determined_cards.append(CardBase.create(CardData.CardSubType.NULLIFICATION))
			game._borrowed_second_target_override = func(options): return options.find(second)
			game._borrowed_strike_override = func(actor, target, options):
				suite.check(actor == first and target == second and options.has(sub), "F02 paid borrow first actor chooses matching strike")
				if mode == "invalid": return game.CHOICE_INVALID
				if mode == "restart":
					game.reset_game_over_state()
					return sub
				return -1 if mode == "refuse" else sub
			var events: Array[CardActionEvent] = []
			var finished: Array[CardActionEvent] = []
			var commit = func(event): events.append(event)
			var finish = func(event): finished.append(event)
			game.card_action_committed.connect(commit)
			game.card_action_completed.connect(finish)
			if concrete: user.determined_cards.append(CardBase.create(CardData.CardSubType.BORROWED_SWORD))
			else: user.hand.append(null)
			var parent = HandPayment.take_card(user, CardData.CardSubType.BORROWED_SWORD)
			game.deck.discard(parent)
			var action = game._record_card_action(user, parent, CardActionEvent.Kind.USE, true, false)
			await game._resolve_paid_borrowed_sword(user, first, [action])
			var invalid = mode in ["invalid", "restart", "limit"]
			var struck = mode in ["normal", "fire", "thunder", "wine", "dodge", "own_turn"]
			var handed = mode in ["refuse", "empty"]
			suite.check(parent.sub_type == CardData.CardSubType.BORROWED_SWORD and game.deck._discard.count(parent) == 1, "F02 paid borrow original entity and one payment preserved")
			suite.check(tm.borrowed_sword_count_this_turn == (2 if mode == "limit" else 1) and tm.strike_count_this_turn == 1, "F02 paid borrow only final card quota, required strike does not consume ordinary quota")
			suite.check(second.hp == (8 if mode == "wine" else 9 if struck and mode != "dodge" else 10), "F02 paid borrow damage/dodge/nullification/refusal isolation")
			suite.check(action.settlement_completed == not invalid, "F02 paid borrow completion versus technical abandonment")
			suite.check(events.size() == (3 if mode == "dodge" else 2 if mode == "nullified" or struck else 1), "F02 paid borrow no invented extra use facts")
			if struck:
				suite.check(events[1].actor_seat == first.seat_index and events[1].sub_type == sub and events[1].kind == CardActionEvent.Kind.USE, "F02 paid borrow actual strike user and original strike type")
				suite.check(finished == ([events[2], events[1], action] if mode == "dodge" else [events[1], action]) and events[1].settlement_completed, "F02 paid borrow completes whole child strike before parent")
				suite.check(first.hand_size() == 0 and game.deck._discard.count(events[1].card) == 1 and (not concrete or events[1].card == required), "F02 paid borrow strike paid once, concrete original resource retained")
			suite.check(user.determined_cards.has(weapon) == handed and (first.get_equipment_card("weapon") == weapon) == not handed, "F02 paid borrow original weapon goes to caster hand only on refusal/no strike")
			suite.check(user.get_weapon() == -1 and game._choice_prompt_stack.is_empty(), "F02 paid borrow never auto-equips received weapon or leaks prompt")
			game.card_action_committed.disconnect(commit)
			game.card_action_completed.disconnect(finish)
	# Real required-strike prompt: selecting type/refusal/timeout versus technical closing.
	for mode in ["confirm", "refuse", "timeout", "close", "phase", "hand_changed"]:
		resetter._reset(suite)
		tm.current_phase = TurnManager.Phase.PLAY
		var first: Player = game.players[0]
		var second: Player = game.players[1]
		first.hand.append(null)
		game._borrowed_strike_override = Callable()
		var drive = func():
			var pending = game._choice_prompt_stack.back()
			var buttons: Array[Button] = []
			_buttons(pending.overlay, buttons)
			suite.check(buttons.size() == 4 and buttons.all(func(b): return b.text != "取消") and game._countdown_active, "F02 required strike real three type choices plus explicit refusal and basic clock")
			if mode == "close": pending.overlay.queue_free()
			elif mode == "phase":
				tm.current_phase = TurnManager.Phase.END
				tm.current_phase = TurnManager.Phase.PLAY
				pending.answer.submit(0)
			elif mode == "hand_changed":
				first.hand.append(null)
				pending.answer.submit(0)
			elif mode == "timeout":
				game._bank_remaining = 0.0
				game._step_remaining = 0.001
				game._process(0.01)
			else: pending.answer.submit(1 if mode == "confirm" else 3)
		drive.call_deferred()
		var result = await game._choose_borrowed_strike(first, second, func(): return true)
		suite.check(result == (CardData.CardSubType.FIRE_STRIKE if mode == "confirm" else -1 if mode in ["refuse", "timeout"] else game.CHOICE_INVALID), "F02 required strike real selection/refusal/timeout/invalid distinction")
		suite.check(first.hand_size() == (2 if mode == "hand_changed" else 1) and game._choice_prompt_stack.is_empty(), "F02 required strike selector never pays and releases wait")
		await suite.process_frame
	game._borrowed_second_target_override = Callable()
	game._borrowed_strike_override = Callable()
	game._dodge_override = func(): return false
	resetter._reset(suite)
	game._bank_remaining = bank
	tm.current_phase = phase
	tm.phase_changed.connect(callback)
