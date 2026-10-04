extends RefCounted

var suite
var game: GameManager

func reset():
	suite.reset_players()
	game.deck._discard.clear()
	game.equipment_pool.clear()
	game._clear_pending_determined_card()
	game._liehuo_override = Callable()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game.turn_manager.current_player_idx = 1
	for p in game.players:
		p.judgment_cards.clear()

func drive(action: String):
	var pending = game._choice_prompt_stack.back()
	var buttons = pending.overlay.find_children("*", "Button", true, false)
	suite.check(game._countdown_active and game._countdown_on_timeout.is_valid(),
		"E03-R01c：盾响应按裁决有计时，超时不发动")
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
		"shield_moved":
			game.players[0].determined_cards.append(game.players[0].remove_equipment("armor"))
			buttons[0].pressed.emit()
		"ended": game._finish_game("平局", "E03e-3a回归")

func launch(timed: bool):
	if timed:
		await game._show_liehuo_prompt()
	else:
		await game._show_bloodthirsty_prompt(game.players[0], game.players[1])

func run(host):
	suite = host
	game = host.game
	var phase = game.turn_manager.current_phase
	var events: Array = []
	var collect = func(event): events.append(event)
	game.card_action_committed.connect(collect)
	for snatch in [false, true]:
		for concrete in [false, true]:
			for action in ["accept", "decline", "timeout", "close", "phase", "shield_moved", "ended"]:
				reset()
				events.clear()
				var target = game.players[0]
				var actor = game.players[1]
				target.hp = 3
				# 只有防具区有牌，AI真实选区必然选装备，不替换生产选区逻辑。
				var shield = CardBase.create(CardData.CardSubType.LIEHUO_SHIELD)
				target.equip_card_to_slot("armor", shield)
				var sub = CardData.CardSubType.SNATCH if snatch else CardData.CardSubType.DISMANTLE
				var original = CardBase.create(sub) if concrete else null
				actor.hand.append(original)
				drive.call_deferred(action)
				await game._play_steal_card(actor, target, snatch)
				suite.check(target.hp == (2 if action == "accept" else 3),
					"E03e-3a：盾仅接受时失去一次体力：" + action)
				if action in ["decline", "timeout"]:
					suite.check(target.get_equipment_card("armor") == null
						and (actor.determined_cards == [shield] if snatch else game.deck._discard.count(shield) == 1),
						"E03e-3a：拒绝盾继续真实拆/顺原牌")
				elif action == "shield_moved":
					suite.check(target.determined_cards == [shield] and actor.hand_size() == 0
						and not game.deck._discard.has(shield), "E03e-3a：原盾离区不扣血、不移动过期装备")
				else:
					suite.check(target.get_equipment_card("armor") == shield and actor.hand_size() == 0
						and not game.deck._discard.has(shield), "E03e-3a：防止/失效停止旧拆顺效果")
				suite.check(events.size() == 1 and game.deck._discard.size() == (2 if action in ["decline", "timeout"] and not snatch else 1)
					and (not concrete or game.deck._discard.count(original) == 1),
					"E03e-3a：已用锦囊费用/事件保留一次，不退款不重付")
				await suite.process_frame
				suite.check(game._choice_prompt_stack.is_empty(), "E03e-3a：盾等待已释放")
	# 关闭旧窗口后，旧按钮和共享信号不能替下一次作答。
	reset()
	var target = game.players[0]
	var shield = CardBase.create(CardData.CardSubType.LIEHUO_SHIELD)
	target.equip_card_to_slot("armor", shield)
	var old_click: Array = []
	var close_first = func():
		var pending = game._choice_prompt_stack.back()
		var button = pending.overlay.find_children("*", "Button", true, false)[0]
		old_click.append(button.get_signal_connection_list("pressed")[0].callable)
		old_click.append(game._countdown_on_timeout)
		drive("close")
	close_first.call_deferred()
	var first = await game._try_liehuo_nullify_result(target, CardData.CardSubType.SNATCH)
	suite.check(first == GameManager.LiehuoOutcome.INVALIDATED and target.hp == 10,
		"E03e-3a：关闭明确返回失效而非拒绝")
	await suite.process_frame
	var next = func():
		var pending = game._choice_prompt_stack.back()
		old_click[0].call()
		old_click[1].call()
		game._response_ready.emit()
		suite.check(not pending.answer.settled, "E03-R01c：旧按钮/旧超时/共享信号不回答新盾窗口")
		drive("accept")
	next.call_deferred()
	var second = await game._try_liehuo_nullify_result(target, CardData.CardSubType.SNATCH)
	suite.check(second == GameManager.LiehuoOutcome.PREVENTED and target.hp == 9,
		"E03e-3a：下一合法盾响应正常且仅扣一次")
	await suite.process_frame
	# 防御性嵌套：无计时窗口也须取得代次所有权，退出后恢复上一窗口原策略。
	for older_timed in [false, true]:
		for newer_first in [false, true]:
			reset()
			launch(older_timed)
			var older = game._choice_prompt_stack.back()
			game._step_remaining = 12.0
			var old_timeout = game._countdown_on_timeout
			launch(not older_timed)
			var newer = game._choice_prompt_stack.back()
			if old_timeout.is_valid(): old_timeout.call()
			suite.check(not older.answer.settled and not newer.answer.settled,
				"E03e-3a：旧计时不穿透嵌套盾等待")
			if newer_first:
				newer.answer.submit(0)
				suite.check(game._countdown_active == older_timed
					and (not older_timed or game._step_remaining == 12.0),
					"E03e-3a：恢复旧窗口原有计时策略/剩余时间")
				older.answer.submit(0)
			else:
				older.answer.submit(0)
				suite.check(game._countdown_active == not older_timed and not newer.answer.settled,
					"E03e-3a：旧窗口先结束不改变新窗口计时策略")
				newer.answer.submit(0)
			suite.check(game._choice_prompt_stack.is_empty(), "E03e-3a：两窗口各自清理")
			await suite.process_frame
	game.card_action_committed.disconnect(collect)
	reset()
	game.turn_manager.current_phase = phase
	suite = null
	game = null
