extends RefCounted

var suite
var game: GameManager
var before_choice: Callable
var windows: Array = []

func reset():
	suite.reset_players()
	game.deck._discard.clear()
	game.equipment_pool.clear()
	game._clear_pending_determined_card()
	game._zhangba_override = Callable()
	before_choice = Callable()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	for p in game.players:
		p.judgment_cards.clear()
		p.identity = "主公" if p.seat_index == 4 else "忠臣"
	game.players[3].identity = "反贼"

func drive(action: String):
	var pending = game._choice_prompt_stack.back()
	windows.append(pending.overlay)
	var buttons = pending.overlay.find_children("*", "Button", true, false)
	suite.check(not game._countdown_active and not game._countdown_on_timeout.is_valid(),
		"E03e-4：丈八保持原无倒计时策略")
	match action:
		"one", "two", "three":
			var x = 1 if action == "one" else (2 if action == "two" else 3)
			if before_choice.is_valid(): before_choice.call()
			buttons[x].pressed.emit()
			pending.answer.submit(3) # 重复答复不能追加费用或改变已选X。
		"decline": buttons[0].pressed.emit()
		"close": pending.overlay.queue_free()
		"phase":
			game.turn_manager.current_phase = TurnManager.Phase.END
			game.turn_manager.current_phase = TurnManager.Phase.PLAY
			buttons[2].pressed.emit()
		"actor":
			game.turn_manager.play_actor_idx = 1
			game.turn_manager.play_actor_idx = -1
			buttons[2].pressed.emit()
		"weapon", "same_weapon":
			game.players[0].determined_cards.append(game.players[0].remove_equipment("weapon"))
			if action == "same_weapon":
				# 防御性同名换实例注入，不声称是合法造出第二把唯一武器。
				game.players[0].equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.ZHANGBA_SPEAR))
			buttons[2].pressed.emit()
		"target_dead":
			game.players[1].hp = 0
			game.players[1].mark_dead()
			buttons[2].pressed.emit()
		"source_dead":
			game.players[0].hp = 0
			game.players[0].mark_dead()
			buttons[2].pressed.emit()
		"hand":
			game.players[0].hand.append(null)
			buttons[2].pressed.emit()
		"ended": game._finish_game("平局", "E03e-4回归")

