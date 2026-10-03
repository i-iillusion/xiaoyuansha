extends RefCounted

var suite
var game: GameManager

func reset():
	suite.reset_players()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game.deck._discard.clear()
	game._nullify_override = Callable()
	for p in game.players:
		p.judgment_cards.clear()

func drive(action: String):
	var pending = game._choice_prompt_stack.back()
	var buttons = pending.overlay.find_children("*", "Button", true, false)
	match action:
		"accept":
			buttons[0].pressed.emit()
			pending.answer.submit(1)
		"decline": buttons[1].pressed.emit()
		"timeout": game._countdown_on_timeout.call()
		"close": pending.overlay.queue_free()
		"phase":
			game.turn_manager.current_phase = TurnManager.Phase.END
			game.turn_manager.current_phase = TurnManager.Phase.PLAY
			buttons[0].pressed.emit()
		"hand":
			game.players[0].hand.append(null)
			buttons[0].pressed.emit()
		"ended": game._finish_game("平局", "E03e-1回归")

func run(host):
	suite = host
	game = host.game
	var phase = game.turn_manager.current_phase
	var events: Array = []
	var collect = func(event): events.append(event)
	game.card_action_committed.connect(collect)
	for concrete in [false, true]:
		for action in ["accept", "decline", "timeout", "close", "phase", "hand", "ended"]:
			reset()
			events.clear()
			var p = game.players[0]
			var original = CardBase.create(CardData.CardSubType.NULLIFICATION) if concrete else null
			if concrete:
				p.determined_cards.append(original)
			else:
				p.hand.append(null)
			drive.call_deferred(action)
			var result = await game._ask_nullification_round_result("E03e-1")
			var expected = GameManager.NullificationOutcome.NULLIFIED if action == "accept" else (
				GameManager.NullificationOutcome.PASSED if action in ["decline", "timeout", "hand"] else GameManager.NullificationOutcome.INVALIDATED)
			suite.check(result.outcome == expected, "E03e-1：无懈窗口结果区分：" + action)
			if action == "accept":
				suite.check(result.actor_name == p.player_name and p.hand_size() == 0 and events.size() == 1
					and game.deck._discard.size() == 1 and (not concrete or game.deck._discard[0] == original),
					"E03e-1：重复点击只使用一次原无懈牌")
			else:
				suite.check(p.hand_size() == (2 if action == "hand" else 1) and events.is_empty()
					and game.deck._discard.is_empty(), "E03e-1：放弃或失效不付无懈费用")
			await suite.process_frame
			suite.check(game._choice_prompt_stack.is_empty(), "E03e-1：无懈窗口无残留等待")
	# 反无懈奇偶及第二窗口失效；第一次已用的牌不返还。
	for second in ["accept", "decline", "close"]:
		reset()
		game.players[0].hand.assign([null, null])
		var tail = func():
			game._nullify_override = func(): return false
			drive(second)
		var first = func():
			drive("accept")
			tail.call_deferred()
		first.call_deferred()
		var outcome = await game._ask_nullification_chain_result("反无懈")
		var expected = GameManager.NullificationOutcome.PASSED if second == "accept" else (
			GameManager.NullificationOutcome.NULLIFIED if second == "decline" else GameManager.NullificationOutcome.INVALIDATED)
		suite.check(outcome == expected and game.deck._discard.size() == (2 if second == "accept" else 1),
			"E03e-1：反无懈奇偶/失效与已支付原牌：" + second)
		await suite.process_frame
	# 是啊二级窗口失效不能降为普通取消，亦不付牌/流失体力。
	reset()
	game.players[0].general_name = "安普提·斯丢皮得"
	game.players[0].hand.append(null)
	var enter_skill = func():
		drive("accept")
		drive.call_deferred("close")
	enter_skill.call_deferred()
	var invalid_skill = await game._ask_nullification_chain_result("是啊二级失效")
	suite.check(invalid_skill == GameManager.NullificationOutcome.INVALIDATED
		and game.players[0].hp == 10 and game.players[0].hand_size() == 1 and game.deck._discard.is_empty(),
		"E03e-1：是啊二级窗口关闭停止旧无懈链，不付费")
	await suite.process_frame
	# 旧共享信号和旧计时回调不能替后来窗口作答。
	reset()
	game.players[0].hand.append(null)
	var saved: Array = []
	var close_first = func():
		saved.append(game._countdown_on_timeout)
		drive("close")
	close_first.call_deferred()
	await game._ask_nullification_chain_result("旧窗口")
	await suite.process_frame
	var stale = func():
		var pending = game._choice_prompt_stack.back()
		game._response_ready.emit()
		saved[0].call()
		suite.check(not pending.answer.settled, "E03e-1：旧共享信号/旧超时不唤醒新窗口")
		drive("accept")
	stale.call_deferred()
	var next = await game._ask_nullification_chain_result("下一合法窗口")
	suite.check(next == GameManager.NullificationOutcome.NULLIFIED and game.players[0].hand_size() == 0,
		"E03e-1：下一合法无懈仍可正常使用")
	await suite.process_frame
	# 真实即时锦囊入口，关闭无懈窗口停止后续目标，不吞回已支付锦囊。
	for kind in ["aoe", "garden", "harvest", "disarm", "chain", "snatch", "duel"]:
		reset()
		var p = game.players[0]
		var actor = game.players[4]
		game.turn_manager.current_player_idx = 4
		p.hand.append(null)
		for target in game.players:
			target.hp = 8
		var armor = CardBase.create(CardData.CardSubType.RENWANG_DUN)
		if kind == "disarm": p.equip_card_to_slot("armor", armor)
		actor.hand.append(null)
		drive.call_deferred("close")
		match kind:
			"aoe": await game._play_aoe(CardData.CardSubType.STRIKE, "南蛮入侵", "杀")
			"garden": await game._play_peach_garden()
			"harvest": await game._play_harvest()
			"disarm": await game._play_disarm()
			"chain":
				var targets: Array[Player] = [p, game.players[1]]
				await game._execute_iron_chain(targets)
			"snatch": await game._play_steal_card(actor, p, true)
			"duel": await game._play_duel(actor, p)
		suite.check(p.hp == 8 and game.players[1].hp == 8 and actor.hp == 8 and p.hand_size() == 1
			and not p.chained and not game.players[1].chained, "E03e-1：失效不继续锦囊旧效果：" + kind)
		suite.check(actor.hand_size() == (1 if kind == "duel" else 0)
			and game.deck._discard.size() == (0 if kind == "duel" else 1), "E03e-1：已支付锦囊保留，决斗底层不重复支付")
		if kind == "disarm": suite.check(p.get_equipment_card("armor") == armor, "E03e-1：失效卸甲不动原装备")
		await suite.process_frame
	# 判定的无懈窗口在移出原判定牌前结束；失效不丢原牌、不触发效果。
	for sub in [CardData.CardSubType.LIGHTNING, CardData.CardSubType.INDULGENCE,
		CardData.CardSubType.SUPPLY_SHORTAGE, CardData.CardSubType.BURNING_CAMP]:
		for action in ["close", "decline"]:
			reset()
			game.turn_manager.skip_play_phase = false
			game.turn_manager.supply_shortage_active = false
			var p = game.players[0]
			p.hand.append(null)
			var original = CardBase.create(sub)
			p.judgment_cards.append(original)
			var choose = func():
				game._nullify_override = func(): return false
				drive(action)
			choose.call_deferred()
			var completed = await game._run_judgment(p, false)
			suite.check(completed == (action == "decline"), "E03e-1：判定显式返回旧结算是否完成")
			suite.check(p.judgment_cards.has(original) == (action == "close")
				and game.deck._discard.count(original) == (0 if action == "close" else 1), "E03e-1：判定原牌不丢失或重复入弃")
			if action == "close":
				suite.check(p.hp == 10 and not game.turn_manager.skip_play_phase and not game.turn_manager.supply_shortage_active
					and game.players[1].judgment_cards.is_empty(), "E03e-1：无效判定不伤害/跳阶段/蔓延")
			await suite.process_frame
	# 普通/获赠判定外层都不得在窗口失效后推进阶段。
	for granted in [false, true]:
		reset()
		game.turn_manager.current_phase = TurnManager.Phase.JUDGE
		game.turn_manager.skip_judge_phase = false
		game.turn_manager.granted_judge_target_idx = 0 if granted else -1
		game.turn_manager.current_player_idx = 1 if granted else 0
		var original = CardBase.create(CardData.CardSubType.LIGHTNING)
		game.players[0].judgment_cards.append(original)
		game.players[0].hand.append(null)
		drive.call_deferred("close")
		await game._do_judge(game.turn_manager.current_player_idx)
		suite.check(game.turn_manager.current_phase == TurnManager.Phase.JUDGE
			and game.players[0].judgment_cards == [original], "E03e-1：普通/获赠判定失效不推进阶段")
		await suite.process_frame
	game.card_action_committed.disconnect(collect)
	reset()
	game.turn_manager.current_phase = phase
	suite = null
	game = null
