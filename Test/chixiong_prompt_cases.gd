extends RefCounted

var suite
var game: GameManager
var windows: Array = []

func reset():
	suite.reset_players()
	game.deck._discard.clear()
	game.equipment_pool.clear()
	game._clear_pending_determined_card()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game._chixiong_activate_override = Callable()
	game._chixiong_target_override = func(): return false
	game.players[0].gender = "男"
	game.players[1].gender = "女"

func drive(action: String, actor: Player, target: Player):
	var pending = game._choice_prompt_stack.back()
	windows.append(pending.overlay)
	var buttons = pending.overlay.find_children("*", "Button", true, false)
	suite.check(not game._countdown_active, "E03e-5a：雌雄发动窗口不新增倒计时")
	match action:
		"yes":
			buttons[0].pressed.emit()
			pending.answer.submit(0)
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
		"weapon":
			actor.determined_cards.append(actor.remove_equipment("weapon"))
			buttons[0].pressed.emit()
		"gender":
			target.gender = actor.gender
			buttons[0].pressed.emit()
		"target_dead", "source_dead":
			var dead = target if action == "target_dead" else actor
			dead.hp = 0
			dead.mark_dead() # 防御性生命周期注入，不声称此弹窗中有合法杀人时机。
			buttons[0].pressed.emit()
		"ended": game._finish_game("平局", "E03e-5a回归")

func run(host):
	suite = host
	game = host.game
	var genders: Array = []
	for p in game.players: genders.append(p.gender)
	for concrete in [false, true]:
		windows.clear()
		for action in ["yes", "no", "close", "phase", "actor", "weapon", "gender", "target_dead", "source_dead", "ended"]:
			reset()
			var actor = game.players[0]
			var target = game.players[1]
			actor.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.CHIXIONG_SHUANGGU))
			target.hand.append(null)
			var original = CardBase.create(CardData.CardSubType.STRIKE) if concrete else null
			if concrete: actor.determined_cards.append(original)
			else: actor.hand.append(null)
			drive.call_deferred(action, actor, target)
			await game.execute_card_on_target(target, CardData.CardSubType.STRIKE)
			var continued = action in ["yes", "no", "source_dead"]
			suite.check(target.hp == (0 if action == "target_dead" else (9 if continued else 10)),
				"E03e-5a：发动/拒绝继续杀，窗口失效停止旧链：" + action)
			suite.check(actor.hand_size() == (1 if action in ["yes", "weapon"] else 0) and target.hand_size() == 1,
				"E03e-5a：仅有效发动令来源摸牌，失效不触发目标选择：" + action)
			suite.check(game.deck._discard.size() == 1 and game.deck._discard[0].sub_type == CardData.CardSubType.STRIKE
				and (not concrete or game.deck._discard[0] == original), "E03e-5a：已用杀原实例仅入弃一次、不退款")
			suite.check(game._choice_prompt_stack.is_empty(), "E03e-5a：雌雄等待已结束")
		await suite.process_frame
		suite.check(windows.all(func(window): return not is_instance_valid(window)), "E03e-5a：全部窗口实际释放")
	# 旧按钮闭包/共享信号均不能答复下一次发动窗口。
	reset()
	var old: Array = []
	var capture = func():
		var pending = game._choice_prompt_stack.back()
		old.append(pending.overlay.find_children("*", "Button", true, false)[0].get_signal_connection_list("pressed")[0].callable)
		pending.overlay.queue_free()
	capture.call_deferred()
	suite.check(await game._ask_chixiong_activate("B") == game.CHOICE_INVALID, "E03e-5a：关闭不是主动不发动")
	await suite.process_frame
	var next = func():
		var pending = game._choice_prompt_stack.back()
		old[0].call()
		game._chixiong_activate_result.emit(true)
		suite.check(not pending.answer.settled, "E03e-5a：旧答复不污染新窗口")
		pending.overlay.find_children("*", "Button", true, false)[1].pressed.emit()
	next.call_deferred()
	suite.check(await game._ask_chixiong_activate("B") == 0, "E03e-5a：下一合法拒绝仍可完成")
	await suite.process_frame
	reset()
	for i in game.players.size(): game.players[i].gender = genders[i]
	game._chixiong_target_override = Callable()
	suite = null
	game = null
