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
		for original_sub in [CardData.CardSubType.DUEL, CardData.CardSubType.IRON_CHAIN, CardData.CardSubType.SNATCH, CardData.CardSubType.DISMANTLE]:
			for final_sub in [CardData.CardSubType.SNATCH, CardData.CardSubType.DISMANTLE]:
				if original_sub == final_sub: continue
				for zone in ["hand", "equip", "judgment"]:
					resetter._reset(suite)
					game.deck._discard.clear()
					tm.current_phase = TurnManager.Phase.PLAY
					tm.current_player_idx = 1
					var user: Player = game.players[1]
					var target: Player = game.players[2]
					var leo: Player = game.players[0]
					leo.general_name = "里奥·普利威尔"
					leo.prep_tokens = 1
					var original: CardBase = CardBase.create(original_sub) if concrete else null
					if concrete: user.determined_cards.append(original)
					else: user.hand.append(null)
					var taken = CardBase.create(CardData.CardSubType.DODGE)
					if zone == "hand": target.hand.append(taken)
					elif zone == "equip":
						taken = CardBase.create(CardData.CardSubType.MOUNT_MINUS)
						target.equip_card_to_slot("mount_2", taken)
					else:
						taken = CardBase.create(CardData.CardSubType.INDULGENCE)
						target.judgment_cards.append(taken)
					var commits: Array[CardActionEvent] = []
					var completions: Array[CardActionEvent] = []
					var on_commit = func(e): commits.append(e)
					var on_complete = func(e): completions.append(e)
					game.card_action_committed.connect(on_commit)
					game.card_action_completed.connect(on_complete)
					game._prep_replace_override = func(_leo, actor, fixed, _sub, options):
						suite.check(actor == user and fixed == target and options.has(final_sub), "F02b-2b-2b fixed target/new steal candidate")
						return final_sub
					game._prep_steal_pick_override = func(options):
						suite.check(options.size() == 1 and options[0].zone == zone, "F02b-2b-2b original zone choices")
						return 0
					if original_sub == CardData.CardSubType.IRON_CHAIN: await game._execute_iron_chain([target])
					else: await game.execute_card_on_target(target, original_sub)
					game.card_action_committed.disconnect(on_commit)
					game.card_action_completed.disconnect(on_complete)
					suite.check(commits.size() == 1 and completions == commits, "F02b-2b-2b one original use/completion")
					if commits.size() == 1:
						suite.check(commits[0].card.sub_type == original_sub and game.deck._discard.count(commits[0].card) == 1 \
							and (not concrete or commits[0].card == original), "F02b-2b-2b original physical card/name")
					suite.check(leo.prep_tokens == 0 and tm.steal_count_this_turn == 1 and tm.duel_count_this_turn == 0, "F02b-2b-2b mark and final category")
					suite.check(target.hp == 10 and not target.chained and not target.has_any_card(), "F02b-2b-2b no intermediate effect")
					var snatch = final_sub == CardData.CardSubType.SNATCH
					suite.check(user.hand_size() == (1 if snatch else 0) and game.deck._discard.count(taken) == (0 if snatch else 1), "F02b-2b-2b one payment and target card movement")
					if snatch: suite.check(user.hand.has(taken) if zone == "hand" else user.determined_cards.has(taken), "F02b-2b-2b same stolen entity")
					suite.check(game._pending_card_actions.is_empty(), "F02b-2b-2b release receipt")
	# 新限额/距离/空牌区只限制新候选，不把原牌合法性当替换合法性。
	for mode in ["limit", "distance", "empty"]:
		resetter._reset(suite)
		tm.current_phase = TurnManager.Phase.PLAY
		var user: Player = game.players[1]
		var target: Player = game.players[2]
		if mode != "empty": target.hand.append(null)
		if mode == "limit": tm.steal_count_this_turn = 2
		if mode == "distance": target.equip_card_to_slot("mount_1", CardBase.create(CardData.CardSubType.MOUNT_PLUS))
		var candidates = game._prep_fixed_candidates(user, target, CardData.CardSubType.DUEL)
		suite.check(candidates.has(CardData.CardSubType.SNATCH) == (mode not in ["limit", "distance", "empty"]), "F02b-2b-2b snatch legal limit/distance/zone")
		suite.check(candidates.has(CardData.CardSubType.DISMANTLE) == (mode == "distance"), "F02b-2b-2b dismantle not distance-limited")
	# 连续替换/新限额在确认时变化/规则免效都不二次付款。
	for mode in ["continuous", "fresh_limit", "nullified", "shield", "virtual", "arbitrary_target"]:
		resetter._reset(suite)
		game.deck._discard.clear()
		tm.current_phase = TurnManager.Phase.PLAY
		tm.current_player_idx = 1
		var user: Player = game.players[1]
		var target: Player = game.players[2]
		var leo: Player = game.players[0]
		leo.general_name = "里奥·普利威尔"
		leo.prep_tokens = 2 if mode == "continuous" else 1
		user.hand.append(null)
		target.hand.append(null if mode == "arbitrary_target" else CardBase.create(CardData.CardSubType.DODGE))
		var n: Array[int] = [0]
		game._prep_replace_override = func(_leo, _actor, _fixed, _sub, _options):
			n[0] += 1
			if mode == "fresh_limit": tm.steal_count_this_turn = 2
			return CardData.CardSubType.SNATCH if mode == "continuous" and n[0] == 1 else CardData.CardSubType.DISMANTLE
		var picks: Array[int] = [0]
		game._prep_steal_pick_override = func(_options):
			picks[0] += 1
			return 0
		if mode == "nullified":
			leo.determined_cards.append(CardBase.create(CardData.CardSubType.NULLIFICATION))
			var nullify_calls: Array[int] = [0]
			game._nullify_override = func():
				nullify_calls[0] += 1
				return nullify_calls[0] == 1
		if mode == "shield":
			target.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.LIEHUO_SHIELD))
			game._liehuo_override = func(): return true
		var events: Array[CardActionEvent] = []
		var collect = func(e): events.append(e)
		game.card_action_committed.connect(collect)
		if mode == "virtual":
			user.general_name = "安普提·斯丢皮得"
			game._yes_ah_override = func(): return "skill"
			suite.check(await game._choose_yes_ah_for_play(user, "顺手牵羊"), "F02b-2b-2b virtual real confirmation")
			await game._play_steal_card(user, target, true)
		else: await game.execute_card_on_target(target, CardData.CardSubType.DUEL)
		game.card_action_committed.disconnect(collect)
		suite.check(events.size() == (2 if mode == "nullified" else 1) and events[0].settlement_completed, "F02b-2b-2b original completed once plus independent nullification")
		suite.check(picks[0] == (0 if mode in ["fresh_limit", "nullified", "shield"] else 1), "F02b-2b-2b prevented effect opens no pick")
		suite.check(leo.prep_tokens == (1 if mode == "fresh_limit" else 0), "F02b-2b-2b continuous pays each existing mark/fresh illegal no fee")
		suite.check(tm.steal_count_this_turn == (2 if mode == "fresh_limit" else 1) and tm.duel_count_this_turn == (1 if mode == "fresh_limit" else 0), "F02b-2b-2b only final category even immune")
		suite.check(target.hand_size() == (1 if mode in ["fresh_limit", "nullified", "shield"] else 0), "F02b-2b-2b immune card preserved/normal dismantled")
		if mode == "virtual":
			suite.check(user.hp == 9 and user.hand_size() == 1 and events[0].is_virtual and not game.deck._discard.has(events[0].card), "F02b-2b-2b virtual no physical card/one HP fee")
		else: suite.check(user.hand_size() == 0, "F02b-2b-2b original paid once")
		if mode == "shield": suite.check(target.hp == 9, "F02b-2b-2b shield HP paid once")
		game._liehuo_override = Callable()
	# 真实强制窗口：无取消、基础计时、正常超时随机/外部失效分离。
	for mode in ["select_hand", "select_equip", "select_judgment", "timeout", "close", "restart", "stale"]:
		resetter._reset(suite)
		game.deck._discard.clear()
		tm.current_phase = TurnManager.Phase.PLAY
		tm.current_player_idx = 0
		var user: Player = game.players[0]
		var target: Player = game.players[1]
		var leo: Player = game.players[2]
		leo.general_name = "里奥·普利威尔"
		leo.prep_tokens = 1
		user.hand.append(null)
		var hand_card = CardBase.create(CardData.CardSubType.DODGE)
		var mount_card = CardBase.create(CardData.CardSubType.MOUNT_PLUS)
		var judgment_card = CardBase.create(CardData.CardSubType.INDULGENCE)
		target.hand.append(hand_card)
		target.equip_card_to_slot("mount_2", mount_card)
		target.judgment_cards.append(judgment_card)
		game._prep_replace_override = func(_leo, _actor, _fixed, _sub, _options): return CardData.CardSubType.DISMANTLE
		var old_answers: Array[ChoicePromptAnswer] = []
		var drive = func():
			var pending = game._choice_prompt_stack.back()
			old_answers.append(pending.answer)
			var buttons = pending.overlay.find_children("*", "Button", true, false)
			suite.check(buttons.size() == 3 and game._countdown_active and game._step_remaining > 29.0, "F02b-2b-2b actual no-cancel/base-countdown window")
			for button in buttons: suite.check(button.text != "取消" and not button.text.contains("闪"), "F02b-2b-2b hidden hand name/noncancel")
			if mode == "timeout":
				game._step_remaining = 0.001
				game._bank_remaining = 0.0
				game._process(0.01)
			elif mode == "close": pending.overlay.queue_free()
			elif mode == "restart": game.reset_game_over_state()
			elif mode == "stale":
				target.remove_equipment("mount_2")
				target.equip_card_to_slot("mount_2", CardBase.create(CardData.CardSubType.MOUNT_PLUS))
				pending.answer.submit(1)
			else: buttons[["select_hand", "select_equip", "select_judgment"].find(mode)].pressed.emit()
		drive.call_deferred()
		await game.execute_card_on_target(target, CardData.CardSubType.DUEL)
		var invalid = mode in ["close", "restart", "stale"]
		var remaining = target.hand_size() + target.equipment.size() + target.judgment_cards.size()
		suite.check(remaining == (3 if invalid else 2), "F02b-2b-2b select/timeout moves one; invalid moves none")
		suite.check(user.hand_size() == 0 and leo.prep_tokens == 0 and tm.steal_count_this_turn == 1, "F02b-2b-2b paid fees retained and final category")
		suite.check(game._pending_card_actions.is_empty(), "F02b-2b-2b invalid receipt cleanup")
		await suite.process_frame
		suite.check(game._choice_prompt_stack.is_empty(), "F02b-2b-2b window cleanup")
		for answer in old_answers:
			suite.check(answer.settled, "F02b-2b-2b old callback already settled")
			answer.submit(0)
			suite.check(target.hand_size() + target.equipment.size() + target.judgment_cards.size() == remaining, "F02b-2b-2b old callback moves no cards")
	resetter._reset(suite)
	game._bank_remaining = bank
	tm.current_phase = phase
	tm.phase_changed.connect(callback)