func run(host):
	suite = host
	game = host.game
	var phase = game.turn_manager.current_phase
	var identities: Array = []
	for p in game.players: identities.append(p.identity)
	var events: Array = []
	var collect = func(event): events.append(event)
	game.card_action_committed.connect(collect)
	for concrete in [false, true]:
		windows.clear()
		for action in ["one", "two", "three", "decline", "close", "phase", "actor", "weapon", "same_weapon", "target_dead", "source_dead", "hand", "ended"]:
			reset()
			events.clear()
			var actor = game.players[0]
			var target = game.players[1]
			var weapon = CardBase.create(CardData.CardSubType.ZHANGBA_SPEAR)
			actor.equip_card_to_slot("weapon", weapon)
			var original = CardBase.create(CardData.CardSubType.STRIKE) if concrete else null
			if concrete: actor.determined_cards.append(original)
			else: actor.hand.append(null)
			drive.call_deferred(action)
			await game.execute_card_on_target(target, CardData.CardSubType.STRIKE)
			var x = 1 if action == "one" else (3 if action == "three" else (2 if action in ["two", "hand"] else 0))
			var continued = action in ["one", "two", "three", "decline", "hand", "source_dead"]
			suite.check(actor.hp == (0 if action == "source_dead" else 10 - x),
				"E03e-4：丈八选定体力费用仅支付一次，失效不付费：" + action)
			suite.check(target.hp == (0 if action == "target_dead" else (9 - x if continued else 10)),
				"E03e-4：放弃/加伤/失效各有正确真实杀结果：" + action)
			suite.check(events.size() == 1 and game.deck._discard.size() == 1
				and game.deck._discard[0].sub_type == CardData.CardSubType.STRIKE
				and (not concrete or game.deck._discard[0] == original),
				"E03e-4：已用杀原牌与事件恰好一次，窗口失效不返还杀")
			suite.check(actor.hand_size() == (1 if action in ["weapon", "same_weapon", "hand"] else 0),
				"E03e-4：丈八不把流失体力误作手牌费用或返牌")
			suite.check(game._choice_prompt_stack.is_empty()
				and (not is_instance_valid(windows.back()) or windows.back().is_queued_for_deletion()),
				"E03e-4：真实丈八窗口完成等待且已请求释放")
		# 接受等同步完成路径无需逐例空等一帧；统一确认每个旧节点均实际销毁。
		await suite.process_frame
		suite.check(windows.all(func(window): return not is_instance_valid(window)),
			"E03e-4：本批所有丈八窗口节点均实际释放")
	# 原链经过统一求救：支付致死后不再核验已离区武器，也不能吞掉已付加伤。
	for outcome in ["saved", "dead", "phase", "target_dead", "ended"]:
		reset()
		var actor = game.players[0]
		var target = game.players[1]
		actor.hp = 2
		actor.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.ZHANGBA_SPEAR))
		if outcome == "saved":
			target.determined_cards.append(CardBase.create(CardData.CardSubType.PEACH))
			game._rescue_choice_override = func(rescuer, _dying, options):
				return CardData.CardSubType.PEACH if rescuer == target and options.has(CardData.CardSubType.PEACH) else -1
		var paid: Array = []
		if outcome in ["phase", "target_dead", "ended"]:
			var invalidate = func(context, _stage):
				paid.append([context.victim, context.victim.hp, context.cause])
				actor.hp = 1 # 故障注入：模拟死亡前规则救回，不作为预大习实现验收。
				match outcome:
					"phase":
						game.turn_manager.current_phase = TurnManager.Phase.END
						game.turn_manager.current_phase = TurnManager.Phase.PLAY
					"target_dead":
						target.hp = 0
						target.mark_dead()
					"ended": game._finish_game("平局", "E03e-4支付后回归")
			# 在丈八答复前入队，下一检查点才是费用后的before_death。
			before_choice = func(): game.rule_scheduler.enqueue("丈八费用后失效注入", invalidate)
		drive.call_deferred("two")
		var chain = game._new_damage_chain(actor, target, CardBase.create(CardData.CardSubType.STRIKE), 1, EffectChain.DamageType.PHYSICAL)
		await chain.start()
		if outcome in ["saved", "dead"]:
			suite.check(chain.damage.committed and chain.damage.applied_amount == 3 and target.hp == 7
				and chain.damage.source == (actor if outcome == "saved" else null),
				"E03e-4：费用后救回/最终死亡仍合并三点伤害，死亡余伤无源：" + outcome)
			suite.check(actor.hp == (1 if outcome == "saved" else 0) and actor.is_dead() == (outcome == "dead"),
				"E03e-4：真实求救不重付丈八体力")
		else:
			suite.check(paid == [[actor, 0, "zhangba"]] and actor.hp == 1 and not chain.damage.committed
				and chain.is_cancelled and target.hp == (0 if outcome == "target_dead" else 10),
				"E03e-4：支付后上下文失效停止伤害，不退款或再支付：" + outcome)
		await suite.process_frame
	# 旧窗口的按钮和共享丈八信号不能回答下一次窗口。
	reset()
	game.players[0].equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.ZHANGBA_SPEAR))
	var old_click: Array = []
	var capture = func():
		var pending = game._choice_prompt_stack.back()
		var button = pending.overlay.find_children("*", "Button", true, false)[3]
		old_click.append(button.get_signal_connection_list("pressed")[0].callable)
		drive("close")
	capture.call_deferred()
	await suite.strike(game.players[0], game.players[1])
	await suite.process_frame
	var second = func():
		var pending = game._choice_prompt_stack.back()
		old_click[0].call()
		game._zhangba_result.emit(3)
		suite.check(not pending.answer.settled, "E03e-4：旧按钮/旧丈八信号不替新窗口作答")
		drive("one")
	second.call_deferred()
	await suite.strike(game.players[0], game.players[1])
	suite.check(game.players[0].hp == 9 and game.players[1].hp == 8,
		"E03e-4：关闭旧窗口后下一次合法丈八仅加一次伤害")
	await suite.process_frame
	game.card_action_committed.disconnect(collect)
	reset()
	for i in game.players.size(): game.players[i].identity = identities[i]
	game.turn_manager.current_phase = phase
	suite = null
	game = null
