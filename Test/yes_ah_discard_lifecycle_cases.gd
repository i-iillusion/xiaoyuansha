extends "res://Test/sage_save_lifecycle_cases.gd"

func active_prepare():
	suite.reset_players()
	game.deck._discard.clear()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game._is_targeting = false
	game._is_iron_chain_targeting = false
	game._clear_pending_determined_card()
	for p in game.players: p.judgment_cards.clear()
	game.players[0].general_name = "安普提·斯丢皮得"
	game.players[0].hand.assign([null, null])
	game.players[0].hp = 9
	game.players[1].hand.assign([null]) # 拆/顺有合法牌区，确实进入是啊窗口。

func run(host):
	suite = host
	game = host.game
	var tricks = [CardData.CardSubType.IRON_CHAIN, CardData.CardSubType.DUEL,
		CardData.CardSubType.BARBARIAN_INVASION, CardData.CardSubType.VOLLEY_OF_ARROWS,
		CardData.CardSubType.PEACH_GARDEN, CardData.CardSubType.HARVEST,
		CardData.CardSubType.DISARM, CardData.CardSubType.DISMANTLE, CardData.CardSubType.SNATCH,
		CardData.CardSubType.LIGHTNING, CardData.CardSubType.INDULGENCE,
		CardData.CardSubType.SUPPLY_SHORTAGE, CardData.CardSubType.BURNING_CAMP]
	for sub in tricks:
		for mode in ["cancel", "close", "reset"]:
			print("[E03e-22c] active trick=%s mode=%s" % [sub, mode])
			active_prepare()
			var action = func():
				suite.check(game._choice_prompt_stack.size() == 1, "E03e-22c：主动锦囊实际进入独立是啊窗口：%s/%s" % [sub, mode])
				var pending = game._choice_prompt_stack.back()
				match mode:
					"cancel": pending.answer.submit(-1)
					"close": pending.overlay.queue_free()
					"reset": game.reset_game_over_state()
			action.call_deferred()
			await game.play_card(sub)
			suite.check(game.players[0].hand == [null, null] and game.players[0].hp == 9 and game.players[1].hp == 10 and game.deck._discard.is_empty() and game.players[0].judgment_cards.is_empty() and not game._is_targeting and not game._is_iron_chain_targeting and not game._yes_ah_active, "E03e-22c：13种主动锦囊取消/关闭/重开不付牌或开旧目标：%s/%s" % [sub, mode])
			await suite.process_frame
	for sub in [CardData.CardSubType.PEACH_GARDEN, CardData.CardSubType.LIGHTNING]:
		for virtual in [false, true]:
			active_prepare()
			game._yes_ah_override = func(): return "skill" if virtual else "card"
			await game.play_card(sub)
			suite.check(game.players[0].hand.size() == (2 if virtual else 1) and game.players[0].hp == (9 if sub == CardData.CardSubType.PEACH_GARDEN and virtual else (10 if sub == CardData.CardSubType.PEACH_GARDEN else (8 if virtual else 9))), "E03e-22c：主动正常付牌/技能费用仍生效，取消保护不阻止合法效果")
			suite.check(game.players[0].judgment_cards.size() == (1 if sub == CardData.CardSubType.LIGHTNING else 0) and game.deck._discard.size() == (1 if not virtual and sub == CardData.CardSubType.PEACH_GARDEN else 0), "E03e-22c：真实锦囊与虚拟锦囊、即时弃牌/延时入区仍分离")
	for mode in ["accept", "close", "reset"]:
		print("[E03e-22c] cost mode=" + mode)
		prepare(TurnManager.Phase.PLAY)
		game.players[0].hp = 1
		var action = func():
			var pending = game._choice_prompt_stack.back()
			match mode:
				"close": pending.overlay.queue_free()
				"reset": game.reset_game_over_state()
				_: pending.overlay.find_children("*", "Button", true, false)[0].pressed.emit()
		action.call_deferred()
		var result = await game._pay_yes_ah_cost_result(game.players[0])
		suite.check(result == (1 if mode == "accept" else GameManager.CHOICE_INVALID) and game.players[0].hp == (10 if mode == "accept" else 0) and not game.players[0].identity_revealed, "E03e-22c：是啊费用濒死成功或失效显式结果，不回滚已流失体力：" + mode)
		await suite.process_frame
	prepare(TurnManager.Phase.PLAY)
	game.players[0].hp = 1
	game._yes_ah_active = true
	var close = func(): game._choice_prompt_stack.back().overlay.queue_free()
	close.call_deferred()
	var actions: Array[CardActionEvent] = []
	suite.check(not await game._consume_trick(game.players[0], CardData.CardSubType.BARBARIAN_INVASION, actions) and game.players[0].hp == 0 and game.deck._discard.is_empty() and game.players[0].hand.size() == 2, "E03e-22c：技能费用失效不生成虚拟锦囊/用牌事件或另扣手牌")
	game._abandon_card_actions(actions)
	await suite.process_frame
	for route in ["nullification", "sacrifice"]:
		prepare(TurnManager.Phase.PLAY)
		game.players[0].general_name = "安普提·斯丢皮得"
		game.players[0].hp = 1
		game._yes_ah_override = func(): return "skill"
		game._nullify_override = func(): return true
		game._sacrifice_actor_override = func(p, _target, _amount): return p.seat_index == 0
		close.call_deferred()
		if route == "nullification":
			var result = await game._ask_nullification_round_result("是啊费用失效")
			suite.check(result.outcome == GameManager.NullificationOutcome.INVALIDATED, "E03e-22c：无懈费用求救失效停止原无懈，不当作正常无人响应")
		else:
			var result = await game._maybe_sacrifice_result(game.players[2], game.players[1], 1, EffectChain.DamageType.PHYSICAL)
			suite.check(result.invalidated and result.player == null, "E03e-22c：舍己费用求救失效不转移伤害或继续旧询问")
		suite.check(game.players[0].hp == 0 and game.players[0].hand.size() == 2 and game.deck._discard.is_empty(), "E03e-22c：响应费用已流失体力保留，不补付或虚拟打出")
		await suite.process_frame
	for override in [false, true]:
		suite.reset_players()
		game.turn_manager.current_phase = TurnManager.Phase.DISCARD
		game.players[0].hp = 1
		game.players[0].hand.assign([null, null, null])
		var calls: Array = []
		if override:
			game._hand_discard_override = func(snapshot, count, _mandatory):
				calls.append(true)
				game.reset_game_over_state()
				return snapshot.defaults(count)
		else:
			game._hand_discard_override = Callable()
			close.call_deferred()
		await game._do_discard(0)
		suite.check(game.players[0].hand.size() == 3 and game.turn_manager.current_phase == TurnManager.Phase.DISCARD and calls.size() == (1 if override else 0), "E03e-22c：真实弃牌阶段关闭/重开不付牌、不忙循环重问、不推进END")
		await suite.process_frame
	suite.reset_players()
	game._yes_ah_override = Callable()
	game._sage_save_override = Callable()
	game._sacrifice_actor_override = Callable()
	game = null
	suite = null
