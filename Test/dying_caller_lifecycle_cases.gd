extends "res://Test/sage_save_lifecycle_cases.gd"

func run(host):
	suite = host
	game = host.game
	for mode in ["win", "ties", "close", "reset", "hook_invalid"]:
		prepare(TurnManager.Phase.PLAY)
		var victim = game.players[0]
		victim.general_name = "安普提·斯丢皮得"
		victim.equipment.clear()
		victim.equipment_cards.clear()
		var calls: Array = []
		game._rps_override = Callable()
		if mode in ["win", "ties", "hook_invalid"]:
			game._rps_override = func(p):
				calls.append(p.seat_index)
				if mode == "hook_invalid": return GameManager.RPS_INVALID
				return GameManager.RPS_ROCK if mode == "ties" or p == victim else GameManager.RPS_SCISSORS
		else:
			var action = func():
				if mode == "close": game._choice_prompt_stack.back().overlay.queue_free()
				else: game.reset_game_over_state()
			action.call_deferred()
		var chain = game._new_damage_chain(game.players[1], victim, null, 1, EffectChain.DamageType.PHYSICAL)
		var result = await game._resolve_dying(victim, null, "test", chain)
		if mode in ["close", "reset", "hook_invalid"]:
			suite.check(result == GameManager.CHOICE_INVALID and victim.is_dying() and victim.hand.size() == 2 and not victim.identity_revealed and chain.continuation_invalid, "E03e-21c：装傻出拳失效停止死亡流程，不误死亡/回血/清牌")
		else:
			suite.check(result == 0 and calls.count(0) == 4 and calls.size() == 8, "E03e-21c：装傻四对手各猜一次，平局不重猜")
			suite.check(victim.hp == (1 if mode == "win" else 0) and victim.is_dead() == (mode == "ties"), "E03e-21c：正常装傻赢局回血，全平仍进入死亡")
		await suite.process_frame
	for kind in ["sage", "rescue"]:
		for mode in ["accept", "close", "reset"]:
			prepare(TurnManager.Phase.PLAY)
			var victim = game.players[0]
			victim.hp = 1
			if kind == "rescue":
				victim.equipment.clear()
				victim.equipment_cards.clear()
				game._dying_peach_override = Callable()
				game._rescue_choice_override = Callable()
			var action = func():
				var pending = game._choice_prompt_stack.back()
				match mode:
					"close": pending.overlay.queue_free()
					"reset": game.reset_game_over_state()
					_: pending.overlay.find_children("*", "Button", true, false)[0].pressed.emit()
			action.call_deferred()
			var result = await suite.strike(game.players[1], victim)
			if mode == "accept":
				suite.check(result == true and victim.is_alive() and not victim.identity_revealed, "E03e-21c：真实杀伤害提交后贤者/救援正常保命，原杀结算完成")
			else:
				suite.check(result == GameManager.CHOICE_INVALID and victim.hp == 0 and victim.is_dying() and not victim.identity_revealed and victim.hand.size() == 2, "E03e-21c：真实杀保留已提交1点伤害，保命技术失效明确停止后续")
			await suite.process_frame
	for mode in ["accept", "close", "reset"]:
		prepare(TurnManager.Phase.JUDGE)
		game._rps_override = Callable()
		var child = game.players[0]
		child.hp = 2
		child.hand.assign([CardBase.create(CardData.CardSubType.STRIKE)])
		var parent = game.players[4]
		parent.general_name = "里奥·普利威尔"
		parent.hp = 0
		game.players[3].hp = 2
		var action = func():
			var pending = game._choice_prompt_stack.back()
			match mode:
				"close": pending.overlay.queue_free()
				"reset": game.reset_game_over_state()
				_: pending.overlay.find_children("*", "Button", true, false)[0].pressed.emit()
		action.call_deferred()
		var chain = game._new_damage_chain(game.players[1], parent, null, 1, EffectChain.DamageType.PHYSICAL)
		var result = await game._resolve_dying(parent, null, "test", chain)
		if mode == "accept":
			suite.check(result == 0 and parent.hp == 1 and child.is_alive() and game.players[3].is_dead(), "E03e-21c：预大习子贤者正常完成，父帧继续且仅统计自身直接死亡")
		else:
			suite.check(result == GameManager.CHOICE_INVALID and parent.is_dying() and child.hp == 0 and child.hand.size() == 1 and game.players[1].hp == 10 and game.players[3].hp == 2 and chain.continuation_invalid, "E03e-21c：预大习子窗口失效保留已扣2点，不继续扣后续角色或误救回父帧")
		suite.check(not game.yudaxi.is_active() and game._dying_contexts.is_empty(), "E03e-21c：正常/失效/重开退出预大习原栈，不残留旧濒死上下文")
		await suite.process_frame
	# 独立规则核心：旧await在重开后不能pop新帧或追加旧结果。
	var resolver = YudaxiResolver.new()
	var owner = game.players[1]
	var target = game.players[2]
	owner.hp = 0
	target.hp = 2
	var answer = ChoicePromptAnswer.new()
	var settle = func(_target): await answer.answered
	var restart_core = func():
		resolver.reset()
		await resolver.resolve(game.players[3], func(_owner): return [] as Array[Player], func(_target): pass, func(_owner, _count): pass, func(): return false, func(): pass)
		answer.submit(0)
	restart_core.call_deferred()
	await resolver.resolve(owner, func(_owner): return [target] as Array[Player], settle, func(_owner, _count): pass, func(): return false, func(): pass)
	suite.check(not resolver.is_active() and resolver.results.size() == 1 and resolver.results[0].owner == game.players[3], "E03e-21c：旧预大习await重开后不pop新栈/污染新结果")
	suite.reset_players()
	game._rps_override = Callable()
	game._sage_save_override = Callable()
	game = null
	suite = null
