extends RefCounted

func _buttons(node, out: Array[Button]):
	if node is Button: out.append(node)
	for child in node.get_children(): _buttons(child, out)

func run(suite):
	var game: GameManager = suite.game
	var tm = game.turn_manager
	var phase = tm.current_phase
	var bank = game._bank_remaining
	var callback = game._on_phase_changed
	tm.phase_changed.disconnect(callback)
	var resetter = load("res://Test/prep_single_replace_cases.gd").new()
	var old_answer: Array[ChoicePromptAnswer] = [null]
	var old_timeout: Array[Callable] = [Callable()]
	var old_toggle: Array[Button] = [null]
	for concrete in [false, true]:
		for mode in ["confirm", "timeout", "uncheck_timeout", "fixed_only", "close", "restart", "phase", "weapon", "hand", "range", "old_callback"]:
			resetter._reset(suite)
			tm.current_phase = TurnManager.Phase.PLAY
			var first: Player = game.players[0]
			var second: Player = game.players[1]
			var extra: Player = game.players[4]
			var weapon = CardBase.create(CardData.CardSubType.FANGTIAN_HALBERD)
			first.equip_card_to_slot("weapon", weapon)
			if concrete: first.determined_cards.append(CardBase.create(CardData.CardSubType.STRIKE))
			else: first.hand.append(null)
			game._borrowed_extra_targets_override = Callable()
			var drive = func():
				var pending = game._choice_prompt_stack.back()
				var buttons: Array[Button] = []
				_buttons(pending.overlay, buttons)
				var fixed: Button
				var toggle: Button
				var confirm: Button
				for b in buttons:
					if b.text == second.player_name: fixed = b
					elif b.text == extra.player_name: toggle = b
					elif b.text == "确认出杀": confirm = b
				suite.check(fixed != null and fixed.disabled and fixed.button_pressed and toggle != null and confirm != null and buttons.all(func(b): return b.text != "取消"), "F02 Q21 fixed target locked, legal extras and confirmation only")
				suite.check(game._countdown_active and game._step_remaining > 29.0, "F02 Q21 real basic countdown")
				if mode == "old_callback":
					old_timeout[0].call()
					old_answer[0].submit(0)
					if is_instance_valid(old_toggle[0]): old_toggle[0].toggled.emit(true)
					suite.check(not pending.answer.settled, "F02 Q21 previous timeout/answer/toggle cannot submit new selection")
				old_answer[0] = pending.answer
				old_timeout[0] = game._countdown_on_timeout
				old_toggle[0] = toggle
				if mode != "fixed_only": toggle.button_pressed = true
				if mode == "uncheck_timeout": toggle.button_pressed = false
				if mode == "close": pending.overlay.queue_free()
				elif mode == "restart": game.reset_game_over_state()
				elif mode == "phase":
					tm.current_phase = TurnManager.Phase.END
					tm.current_phase = TurnManager.Phase.PLAY
					confirm.pressed.emit()
				elif mode == "weapon":
					first.remove_equipment("weapon")
					first.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.FANGTIAN_HALBERD))
					confirm.pressed.emit()
				elif mode == "hand":
					first.hand.append(null)
					confirm.pressed.emit()
				elif mode == "range":
					extra.equip_card_to_slot("mount_1", CardBase.create(CardData.CardSubType.MOUNT_PLUS))
					confirm.pressed.emit()
				elif mode in ["timeout", "uncheck_timeout"]:
					game._bank_remaining = 0.0
					game._step_remaining = 0.001
					game._process(0.01)
				else: confirm.pressed.emit()
			drive.call_deferred()
			var result = await game._choose_borrowed_strike_targets(first, second, CardData.CardSubType.STRIKE, func(): return true)
			var ok = mode in ["confirm", "timeout", "uncheck_timeout", "fixed_only", "old_callback"]
			suite.check(result == ([second] if mode in ["fixed_only", "uncheck_timeout"] else [second, extra]) if ok else typeof(result) == TYPE_INT and result == game.CHOICE_INVALID, "F02 Q21 confirmation/timeout uses current selected set, technical invalid never attacks")
			suite.check(first.hand_size() == (2 if mode == "hand" else 1) and tm.strike_count_this_turn == 0 and tm.borrowed_sword_count_this_turn == 0 and game._choice_prompt_stack.is_empty(), "F02 Q21 chooser no payment/quota, window released")
			await suite.process_frame
	# Actual paid Borrow -> selected strike -> real extra window -> one payment and per-target effects.
	for concrete in [false, true]:
		for mode in ["confirm", "timeout", "refuse", "close"]:
			resetter._reset(suite)
			game.deck._discard.clear()
			tm.current_phase = TurnManager.Phase.PLAY
			var user: Player = game.players[2]
			var first: Player = game.players[0]
			var second: Player = game.players[1]
			var extra: Player = game.players[4]
			var weapon = CardBase.create(CardData.CardSubType.FANGTIAN_HALBERD)
			first.equip_card_to_slot("weapon", weapon)
			var strike = CardBase.create(CardData.CardSubType.FIRE_STRIKE) if concrete else null
			if concrete: first.determined_cards.append(strike)
			else: first.hand.append(null)
			first.wine_stacks = 1
			game._borrowed_second_target_override = func(options): return options.find(second)
			game._borrowed_strike_override = func(_p, _t, _options): return -1 if mode == "refuse" else CardData.CardSubType.FIRE_STRIKE
			game._nullify_override = func(): return false
			game._ai_response_override = func(_v, _k, _o): return -1
			game._dodge_override = func(): return false
			if mode != "refuse":
				var drive = func():
					var pending = game._choice_prompt_stack.back()
					var buttons: Array[Button] = []
					_buttons(pending.overlay, buttons)
					for b in buttons:
						if b.text == extra.player_name: b.button_pressed = true
					if mode == "close": pending.overlay.queue_free()
					elif mode == "timeout": pending.answer.submit(-1)
					else:
						for b in buttons:
							if b.text == "确认出杀": b.pressed.emit()
				drive.call_deferred()
			if concrete: user.determined_cards.append(CardBase.create(CardData.CardSubType.BORROWED_SWORD))
			else: user.hand.append(null)
			var parent_card = HandPayment.take_card(user, CardData.CardSubType.BORROWED_SWORD)
			game.deck.discard(parent_card)
			var completed: Array[CardActionEvent] = []
			var events: Array[CardActionEvent] = []
			var commit = func(e): events.append(e)
			var finish = func(e): completed.append(e)
			game.card_action_committed.connect(commit)
			game.card_action_completed.connect(finish)
			var parent = game._record_card_action(user, parent_card, CardActionEvent.Kind.USE, true, false)
			await game._resolve_paid_borrowed_sword(user, first, [parent])
			var killed = mode in ["confirm", "timeout"]
			suite.check(second.hp == (8 if killed else 10) and extra.hp == (8 if killed else 10), "F02 Q21 actual Borrow causes equal wine/fire damage to fixed and selected extra")
			suite.check(first.hand_size() == (0 if killed else 1) and first.wine_stacks == (0 if killed else 1) and tm.strike_count_this_turn == 0 and tm.borrowed_sword_count_this_turn == 1, "F02 Q21 whole borrowed kill one payment/wine, no normal strike quota")
			suite.check(game.deck._discard.count(parent_card) == 1 and parent.settlement_completed == (mode != "close") and events.size() == (2 if killed else 1), "F02 Q21 original parent paid once, technical closure abandons, strike USE once")
			if killed:
				suite.check(completed == [events[1], parent] and game.deck._discard.count(events[1].card) == 1 and (not concrete or events[1].card == strike), "F02 Q21 child completion after both targets, then parent; original concrete strike")
			else:
				suite.check(user.determined_cards.has(weapon) if mode == "refuse" else first.get_equipment_card("weapon") == weapon, "F02 Q21 refusal transfers original weapon, technical close never transfers")
			game.card_action_committed.disconnect(commit)
			game.card_action_completed.disconnect(finish)
			await suite.process_frame
	# AI legality and untrusted selections: no last-handcard/three-target restriction.
	resetter._reset(suite)
	var actor: Player = game.players[1]
	var fixed: Player = game.players[2]
	actor.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.FANGTIAN_HALBERD))
	actor.equip_card_to_slot("mount_1", CardBase.create(CardData.CardSubType.MOUNT_MINUS))
	actor.hand.append_array([null, null])
	game._borrowed_extra_targets_override = Callable()
	suite.check(await game._choose_borrowed_strike_targets(actor, fixed, CardData.CardSubType.STRIKE, func(): return true) == [fixed], "F02 Q21 AI conservatively chooses fixed target without human window")
	var legal = game._get_strike_targets(actor)
	suite.check(legal.size() == 4, "F02 Q21 four legally reachable targets in custom halberd fixture")
	game._borrowed_extra_targets_override = func(_actor, _fixed, options): return options
	var all_targets = await game._choose_borrowed_strike_targets(actor, fixed, CardData.CardSubType.STRIKE, func(): return true)
	suite.check(all_targets is Array and all_targets.size() == 4 and all_targets[0] == fixed and actor.hand_size() == 2, "F02 Q21 custom halberd has neither last-card nor three-target cap")
	for bad in [[actor], [fixed, fixed], [game.players[3]], game.CHOICE_INVALID]:
		game._borrowed_extra_targets_override = func(_actor, _fixed, _options): return bad
		suite.check(await game._choose_borrowed_strike_targets(actor, fixed, CardData.CardSubType.STRIKE, func(): return true) == game.CHOICE_INVALID and actor.hand_size() == 2, "F02 Q21 missing fixed/self/duplicate/explicit invalid rejected without payment")
	game._borrowed_extra_targets_override = Callable()
	game._borrowed_second_target_override = Callable()
	game._borrowed_strike_override = Callable()
	resetter._reset(suite)
	game._bank_remaining = bank
	tm.current_phase = phase
	tm.phase_changed.connect(callback)
