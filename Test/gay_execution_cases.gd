extends RefCounted

var suite
var game: GameManager

func reset():
	suite.reset_players()
	game.deck._discard.clear()
	game._gay_used = false
	game._gay_x_override = Callable()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game.turn_manager.play_actor_idx = 0
	var actor = game.players[0]
	var target = game.players[1]
	actor.general_name = "比尔·盖伊"
	actor.gender = "male"
	target.gender = "male"
	actor.hp = 1
	target.hp = 1
	actor.hand.assign([null, null, null])

func run(host):
	suite = host
	game = host.game
	for close in [false, true]:
		reset()
		var actor = game.players[0]
		var target = game.players[1]
		var duplicate = func():
			var pending = game._choice_prompt_stack.back()
			var owner = game._gay_execution_owner
			await game._execute_gay(actor, target)
			suite.check(game._choice_prompt_stack.size() == 1 and game._gay_execution_owner == owner and actor.hand_size() == 3, "E03e-17b-1：重复Gay执行不叠窗口、不付费用、不释放原锁")
			if close: pending.overlay.queue_free()
			else: pending.overlay.find_children("*", "Button", true, false)[1].pressed.emit()
		duplicate.call_deferred()
		await game._execute_gay(actor, target)
		suite.check(game._gay_execution_owner == -1 and game._choice_prompt_stack.is_empty(), "E03e-17b-1：成功/关闭均释放自己的执行锁")
		suite.check(actor.hand_size() == (3 if close else 1) and actor.hp == (1 if close else 3) and target.hp == actor.hp and game._gay_used == (not close), "E03e-17b-1：仅原有效Gay支付/回复一次，关闭不占次数")
		await suite.process_frame
	reset()
	var actor = game.players[0]
	var target = game.players[1]
	var stale: Array = []
	var restart = func():
		var old = game._choice_prompt_stack.back()
		stale.append(old.overlay.find_children("*", "Button", true, false)[1].get_signal_connection_list("pressed")[0].callable)
		stale.append(game._countdown_on_timeout)
		game.reset_game_over_state() # 同一人物/PLAY仍在，不能仅靠阶段与人物辨认旧执行。
		var settle_new = func():
			var current = game._choice_prompt_stack.back()
			var owner = game._gay_execution_owner
			stale[0].call()
			stale[1].call()
			game._response_ready.emit()
			await suite.process_frame
			suite.check(game._gay_execution_owner == owner and not current.answer.settled and game._countdown_active, "E03e-17b-1：重开后旧执行清理/按钮/超时不清新锁或污染新窗口")
			current.overlay.find_children("*", "Button", true, false)[1].pressed.emit()
		settle_new.call_deferred()
		await game._execute_gay(actor, target)
		suite.check(actor.hp == 3 and target.hp == 3 and actor.hand_size() == 1 and game._gay_used, "E03e-17b-1：重开后的唯一新执行正常支付回血一次")
	restart.call_deferred()
	await game._execute_gay(actor, target)
	# 新执行可能仍在等待；等它的独立窗口按上述驱动完成。
	while game._gay_execution_owner != -1:
		await suite.process_frame
	suite.check(game._choice_prompt_stack.is_empty() and actor.hand_size() == 1 and actor.hp == 3, "E03e-17b-1：旧执行不额外支付，所有等待清理")
	await suite.process_frame
	reset()
	suite = null
	game = null
