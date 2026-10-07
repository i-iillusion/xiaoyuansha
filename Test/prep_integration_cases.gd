extends RefCounted

func run(suite):
	var game: GameManager = suite.game
	var tm = game.turn_manager
	var phase = tm.current_phase
	var bank = game._bank_remaining
	var mode_before = game.game_mode
	var callback = game._on_phase_changed
	tm.phase_changed.disconnect(callback)
	var resetter = load("res://Test/prep_single_replace_cases.gd").new()
	var previous: Array[ChoicePromptAnswer] = []
	var previous_timeout: Array[Callable] = []
	# A real Leo popup must not claim ownership of the caster's later second-target choice.
	for mode in ["confirm", "timeout", "close", "restart", "weapon", "old_callback"]:
		resetter._reset(suite)
		game.deck._discard.clear()
		tm.current_phase = TurnManager.Phase.PLAY
		tm.current_player_idx = 1
		var leo: Player = game.players[0]
		var user: Player = game.players[1]
		var first: Player = game.players[2]
		var second: Player = game.players[3]
		leo.general_name = "里奥·普利威尔"
		leo.prep_tokens = 1
		user.hand.append(null)
		first.hand.append(null)
		first.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.QINGGANG_SWORD))
		game._prep_replace_override = Callable()
		game._borrowed_second_target_override = Callable()
		game._borrowed_strike_override = Callable()
		var seconds: Array[int] = [0]
		game._ai_response_override = func(view, kind, options):
			if kind == "borrowed_second_target":
				seconds[0] += 1
				suite.check(view.actor == user.seat_index and leo.prep_tokens == 0 and options.has(second.seat_index), "F02 integration second target chosen by original caster AI, not Leo")
				return second.seat_index
			if kind == "borrowed_strike": return CardData.CardSubType.STRIKE
			return -1
		var events: Array[CardActionEvent] = []
		var commit = func(e): events.append(e)
		game.card_action_committed.connect(commit)
		var drive = func():
			suite.check(game._choice_prompt_stack.size() == 1 and game._countdown_active and events.size() == 1 and not events[0].settlement_completed and leo.prep_tokens == 1, "F02 integration real timed prep popup after single original payment")
			var pending = game._choice_prompt_stack.back()
			var buttons = pending.overlay.find_children("*", "Button", true, false)
			var borrow_buttons = buttons.filter(func(b): return b.text == "更换为借刀杀人")
			suite.check(borrow_buttons.size() == 1 and not buttons.any(func(b): return b.text == "更换为舍己为人"), "F02 integration real Borrow candidate, no sacrifice")
			if mode == "old_callback":
				previous.back().submit(0)
				previous_timeout.back().call()
				suite.check(not pending.answer.settled and leo.prep_tokens == 1, "F02 integration old prep answer/timeout cannot settle new popup")
			previous.append(pending.answer)
			previous_timeout.append(game._countdown_on_timeout)
			if mode == "close": pending.overlay.queue_free()
			elif mode == "restart": game.reset_game_over_state()
			elif mode == "timeout": game._countdown_on_timeout.call()
			else:
				if mode == "weapon": first.remove_equipment("weapon")
				borrow_buttons[0].pressed.emit()
		drive.call_deferred()
		await game.execute_card_on_target(first, CardData.CardSubType.DUEL)
		game.card_action_committed.disconnect(commit)
		var borrowed = mode in ["confirm", "old_callback"]
		var invalid = mode in ["close", "restart"]
		suite.check(seconds[0] == (1 if borrowed else 0) and tm.borrowed_sword_count_this_turn == (1 if borrowed else 0) and tm.duel_count_this_turn == (0 if borrowed or invalid else 1), "F02 integration prep confirm/timeout/fresh legality final category")
		suite.check(first.hp == (9 if mode in ["timeout", "weapon"] else 10) and second.hp == (9 if borrowed else 10) and leo.prep_tokens == (0 if borrowed else 1), "F02 integration timeout retains mark/original duel; invalid no effect")
		suite.check(events[0].settlement_completed == not invalid and game._pending_card_actions.is_empty(), "F02 integration original parent completed or explicitly abandoned")
		await suite.process_frame
		suite.check(game._choice_prompt_stack.is_empty(), "F02 integration real prep popup released")
	# Original human caster pays a concrete Duel; AI Leo replaces it and human chooses second.
	for mode in ["confirm", "timeout", "close", "phase", "weapon", "old_callback"]:
		resetter._reset(suite)
		game.deck._discard.clear()
		tm.current_phase = TurnManager.Phase.PLAY
		var user: Player = game.players[0]
		var leo: Player = game.players[1]
		var first: Player = game.players[2]
		var second: Player = game.players[3]
		var original = CardBase.create(CardData.CardSubType.DUEL)
		user.determined_cards.append(original)
		leo.general_name = "里奥·普利威尔"
		leo.prep_tokens = 1
		first.hand.append(null)
		first.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.QINGGANG_SWORD))
		game._prep_replace_override = Callable()
		game._borrowed_second_target_override = Callable()
		game._borrowed_strike_override = Callable()
		game._ai_response_override = func(view, kind, options):
			if kind == "prep_replace":
				suite.check(view.actor == leo.seat_index and options.has(CardData.CardSubType.BORROWED_SWORD), "F02 integration AI Leo uses common legal Borrow candidate")
				return CardData.CardSubType.BORROWED_SWORD
			if kind == "borrowed_strike": return CardData.CardSubType.STRIKE
			return -1
		var offered = game._get_strike_targets(first)
		var events: Array[CardActionEvent] = []
		var commit = func(e): events.append(e)
		game.card_action_committed.connect(commit)
		var drive = func():
			var pending = game._choice_prompt_stack.back()
			var buttons = pending.overlay.find_children("*", "Button", true, false)
			suite.check(buttons.size() == offered.size() and not buttons.any(func(b): return b.text == "取消") and leo.prep_tokens == 0 and user.hand_size() == 0 and game.deck._discard.count(original) == 1, "F02 integration real mandatory second window after concrete payment and prep fee")
			if mode == "old_callback":
				previous.back().submit(0)
				previous_timeout.back().call()
				suite.check(not pending.answer.settled, "F02 integration old second answer cannot settle current window")
			previous.append(pending.answer)
			previous_timeout.append(game._countdown_on_timeout)
			if mode == "close": pending.overlay.queue_free()
			elif mode == "timeout": game._countdown_on_timeout.call()
			else:
				if mode == "phase":
					tm.current_phase = TurnManager.Phase.END
					tm.current_phase = TurnManager.Phase.PLAY
				if mode == "weapon":
					first.remove_equipment("weapon")
					first.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.QINGGANG_SWORD))
				buttons[offered.find(second)].pressed.emit()
		drive.call_deferred()
		await game.execute_card_on_target(first, CardData.CardSubType.DUEL)
		game.card_action_committed.disconnect(commit)
		var valid = mode in ["confirm", "timeout", "old_callback"]
		suite.check(events.size() == (2 if valid else 1) and events[0].card == original and events[0].settlement_completed == valid and game.deck._discard.count(original) == 1, "F02 integration real second answer never repays/renames original concrete Duel")
		suite.check(first.hand_size() == (0 if valid else 1) and tm.borrowed_sword_count_this_turn == 1 and tm.duel_count_this_turn == 0 and tm.strike_count_this_turn == 0, "F02 integration invalid second preserves parent fees/quota, never pays required strike")
		if mode in ["confirm", "old_callback"]: suite.check(second.hp == 9 and user.hp == 10, "F02 integration human original caster chose second, not Leo/default target")
		if mode == "timeout": suite.check(offered.any(func(p): return p.hp == 9), "F02 integration second timeout randomly uses one legal target")
		await suite.process_frame
		suite.check(game._choice_prompt_stack.is_empty() and game._pending_card_actions.is_empty(), "F02 integration second answer releases windows and receipts")
	# One parent + two nullifications: marks appear once at whole chain end, then parent end.
	resetter._reset(suite)
	game.deck._discard.clear()
	tm.current_phase = TurnManager.Phase.PLAY
	var user: Player = game.players[0]
	var first: Player = game.players[2]
	var second: Player = game.players[3]
	user.general_name = "里奥·普利威尔"
	user.prep_tokens = 1
	user.hand.append(null)
	var null_cards: Array[CardBase] = [CardBase.create(CardData.CardSubType.NULLIFICATION), CardBase.create(CardData.CardSubType.NULLIFICATION)]
	user.determined_cards.append_array(null_cards)
	first.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.QINGGANG_SWORD))
	game._prep_replace_override = func(_l, _u, _t, _s, _o): return CardData.CardSubType.BORROWED_SWORD
	game._borrowed_second_target_override = func(options): return options.find(second)
	game._nullify_override = func():
		suite.check(user.prep_tokens == 0, "F02 integration every null chain query precedes batch marker grant")
		return HandPayment.has_card(user, CardData.CardSubType.NULLIFICATION)
	var events: Array[CardActionEvent] = []
	var marks: Array[int] = []
	var commit = func(e): events.append(e)
	var finish = func(_e): marks.append(user.prep_tokens)
	game.card_action_committed.connect(commit)
	game.card_action_completed.connect(finish)
	await game.execute_card_on_target(first, CardData.CardSubType.DUEL)
	game.card_action_committed.disconnect(commit)
	game.card_action_completed.disconnect(finish)
	suite.check(events.size() == 3 and marks == [2, 2, 3] and user.prep_tokens == 3 and events[0].settlement_completed, "F02 integration complete null chain grants two together, parent grants exactly one later")
	suite.check(null_cards.all(func(c): return game.deck._discard.count(c) == 1) and user.determined_cards.size() == 1 and first.equipment.is_empty(), "F02 integration even chain allows refusal, physical originals move once")
	# Legal Fangtian extra target: first actor dies to real thorn counter, remainder is sourceless.
	var old_scheduler = game.rule_scheduler
	for concrete in [false, true]:
		resetter._reset(suite)
		game.deck._discard.clear()
		game.game_mode = GameManager.MODE_FREE_FOR_ALL
		tm.current_phase = TurnManager.Phase.PLAY
		tm.current_player_idx = 1
		var caster: Player = game.players[1]
		var actual: Player = game.players[2]
		var fixed: Player = game.players[3]
		var extra: Player = game.players[1]
		game.players[0].general_name = "里奥·普利威尔"
		game.players[0].prep_tokens = 1
		var parent = CardBase.create(CardData.CardSubType.DUEL) if concrete else null
		var kill = CardBase.create(CardData.CardSubType.STRIKE) if concrete else null
		if concrete:
			caster.determined_cards.append(parent)
			actual.determined_cards.append(kill)
		else:
			caster.hand.append(null)
			actual.hand.append(null)
		actual.hp = 1
		var weapon = CardBase.create(CardData.CardSubType.FANGTIAN_HALBERD)
		actual.equip_card_to_slot("weapon", weapon)
		fixed.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.THORN_ARMOR))
		game._prep_replace_override = func(_l, _u, _t, _s, _o): return CardData.CardSubType.BORROWED_SWORD
		game._borrowed_second_target_override = func(options): return options.find(fixed)
		game._borrowed_strike_override = func(_a, _t, _o): return CardData.CardSubType.STRIKE
		game._borrowed_extra_targets_override = func(_a, _t, _o): return [fixed, extra]
		game._rps_override = func(p): return game.RPS_ROCK if p == fixed else game.RPS_SCISSORS
		var observer = load("res://Test/prep_damage_observer.gd").new()
		game.rule_scheduler = observer
		var actions: Array[CardActionEvent] = []
		var collect = func(e): actions.append(e)
		game.card_action_committed.connect(collect)
		await game.execute_card_on_target(actual, CardData.CardSubType.DUEL)
		game.card_action_committed.disconnect(collect)
		suite.check(actual.is_dead() and fixed.hp == 9 and extra.hp == 9 and not game._game_over, "F02 integration real thorn kills required strike actor; legal remaining Fangtian target still receives damage")
		suite.check(observer.observed.any(func(r): return r.target == extra and r.source == null and r.committed), "F02 integration remaining target commits genuine sourceless DamageRecord")
		suite.check(actions.size() == 2 and actions.all(func(e): return e.settlement_completed) and game.deck._discard.count(weapon) == 1 and (not concrete or actions[0].card == parent and actions[1].card == kill), "F02 integration parent/child both complete after real death; original weapon/kill/parent never copied")
		suite.check(tm.borrowed_sword_count_this_turn == 1 and tm.strike_count_this_turn == 0 and game._pending_card_actions.is_empty(), "F02 integration death doesn't fake refusal/active strike charge or leak receipt")
		game.rule_scheduler = old_scheduler
	# Real granted PLAY: quota belongs to the actor, markers still require own turn.
	for concrete in [false, true]:
		resetter._reset(suite)
		game.deck._discard.clear()
		tm.current_player_idx = 1
		tm.current_phase = TurnManager.Phase.START
		var actor: Player = game.players[0]
		var source: Player = game.players[1]
		var first_target: Player = game.players[2]
		var second_target: Player = game.players[3]
		actor.general_name = "里奥·普利威尔"
		actor.prep_tokens = 1
		source.general_name = "麦克斯·欧尼斯特"
		var original = CardBase.create(CardData.CardSubType.DUEL) if concrete else null
		if concrete: actor.determined_cards.append(original)
		else: actor.hand.append(null)
		first_target.hand.append(null)
		first_target.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.QINGGANG_SWORD))
		game._prep_replace_override = func(_l, _u, _t, _s, _o): return CardData.CardSubType.BORROWED_SWORD
		game._borrowed_second_target_override = func(options): return options.find(second_target)
		game._borrowed_strike_override = func(_a, _t, _o): return CardData.CardSubType.STRIKE
		game._meiyong_override = func(): return true
		game._meiyong_option_override = func(): return 2
		game._meiyong_target_override = func(): return actor
		var granted_actions: Array[CardActionEvent] = []
		var collect_granted = func(e): granted_actions.append(e)
		game.card_action_committed.connect(collect_granted)
		var act = func():
			suite.check(tm.get_play_actor_idx() == 0 and tm.current_player_idx == 1, "F02 integration real granted PLAY separates actor and owner")
			await game.execute_card_on_target(first_target, CardData.CardSubType.DUEL)
			suite.check(actor.prep_tokens == 0 and second_target.hp == 9 and tm.borrowed_sword_count_this_turn == 1 and tm.duel_count_this_turn == 0, "F02 integration gifted replacement spends old marker, final quota belongs to actor, grants no marker")
			game._on_end_play_pressed()
		act.call_deferred()
		var granted = await game._maybe_meiyong(source)
		game.card_action_committed.disconnect(collect_granted)
		suite.check(granted == 1 and tm.current_phase == TurnManager.Phase.START and source.hand_size() == 1 and tm.borrowed_sword_count_this_turn == 0, "F02 integration gifted replacement restores owner stage and independent quota")
		suite.check(granted_actions.size() == 2 and granted_actions.all(func(e): return e.settlement_completed) and (not concrete or granted_actions[0].card == original) and game._pending_card_actions.is_empty(), "F02 integration gifted original parent and required strike complete once")
		game._meiyong_override = Callable()
		game._meiyong_option_override = Callable()
		game._meiyong_target_override = Callable()
	# Replacement cannot become sacrifice, but the real response remains legal.
	resetter._reset(suite)
	game.deck._discard.clear()
	tm.current_phase = TurnManager.Phase.PLAY
	var protector: Player = game.players[0]
	protector.general_name = "里奥·普利威尔"
	protector.prep_tokens = 1
	protector.hand.append_array([null, null])
	first = game.players[2]
	second = game.players[3]
	first.hand.append(null)
	first.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.QINGGANG_SWORD))
	game._prep_replace_override = func(_l, _u, _t, _s, _o): return CardData.CardSubType.BORROWED_SWORD
	game._borrowed_second_target_override = func(options): return options.find(second)
	game._sacrifice_actor_override = func(p, target, _amount): return p == protector and target == second
	var sacrifice_actions: Array[CardActionEvent] = []
	var collect_sacrifice = func(e): sacrifice_actions.append(e)
	game.card_action_committed.connect(collect_sacrifice)
	await game.execute_card_on_target(first, CardData.CardSubType.DUEL)
	game.card_action_committed.disconnect(collect_sacrifice)
	suite.check(protector.hp == 9 and second.hp == 10 and protector.prep_tokens == 2 and sacrifice_actions.size() == 3 and sacrifice_actions.all(func(e): return e.settlement_completed), "F02 integration real sacrifice transfers required strike damage; own-turn sacrifice and parent grant only on completion")
	suite.check(sacrifice_actions.any(func(e): return e.card.sub_type == CardData.CardSubType.SACRIFICE) and game._pending_card_actions.is_empty(), "F02 integration real sacrifice remains a response, never a replacement candidate")
	game._borrowed_second_target_override = Callable()
	game._borrowed_strike_override = Callable()
	game._borrowed_extra_targets_override = Callable()
	game._rps_override = Callable()
	resetter._reset(suite)
	game.game_mode = mode_before
	game._bank_remaining = bank
	tm.current_phase = phase
	tm.phase_changed.connect(callback)
