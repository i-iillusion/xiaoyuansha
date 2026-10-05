extends RefCounted

var suite
var game: GameManager
var windows: Array = []

func reset():
	suite.reset_players()
	game.deck._discard.clear()
	game._clear_pending_determined_card()
	game._exit_zhuangbi_mode()
	game._zhuangbi_blocked_this_phase = false
	game._zhuangbi_again_override = Callable()
	game._hand_discard_override = func(_snapshot, _count, _mandatory): return [0]
	game._rps_override = func(p): return GameManager.RPS_ROCK if p.seat_index == 0 else GameManager.RPS_SCISSORS
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game.turn_manager.play_actor_idx = 0
	for p in game.players:
		p.hidden_equip_slot = ""
		p.hidden_equip_card = null

func drive(action: String, actor: Player):
	var pending = game._choice_prompt_stack.back()
	windows.append(pending.overlay)
	var buttons = pending.overlay.find_children("*", "Button", true, false)
	suite.check(buttons.size() == 3 and game._countdown_active, "E03e-16c：再发动确认保留通用计时及取消按钮")
	var labels = pending.overlay.find_children("*", "Label", true, false)
	suite.check(labels.any(func(label): return label.text.contains("装逼成功")) and not labels.any(func(label): return label.text.contains("一半及以上")), "E03e-16c：再发动窗口以成功结果提示，不另写判胜阈值")
	match action:
		"close":
			pending.overlay.queue_free()
			return
		"timeout":
			game._countdown_on_timeout.call()
			return
		"phase", "phase_idle":
			game.turn_manager.current_phase = TurnManager.Phase.END
			game.turn_manager.current_phase = TurnManager.Phase.PLAY
			if action == "phase_idle": return
		"actor":
			game.turn_manager.play_actor_idx = 1
			game.turn_manager.play_actor_idx = 0
		"dead":
			actor.hp = 0
			actor.mark_dead()
		"skill": actor.general_name = "稻草人"
		"ended":
			game._finish_game("平局", "装逼再发动窗口测试")
			return
	buttons[2 if action == "cancel" else (1 if action == "no" else 0)].pressed.emit()
	pending.answer.submit(0)

func run(host):
	suite = host
	game = host.game
	for concrete in [false, true]:
		for action in ["yes", "no", "cancel", "timeout", "close", "phase", "phase_idle", "actor", "dead", "skill", "ended"]:
			reset()
			var actor = game.players[0]
			var target = game.players[1]
			actor.general_name = "史蒂芬·彼特先斯"
			var source_fee = CardBase.create(CardData.CardSubType.PEACH) if concrete else null
			var target_fee = CardBase.create(CardData.CardSubType.DODGE) if concrete else null
			actor.hand.assign([source_fee, null])
			target.hand.assign([target_fee])
			drive.call_deferred(action, actor)
			await game._execute_zhuangbi([target])
			suite.check(game._is_zhuangbi_targeting == (action == "yes"), "E03e-16c：只有合法主动同意才重新进入装逼选目标")
			suite.check(target.hp == 9, "E03e-16c：确认失效不回滚已造成的成功伤害")
			suite.check(actor.hand_size() == 1 and target.hand_size() == 0 and not actor.awoken, "E03e-16c：双方原费用只付一次，再发动确认不收费")
			if concrete:
				suite.check(game.deck._discard.count(source_fee) == 1 and game.deck._discard.count(target_fee) == 1, "E03e-16c：双方具体费用原实例各入弃一次")
			suite.check(game._choice_prompt_stack.is_empty(), "E03e-16c：再发动确认清理独立等待")
			await suite.process_frame
	suite.check(windows.all(func(window): return not is_instance_valid(window)), "E03e-16c：确认节点实际释放")
	reset()
	var old: Array = []
	var capture = func():
		var pending = game._choice_prompt_stack.back()
		old.append(pending.overlay.find_children("*", "Button", true, false)[0].get_signal_connection_list("pressed")[0].callable)
		old.append(game._countdown_on_timeout)
		pending.overlay.queue_free()
	capture.call_deferred()
	suite.check(await game._show_zhuangbi_again_prompt() == GameManager.CHOICE_INVALID, "E03e-16c：关闭明确失效，不是假装自愿收手")
	await suite.process_frame
	var next = func():
		var pending = game._choice_prompt_stack.back()
		old[0].call()
		old[1].call()
		suite.check(not pending.answer.settled and game._countdown_active, "E03e-16c：旧按钮/超时不污染下一合法再发动确认")
		pending.overlay.find_children("*", "Button", true, false)[1].pressed.emit()
	next.call_deferred()
	suite.check(await game._show_zhuangbi_again_prompt() == 0, "E03e-16c：下一窗口仍可主动收手")
	await suite.process_frame
	reset()
	var actor = game.players[0]
	var target = game.players[1]
	actor.general_name = "史蒂芬·彼特先斯"
	actor.hand.assign([null, null])
	target.hand.assign([null])
	game._zhuangbi_again_override = func(): return GameManager.CHOICE_INVALID
	await game._execute_zhuangbi([target])
	suite.check(not game._is_zhuangbi_targeting and target.hp == 9, "E03e-16c：旧bool钩子的-2不是同意，已结算伤害保留")
	reset()
	game._rps_override = Callable()
	game._hand_discard_override = Callable()
	suite = null
	game = null
