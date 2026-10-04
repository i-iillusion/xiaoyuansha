extends RefCounted

var suite
var game: GameManager
var windows: Array = []

func reset():
	suite.reset_players()
	game.deck._discard.clear()
	game.equipment_pool.clear()
	game._clear_pending_determined_card()
	game._guanshi_override = Callable()
	game._guanshi_mount_override = func(): return "mount_1"
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	for p in game.players:
		p.mount_plus = 0
		p.mount_minus = 0

func drive(action: String, actor: Player, target: Player):
	var pending = game._choice_prompt_stack.back()
	windows.append(pending.overlay)
	var buttons = pending.overlay.find_children("*", "Button", true, false)
	suite.check(not game._countdown_active, "E03e-7a：贯石确认沿用无倒计时")
	match action:
		"yes":
			buttons[0].pressed.emit()
			pending.answer.submit(1)
		"no": buttons[1].pressed.emit()
		"close": pending.overlay.queue_free()
		"phase":
			game.turn_manager.current_phase = TurnManager.Phase.END
			game.turn_manager.current_phase = TurnManager.Phase.PLAY
			buttons[0].pressed.emit()
		"actor":
			game.turn_manager.play_actor_idx = 1
			game.turn_manager.play_actor_idx = -1
			buttons[0].pressed.emit()
		"weapon", "same_weapon":
			actor.determined_cards.append(actor.remove_equipment("weapon"))
			if action == "same_weapon":
				actor.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.GUANSHI_AXE))
			buttons[0].pressed.emit()
		"mount":
			actor.determined_cards.append(actor.remove_equipment("mount_1"))
			buttons[0].pressed.emit()
		"armor":
			target.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.QINGGANG_SHIELD))
			buttons[0].pressed.emit()
		"source_dead", "target_dead":
			var dead = actor if action == "source_dead" else target
			dead.hp = 0
			dead.mark_dead()
			buttons[0].pressed.emit()
		"ended": game._finish_game("平局", "E03e-7a回归")

func run(host):
	suite = host
	game = host.game
	var events: Array = []
	var collect = func(event): events.append(event)
	game.card_action_committed.connect(collect)
	for concrete in [false, true]:
		windows.clear()
		for action in ["yes", "no", "close", "phase", "actor", "weapon", "same_weapon", "mount", "armor", "source_dead", "target_dead", "ended"]:
			reset()
			events.clear()
			var actor = game.players[0]
			var target = game.players[1]
			actor.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.GUANSHI_AXE))
			var mount = CardBase.create(CardData.CardSubType.MOUNT_MINUS)
			actor.equip_card_to_slot("mount_1", mount)
			var kill = CardBase.create(CardData.CardSubType.STRIKE) if concrete else null
			var dodge = CardBase.create(CardData.CardSubType.DODGE) if concrete else null
			if concrete:
				actor.determined_cards.append(kill)
				target.determined_cards.append(dodge)
			else:
				actor.hand.append(null)
				target.hand.append(null)
			var responses: Array = []
			game._dodge_override = func():
				responses.append(true)
				return true
			drive.call_deferred(action, actor, target)
			await game.execute_card_on_target(target, CardData.CardSubType.STRIKE)
			suite.check(target.hp == (0 if action == "target_dead" else (9 if action == "yes" else 10)),
				"E03e-7a：仅有效贯石使已被闪抵消的杀命中：" + action)
			suite.check(game.deck._discard.count(mount) == (1 if action == "yes" else 0),
				"E03e-7a：确认失效或拒绝不支付坐骑费用：" + action)
			suite.check(game.deck._discard.size() == (3 if action == "yes" else 2)
				and (not concrete or (game.deck._discard.count(kill) == 1 and game.deck._discard.count(dodge) == 1)),
				"E03e-7a：实际杀闪只入弃一次，不因失效退款")
			suite.check(events.size() == 2 and responses.size() == 1 and target.hand_size() == 0,
				"E03e-7a：杀闪各一次用牌事件，强制命中不重开闪窗口")
			suite.check(game._choice_prompt_stack.is_empty(), "E03e-7a：确认等待结束")
		await suite.process_frame
		suite.check(windows.all(func(window): return not is_instance_valid(window)), "E03e-7a：确认窗口实际释放")
	game.card_action_committed.disconnect(collect)
	reset()
	var old: Array = []
	var capture = func():
		var pending = game._choice_prompt_stack.back()
		old.append(pending.overlay.find_children("*", "Button", true, false)[0].get_signal_connection_list("pressed")[0].callable)
		pending.overlay.queue_free()
	capture.call_deferred()
	suite.check(await game._ask_guanshi("B") == game.CHOICE_INVALID, "E03e-7a：关闭确认返回失效")
	await suite.process_frame
	var next = func():
		var pending = game._choice_prompt_stack.back()
		old[0].call()
		game._guanshi_result.emit(true)
		suite.check(not pending.answer.settled, "E03e-7a：旧按钮和旧共享信号不污染下一窗口")
		pending.overlay.find_children("*", "Button", true, false)[1].pressed.emit()
	next.call_deferred()
	suite.check(await game._ask_guanshi("B") == 0, "E03e-7a：下一次合法拒绝可完成")
	await suite.process_frame
	for result in [true, false, -2]:
		game._guanshi_override = func(): return result
		suite.check(await game._ask_guanshi("B") == (-2 if typeof(result) == TYPE_INT else (1 if result else 0)),
			"E03e-7a：旧bool钩子兼容整数失效值")
	reset()
	game._guanshi_mount_override = Callable()
	suite = null
	game = null
