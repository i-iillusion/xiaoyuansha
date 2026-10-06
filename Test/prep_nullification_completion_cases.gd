extends RefCounted

func run(suite):
	var game: GameManager = suite.game
	var tm = game.turn_manager
	var phase = tm.current_phase
	var callback = game._on_phase_changed
	tm.phase_changed.disconnect(callback)
	for owner in [0, 1]:
		for concrete in [false, true]:
			suite.reset_players()
			tm.current_player_idx = owner
			tm.current_phase = TurnManager.Phase.PLAY
			var actor: Player = game.players[1]
			actor.general_name = "里奥·普利威尔"
			for i in 2:
				if concrete: actor.determined_cards.append(CardBase.create(CardData.CardSubType.NULLIFICATION))
				else: actor.hand.append(null)
			game.players[3].determined_cards.append(CardBase.create(CardData.CardSubType.NULLIFICATION))
			var actions: Array[CardActionEvent] = []
			var completed: Array[CardActionEvent] = []
			var expected: Array[int] = [1, 3, 1]
			var commit = func(event):
				actions.append(event)
				suite.check(actor.prep_tokens == 0 and not event.settlement_completed,
					"F02b-1e-a：无懈逐张成立期间均不提前获标记")
			var finish = func(event):
				completed.append(event)
				suite.check(actor.prep_tokens == (2 if owner == 1 else 0),
					"F02b-1e-a：首次完成通知时整链合资格计数已一次完成")
			game.card_action_committed.connect(commit)
			game.card_action_completed.connect(finish)
			game._ai_response_override = func(view, kind, options):
				if kind != "nullification": return -1
				suite.check(actor.prep_tokens == 0, "F02b-1e-a：后续反无懈选择窗口仍0")
				return CardData.CardSubType.NULLIFICATION if actions.size() < expected.size() \
					and view.actor == expected[actions.size()] and options.has(CardData.CardSubType.NULLIFICATION) else -1
			var result = await game._ask_nullification_chain_result("完整三张反制链")
			game.card_action_committed.disconnect(commit)
			game.card_action_completed.disconnect(finish)
			suite.check(result == GameManager.NullificationOutcome.NULLIFIED and actions.size() == 3
				and actions[0].actor_seat == 1 and actions[1].actor_seat == 3 and actions[2].actor_seat == 1
				and completed == actions, "F02b-1e-a：整链顺序1→3→1，奇数抵消，全批只完成一次")
			for event in actions:
				suite.check(game.deck._discard.count(event.card) == 1 and event.card.sub_type == CardData.CardSubType.NULLIFICATION,
					"F02b-1e-a：每个原实体实际入弃一次、牌名不变")
			game._complete_card_actions(actions)
			suite.check(actor.prep_tokens == (2 if owner == 1 else 0) and game._pending_card_actions.is_empty(),
				"F02b-1e-a：别人回合0、重复批量完成幂等且无遗留")
	for concrete in [false, true]:
		for restart in [false, true]:
			suite.reset_players()
			tm.current_player_idx = 1
			tm.current_phase = TurnManager.Phase.PLAY
			var actor: Player = game.players[1]
			actor.general_name = "里奥·普利威尔"
			if concrete: actor.determined_cards.append(CardBase.create(CardData.CardSubType.NULLIFICATION))
			else: actor.hand.append(null)
			game.players[0].hand.append(null)
			var actions: Array[CardActionEvent] = []
			var completed: Array[CardActionEvent] = []
			var drive = func():
				suite.check(actions.size() == 1 and actor.prep_tokens == 0,
					"F02b-1e-a：真实后续无懈窗口首张已付，标记仍0")
				if restart: game.reset_game_over_state()
				else: game._choice_prompt_stack.back().overlay.queue_free()
			var commit = func(event):
				actions.append(event)
				game._nullify_override = Callable()
				drive.call_deferred()
			var finish = func(event): completed.append(event)
			game.card_action_committed.connect(commit)
			game.card_action_completed.connect(finish)
			game._ai_response_override = func(view, kind, options):
				return CardData.CardSubType.NULLIFICATION if view.actor == 1 and kind == "nullification" and options.has(CardData.CardSubType.NULLIFICATION) else -1
			var result = await game._ask_nullification_chain_result("后续真实反无懈失效")
			game.card_action_committed.disconnect(commit)
			game.card_action_completed.disconnect(finish)
			suite.check(result == GameManager.NullificationOutcome.INVALIDATED and completed.is_empty()
				and actor.prep_tokens == 0 and game._pending_card_actions.is_empty(),
				"F02b-1e-a：真实链失效释放整批，不冒充正常终止")
			suite.check(actor.hand_size() == 0 and game.deck._discard.count(actions[0].card) == 1
				and game.players[0].hand_size() == 1, "F02b-1e-a：首张费用保留，后续未答不支付")
			await suite.process_frame
			suite.check(game._choice_prompt_stack.is_empty(), "F02b-1e-a：真实反制旧窗口清理")
	# 合法安普提虚拟无懈仍有完成事实，但不制造实体入弃或里奥资格。
	suite.reset_players()
	tm.current_phase = TurnManager.Phase.PLAY
	var actor: Player = game.players[0]
	actor.general_name = "安普提·斯丢皮得"
	var original = CardBase.create(CardData.CardSubType.NULLIFICATION)
	actor.determined_cards.append(original)
	var actions: Array[CardActionEvent] = []
	var completed: Array[CardActionEvent] = []
	var commit = func(event):
		actions.append(event)
		game._nullify_override = func(): return false
	var finish = func(event): completed.append(event)
	game.card_action_committed.connect(commit)
	game.card_action_completed.connect(finish)
	game._nullify_override = func(): return true
	game._yes_ah_override = func(): return "skill"
	var result = await game._ask_nullification_chain_result("合法虚拟无懈完整链")
	game.card_action_committed.disconnect(commit)
	game.card_action_completed.disconnect(finish)
	suite.check(result == GameManager.NullificationOutcome.NULLIFIED and actions.size() == 1
		and completed == actions and actions[0].is_virtual and not actions[0].from_hand,
		"F02b-1e-a：合法虚拟无懈有唯一完成但不是手牌使用")
	suite.check(actor.hp == 9 and actor.determined_cards == [original]
		and not game.deck._discard.has(original) and not game.deck._discard.has(actions[0].card)
		and actor.prep_tokens == 0 and game._pending_card_actions.is_empty(),
		"F02b-1e-a：虚拟只付技能费用，保留原牌，无凭据或标记泄漏")
	suite.reset_players()
	tm.current_phase = phase
	tm.phase_changed.connect(callback)
