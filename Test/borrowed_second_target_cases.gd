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
	var previous_answer: Array[ChoicePromptAnswer] = [null]
	var previous_timeout: Array[Callable] = [Callable()]
	for case_name in ["confirm", "timeout", "close", "restart", "phase", "weapon", "range", "old_callback", "invalid_index", "dead", "kneel"]:
		resetter._reset(suite)
		tm.current_phase = TurnManager.Phase.PLAY
		var user: Player = game.players[0]
		var first: Player = game.players[1]
		var original = CardBase.create(CardData.CardSubType.LIANNU)
		first.equip_card_to_slot("weapon", original)
		user.hand.append(null)
		first.hand.append(null)
		game._borrowed_second_target_override = Callable()
		var offered = game._get_strike_targets(first)
		suite.check(offered.size() >= 2 and offered.has(user) and not offered.has(first), "F02b-3b-2b-1 second target from first actor's strike legality")
		var drive = func():
			suite.check(game._choice_prompt_stack.size() == 1 and game._countdown_active and game._step_remaining > 29.0, "F02b-3b-2b-1 real mandatory basic countdown")
			var pending = game._choice_prompt_stack.back()
			var buttons: Array[Button] = []
			_buttons(pending.overlay, buttons)
			suite.check(buttons.size() == offered.size() and buttons.all(func(b): return b.text != "取消"), "F02b-3b-2b-1 no cancel button, one per legal target")
			if case_name == "old_callback":
				previous_timeout[0].call()
				previous_answer[0].submit(0)
				suite.check(not pending.answer.settled and game._choice_prompt_stack.size() == 1, "F02b-3b-2b-1 old answer/timeout cannot settle current window")
			previous_answer[0] = pending.answer
			previous_timeout[0] = game._countdown_on_timeout
			if case_name == "close": pending.overlay.queue_free()
			elif case_name == "restart": game.reset_game_over_state()
			elif case_name == "phase":
				tm.current_phase = TurnManager.Phase.END
				tm.current_phase = TurnManager.Phase.PLAY
				pending.answer.submit(0)
			elif case_name == "weapon":
				first.remove_equipment("weapon")
				first.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.LIANNU))
				pending.answer.submit(0)
			elif case_name == "range":
				user.equip_card_to_slot("mount_1", CardBase.create(CardData.CardSubType.MOUNT_PLUS))
				pending.answer.submit(0)
			elif case_name == "dead":
				first.mark_dead()
				pending.answer.submit(0)
			elif case_name == "kneel":
				first.general_name = "布鲁斯·萨维奇"
				first.kneeling = true
				pending.answer.submit(0)
			elif case_name == "timeout":
				game._bank_remaining = 0.0
				game._step_remaining = 0.001
				game._process(0.01)
			else: pending.answer.submit(999 if case_name == "invalid_index" else offered.size() - 1)
		drive.call_deferred()
		var result = await game._choose_borrowed_second_target(user, first)
		var successful = case_name in ["confirm", "timeout", "old_callback"]
		suite.check(result is Player and offered.has(result) if successful else (typeof(result) == TYPE_INT and result == game.CHOICE_INVALID), "F02b-3b-2b-1 valid selection/random timeout versus technical invalidity")
		if case_name in ["confirm", "old_callback"]: suite.check(result == offered.back(), "F02b-3b-2b-1 original user chose last offered target")
		suite.check(user.hand_size() == 1 and first.hand_size() == 1 and tm.borrowed_sword_count_this_turn == 0 and game._choice_prompt_stack.is_empty() and game._countdown_active, "F02b-3b-2b-1 chooser never pays or moves weapon; wait released and normal PLAY countdown restored")
		if case_name != "weapon": suite.check(first.get_equipment_card("weapon") == original, "F02b-3b-2b-1 chooser preserves original weapon")
		await suite.process_frame
	# No playable targets/weapon: precondition fails without an empty timed mandatory prompt.
	resetter._reset(suite)
	game._borrowed_second_target_override = Callable()
	suite.check(await game._choose_borrowed_second_target(game.players[0], game.players[1]) == game.CHOICE_INVALID and game._choice_prompt_stack.is_empty(), "F02b-3b-2b-1 missing weapon has no selection window")
	# AI/override branch shares legality and doesn't grant original caster/first-target privileges.
	var first: Player = game.players[1]
	first.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.LIANNU))
	game._ai_response_override = func(_view, kind, options): return options.back() if kind == "borrowed_second_target" else -1
	var offered = game._get_strike_targets(first)
	suite.check(await game._choose_borrowed_second_target(game.players[2], first) == offered.back(), "F02b-3b-2b-1 AI original caster selects from legal first-target range")
	game._borrowed_second_target_override = func(_options): return game.CHOICE_INVALID
	suite.check(await game._choose_borrowed_second_target(game.players[0], first) == game.CHOICE_INVALID, "F02b-3b-2b-1 explicit invalid never becomes random")
	game._borrowed_second_target_override = Callable()
	resetter._reset(suite)
	game._bank_remaining = bank
	tm.current_phase = phase
	tm.phase_changed.connect(callback)
