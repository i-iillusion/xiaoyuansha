extends RefCounted

var suite
var game: GameManager
var windows: Array = []

func reset():
	suite.reset_players()
	game.deck._discard.clear()
	game._clear_pending_determined_card()
	game._paixiong_override = Callable()
	game._hand_discard_override = Callable()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	for p in game.players:
		p.hidden_equip_slot = ""
		p.hidden_equip_card = null

func drive(action: String, source: Player, victim: Player):
	var pending = game._choice_prompt_stack.back()
	windows.append(pending.overlay)
	var buttons = pending.overlay.find_children("*", "Button", true, false)
	suite.check(buttons.size() == 3 and buttons[-1].text == "取消" and game._countdown_active, "E03e-16b：拍胸脯原通用确认计时及取消按钮保留")
	match action:
		"close":
			pending.overlay.queue_free()
			return
		"phase", "phase_idle":
			game.turn_manager.current_phase = TurnManager.Phase.END
			game.turn_manager.current_phase = TurnManager.Phase.PLAY
			if action == "phase_idle": return
		"actor":
			game.turn_manager.play_actor_idx = 2
			game.turn_manager.play_actor_idx = 1
		"source_dead", "victim_dead":
			var dead = source if action == "source_dead" else victim
			dead.hp = 0
			dead.mark_dead()
		"ended":
			game._finish_game("平局", "拍胸脯确认回归")
			return
		"timeout":
			game._countdown_on_timeout.call()
			return
	buttons[2 if action == "cancel" else (1 if action == "no" else 0)].pressed.emit()
	pending.answer.submit(0)

func run(host):
	suite = host
	game = host.game
	var events: Array = []
	var collect = func(event): events.append(event)
	game.card_action_committed.connect(collect)
	for concrete in [false, true]:
		for fee_concrete in [false, true]:
			for action in ["yes", "refuse", "no", "cancel", "timeout", "close", "phase", "phase_idle", "actor", "source_dead", "victim_dead", "ended"]:
				reset()
				events.clear()
				var source = game.players[1]
				var victim = game.players[0]
				victim.general_name = "史蒂芬·彼特先斯"
				victim.hand.assign([null, null]) # 防止夹具意外启动另一觉醒窗口。
				var fee = CardBase.create(CardData.CardSubType.PEACH) if fee_concrete else null
				source.hand.append(fee)
				var kill = CardBase.create(CardData.CardSubType.STRIKE) if concrete else null
				if concrete:
					source.determined_cards.append(kill)
					game._pending_determined_card = kill
				else: source.hand.append(null)
				source.wine_stacks = 2
				game.turn_manager.play_actor_idx = 1
				if action == "refuse": game._hand_discard_override = func(_snapshot, _count, _mandatory): return []
				drive.call_deferred(action, source, victim)
				await game.execute_card_on_target(victim, CardData.CardSubType.STRIKE)
				var damaged = action in ["yes", "no", "cancel", "timeout", "source_dead"]
				suite.check(victim.hp == (0 if action == "victim_dead" else (7 if damaged else 10)), "E03e-16b：弃一张后整次3伤正常，拒付防止整次，失效停止旧链")
				suite.check(source.hand_size() == (0 if action == "yes" else 1) and (not fee_concrete or game.deck._discard.count(fee) == (1 if action == "yes" else 0)), "E03e-16b：仅有效发动且选择支付弃一张原牌，不按伤害点收费")
				suite.check(events.size() == 1 and (not concrete or game.deck._discard.count(kill) == 1), "E03e-16b：杀费用已提交不回滚/不重复")
				suite.check(victim.hand_size() == 2 and not victim.awoken, "E03e-16b：确认不误支付受伤者手牌或触发觉醒")
				suite.check(game._choice_prompt_stack.is_empty(), "E03e-16b：拍胸确认等待清理")
				await suite.process_frame
	suite.check(windows.all(func(window): return not is_instance_valid(window)), "E03e-16b：确认窗口实际释放")
	game.card_action_committed.disconnect(collect)
	reset()
	var old: Array = []
	var capture = func():
		var pending = game._choice_prompt_stack.back()
		old.append(pending.overlay.find_children("*", "Button", true, false)[0].get_signal_connection_list("pressed")[0].callable)
		old.append(game._countdown_on_timeout)
		pending.overlay.queue_free()
	capture.call_deferred()
	suite.check(await game._show_paixiong_prompt("A") == GameManager.CHOICE_INVALID, "E03e-16b：拍胸确认关闭是失效，不是自愿不发动")
	await suite.process_frame
	var next = func():
		var pending = game._choice_prompt_stack.back()
		old[0].call()
		old[1].call()
		suite.check(not pending.answer.settled and game._countdown_active, "E03e-16b：旧按钮/超时不污染下一合法拍胸确认")
		pending.overlay.find_children("*", "Button", true, false)[1].pressed.emit()
	next.call_deferred()
	suite.check(await game._show_paixiong_prompt("A") == 0, "E03e-16b：下一合法确认仍可不发动")
	await suite.process_frame
	reset()
	suite = null
	game = null
