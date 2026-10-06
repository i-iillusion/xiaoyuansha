extends RefCounted

func run(suite):
	var game: GameManager = suite.game
	var tm = game.turn_manager
	var resetter = load("res://Test/prep_single_replace_cases.gd").new()
	var phase = tm.current_phase
	var bank = game._bank_remaining
	var callback = game._on_phase_changed
	tm.phase_changed.disconnect(callback)
	for concrete in [false, true]:
		for initially_chained in [false, true]:
			for sub in [CardData.CardSubType.DUEL, CardData.CardSubType.SNATCH, CardData.CardSubType.DISMANTLE, CardData.CardSubType.IRON_CHAIN]:
				resetter._reset(suite)
				tm.current_phase = TurnManager.Phase.PLAY
				tm.current_player_idx = 1
				var user: Player = game.players[1]
				var target: Player = game.players[2]
				var leo: Player = game.players[0]
				leo.general_name = "里奥·普利威尔"
				leo.prep_tokens = 1
				target.chained = initially_chained
				target.hand.append(CardBase.create(CardData.CardSubType.DODGE))
				var original: CardBase = CardBase.create(sub) if concrete else null
				if concrete: user.determined_cards.append(original)
				else: user.hand.append(null)
				var events: Array[CardActionEvent] = []
				var collect = func(event): events.append(event)
				game.card_action_committed.connect(collect)
				game._prep_replace_override = func(owner, actor, fixed, _current_sub, options):
					suite.check(owner == leo and actor == user and fixed == target and owner.prep_tokens == 1,
						"F02b-2b-1：原目标/使用者/已有费用一致")
					var desired = CardData.CardSubType.DUEL if sub == CardData.CardSubType.IRON_CHAIN else CardData.CardSubType.IRON_CHAIN
					suite.check(options.has(desired) and not options.has(CardData.CardSubType.SACRIFICE),
						"F02b-2b-1：合法铁索/决斗候选，舍己排除")
					return desired
				if sub == CardData.CardSubType.IRON_CHAIN:
					var targets: Array[Player] = [target]
					await game._execute_iron_chain(targets)
				else: await game.execute_card_on_target(target, sub)
				game.card_action_committed.disconnect(collect)
				suite.check(target.hp == (9 if sub == CardData.CardSubType.IRON_CHAIN else 10)
					and target.chained == (initially_chained if sub == CardData.CardSubType.IRON_CHAIN else true),
					"F02b-2b-1：单体改铁索只令原目标横置，已横置不解除；铁索改决斗仍原目标")
				suite.check(not game.players[3].chained and game.players[3].hp == 10,
					"F02b-2b-1：不扩大为第二目标")
				suite.check(events.size() == 1 and events[0].card.sub_type == sub and events[0].sub_type == sub
					and events[0].settlement_completed and game.deck._discard.count(events[0].card) == 1
					and (not concrete or events[0].card == original), "F02b-2b-1：只完成一次原实体原事件")
				suite.check(tm.duel_count_this_turn == (1 if sub == CardData.CardSubType.IRON_CHAIN else 0)
					and tm.steal_count_this_turn == 0 and leo.prep_tokens == 0,
					"F02b-2b-1：最终类别计数，一次标记、不再支付原牌")
	# 连续替换，不因最终回到原牌而抹去中间费用或使用旧铁索切换语义。
	for mode in ["triple", "back", "decline", "invalid", "restart"]:
		resetter._reset(suite)
		tm.current_phase = TurnManager.Phase.PLAY
		tm.current_player_idx = 1
		var user: Player = game.players[1]
		var target: Player = game.players[2]
		var leo: Player = game.players[0]
		leo.general_name = "里奥·普利威尔"
		leo.prep_tokens = 3
		target.hand.append(CardBase.create(CardData.CardSubType.DODGE))
		target.chained = true
		var sub = CardData.CardSubType.IRON_CHAIN if mode == "back" else CardData.CardSubType.DISMANTLE
		user.hand.append(null)
		var windows: Array[int] = [0]
		var events: Array[CardActionEvent] = []
		var collect = func(event): events.append(event)
		game.card_action_committed.connect(collect)
		game._prep_replace_override = func(_owner, actor, fixed, current, options):
			windows[0] += 1
			suite.check(actor == user and fixed == target and leo.prep_tokens == 4 - windows[0]
				and events.size() == 1 and not events[0].settlement_completed,
				"F02b-2b-1：连续更换每次只用此前已有标记，中途不完成原牌")
			if windows[0] == 2 and mode in ["decline", "invalid", "restart"]:
				if mode == "invalid":
					tm.current_phase = TurnManager.Phase.END
					tm.current_phase = TurnManager.Phase.PLAY
				elif mode == "restart": game.reset_game_over_state()
				return -1
			if windows[0] == 3 and mode == "back": return -1
			var desired = CardData.CardSubType.IRON_CHAIN if current == CardData.CardSubType.DUEL else CardData.CardSubType.DUEL
			suite.check(options.has(desired), "F02b-2b-1：基于当前效果而非持久原牌生成下一候选")
			return desired
		if sub == CardData.CardSubType.IRON_CHAIN:
			var targets: Array[Player] = [target]
			await game._execute_iron_chain(targets)
		else: await game.execute_card_on_target(target, sub)
		game.card_action_committed.disconnect(collect)
		var invalid = mode in ["invalid", "restart"]
		suite.check(leo.prep_tokens == (0 if mode == "triple" else (1 if mode == "back" else 2)),
			"F02b-2b-1：连续更换逐次付标记，拒绝/失效不退已付费用")
		suite.check(target.hp == (9 if mode in ["triple", "decline"] else 10) and target.chained,
			"F02b-2b-1：仅最终牌生效，回原铁索仍是替换为横置而非解除")
		suite.check(tm.duel_count_this_turn == (1 if mode in ["triple", "decline"] else 0) and tm.steal_count_this_turn == 0,
			"F02b-2b-1：中间牌不计次数，技术失效不计最终使用")
		suite.check(events.size() == 1 and events[0].settlement_completed == not invalid
			and events[0].card.sub_type == sub and game.deck._discard.count(events[0].card) == 1
			and game._pending_card_actions.is_empty(), "F02b-2b-1：连续替换原费用一次、原凭据一次完成或释放")
	# 第二个真实窗口的超时只放弃本次更换，不回退已成功的新效果。
	for mode in ["cancel", "timeout", "close", "restart"]:
		resetter._reset(suite)
		tm.current_phase = TurnManager.Phase.PLAY
		tm.current_player_idx = 1
		var user: Player = game.players[1]
		var target: Player = game.players[2]
		var leo: Player = game.players[0]
		leo.general_name = "里奥·普利威尔"
		leo.prep_tokens = 2
		user.hand.append(null)
		target.hand.append(CardBase.create(CardData.CardSubType.DODGE))
		game._prep_replace_override = Callable()
		var seen: Array = []
		var drive = func():
			if game._choice_prompt_stack.is_empty(): return
			var pending = game._choice_prompt_stack.back()
			if seen.has(pending.answer): return
			seen.append(pending.answer)
			if seen.size() == 1:
				suite.check(leo.prep_tokens == 2, "F02b-2b-1：第一次真实更换前已有2标记")
				pending.answer.submit(0) # 原拆→决斗
			else:
				suite.check(leo.prep_tokens == 1 and target.hp == 10 and tm.duel_count_this_turn == 0,
					"F02b-2b-1：第二真实窗口前只花1标记，最终效果/计数尚未结算")
				if mode == "cancel": pending.answer.submit(-1)
				elif mode == "close": pending.overlay.queue_free()
				elif mode == "restart": game.reset_game_over_state()
				else:
					game._step_remaining = 0.001
					game._bank_remaining = 0.0
					game._process(0.01)
		suite.process_frame.connect(drive)
		await game.execute_card_on_target(target, CardData.CardSubType.DISMANTLE)
		suite.process_frame.disconnect(drive)
		var invalid = mode in ["close", "restart"]
		suite.check(seen.size() == 2 and leo.prep_tokens == 1 and target.hp == (10 if invalid else 9),
			"F02b-2b-1：后续超时/取消保留前次决斗和剩余标记，关闭/重开不生效")
		suite.check(tm.duel_count_this_turn == (0 if invalid else 1) and tm.steal_count_this_turn == 0
			and user.hand_size() == 0 and game._pending_card_actions.is_empty(),
			"F02b-2b-1：第二真实窗口费用不退，最终使用仅正常计数，凭据释放")
		await suite.process_frame
		suite.check(game._choice_prompt_stack.is_empty(), "F02b-2b-1：连续真实窗口全部清理")
	# 两目标铁索不能缩水成固定单体，原未替换铁索仍切换两个角色。
	resetter._reset(suite)
	tm.current_phase = TurnManager.Phase.PLAY
	tm.current_player_idx = 1
	game.players[0].general_name = "里奥·普利威尔"
	game.players[0].prep_tokens = 1
	game.players[1].hand.append(null)
	game.players[2].chained = true
	game._prep_replace_override = func(_owner, _actor, _fixed, _current, _options):
		suite.check(false, "F02b-2b-1：两目标铁索不进入固定单体候选")
		return CardData.CardSubType.DUEL
	var targets: Array[Player] = [game.players[2], game.players[3]]
	await game._execute_iron_chain(targets)
	suite.check(not game.players[2].chained and game.players[3].chained and game.players[0].prep_tokens == 1,
		"F02b-2b-1：未替换两目标铁索保持原切换，标记未花；改AOE留b-3")
	resetter._reset(suite)
	game._bank_remaining = bank
	tm.current_phase = phase
	tm.phase_changed.connect(callback)
