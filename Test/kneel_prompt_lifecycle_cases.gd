extends "res://Test/play_skill_selection_generation_cases.gd"

func prepare(release: bool):
	reset("布鲁斯·萨维奇")
	game._kneel_override = Callable()
	game.players[0].hand.clear()
	game.players[0].kneeling = release
	game.players[0].kneel_used = release
	game.turn_manager.current_player_idx = 0 if release else 1
	game.turn_manager.current_phase = TurnManager.Phase.DRAW

func run(host):
	suite = host
	game = host.game
	for release in [false, true]:
		for mode in ["accept", "decline", "close", "phase", "dead", "general", "end", "duplicate", "old_signal"] + ([] if release else ["hand", "full_hp", "own_turn"]):
			prepare(release)
			var actor = game.players[0]
			var act = func():
				var pending = game._choice_prompt_stack.back()
				var buttons = pending.overlay.find_children("*", "Button", true, false)
				suite.check(buttons.size() == 2 and not game._countdown_active, "E03e-19：下跪确认保留无计时/两个按钮")
				match mode:
					"decline": buttons[1].pressed.emit()
					"close": pending.overlay.queue_free()
					"phase": game.turn_manager.current_phase = TurnManager.Phase.JUDGE
					"dead": actor.mark_dead()
					"general": actor.general_name = "稻草人"
					"end": game._game_over = true
					"hand": actor.hand.append(null)
					"full_hp": actor.hp = actor.max_hp
					"own_turn": game.turn_manager.current_player_idx = 0
					"duplicate":
						var owner = game._kneel_execution_owner
						var count = game._choice_prompt_stack.size()
						await game._on_detail_skill_clicked("下跪", actor)
						suite.check(game._kneel_execution_owner == owner and game._choice_prompt_stack.size() == count, "E03e-19：重复详情点击不叠确认/不改执行锁")
					"old_signal":
						game._kneel_cfm_result.emit(true)
						suite.check(not pending.answer.settled, "E03e-19：旧共享下跪信号不回答实际窗口")
				if mode not in ["decline", "close"]: buttons[0].pressed.emit()
			act.call_deferred()
			await game._on_detail_skill_clicked("下跪", actor)
			var confirmed = mode in ["accept", "duplicate", "old_signal"]
			suite.check(actor.kneeling == (not release if confirmed else release) and actor.kneel_used == (release or confirmed) and game._kneel_execution_owner == -1, "E03e-19：仅有效确认写入限定状态，拒绝/过期不误发动或解除")
			await suite.process_frame
	prepare(false)
	var actor = game.players[0]
	var finished: Array = [false]
	var restart = func():
		var old_callback = game._choice_prompt_stack.back().overlay.find_children("*", "Button", true, false)[0].get_signal_connection_list("pressed")[0].callable
		game.reset_game_over_state()
		var finish_new = func():
			var owner = game._kneel_execution_owner
			old_callback.call()
			suite.check(owner != -1 and game._kneel_execution_owner == owner and not actor.kneeling and not actor.kneel_used and not game._choice_prompt_stack.back().answer.settled, "E03e-19：同人物同阶段重开，旧确认不写新限定状态或清新锁")
			game._choice_prompt_stack.back().overlay.find_children("*", "Button", true, false)[0].pressed.emit()
		finish_new.call_deferred()
		await game._on_detail_skill_clicked("下跪", actor)
		finished[0] = true
	restart.call_deferred()
	await game._on_detail_skill_clicked("下跪", actor)
	while not finished[0]: await suite.process_frame
	suite.check(actor.kneeling and actor.kneel_used and game._kneel_execution_owner == -1, "E03e-19：重开仅新确认正常发动下跪一次")
	await suite.process_frame
	prepare(true)
	game._kneel_override = func(): return GameManager.CHOICE_INVALID
	await game._on_detail_skill_clicked("下跪", game.players[0])
	suite.check(game.players[0].kneeling, "E03e-19：旧bool钩子整数失效不转为确认解除")
	reset("稻草人")
	game._kneel_override = Callable()
	game._rps_override = Callable()
	suite = null
	game = null
