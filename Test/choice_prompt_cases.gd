extends RefCounted

var suite
var game: GameManager
var results: Array = []

func launch(grid: bool, tag: String):
	var result: int
	if grid:
		result = await game._show_sao_reveal_picker(["选择甲", "选择乙"])
	else:
		result = await game._show_choice_popup("E03b窗口", ["选择甲", "选择乙"])
	results.append([tag, result])

func run(host):
	suite = host
	game = host.game
	var tm = game.turn_manager
	var old_phase = tm.current_phase
	for grid in [false, true]:
		for outcome in ["accept", "cancel", "timeout", "close", "phase", "actor", "game_over"]:
			suite.reset_players()
			tm.current_phase = TurnManager.Phase.PLAY
			results.clear()
			launch(grid, outcome)
			suite.check(game._choice_prompt_stack.size() == 1, "E03b：真实选择窗口登记独立等待")
			if game._choice_prompt_stack.is_empty():
				continue
			var pending = game._choice_prompt_stack[0]
			var overlay: Control = pending.overlay
			var buttons = overlay.find_children("*", "Button", true, false)
			var old_click: Callable = buttons[0].get_signal_connection_list("pressed")[0].callable
			var old_timeout: Callable = game._countdown_on_timeout
			match outcome:
				"accept":
					buttons[1].pressed.emit()
					old_click.call() # 同帧重复答复不能改为第一个按钮。
				"cancel": buttons[2].pressed.emit()
				"timeout": old_timeout.call()
				"close": overlay.queue_free()
				"phase":
					tm.current_phase = TurnManager.Phase.END
					tm.current_phase = TurnManager.Phase.PLAY
					old_click.call() # 不等下一帧也须核验代次。
				"actor":
					tm.play_actor_idx = 1
				"game_over": game._finish_game("平局", "E03b回归")
			for i in range(3):
				await game.get_tree().process_frame
			var expected = 1 if outcome == "accept" else (-1 if outcome in ["cancel", "timeout"] else GameManager.CHOICE_INVALID)
			suite.check(results == [[outcome, expected]], "E03b：接受/取消/超时与失效分别返回且只答复一次：" + outcome)
			suite.check(not is_instance_valid(overlay) and game._choice_prompt_stack.is_empty(),
				"E03b：结束的真实窗口释放且移除等待登记")
			if outcome == "game_over":
				suite.check(not game._countdown_active, "E03b：终局不恢复阶段倒计时")
			# 新窗口不接收旧按钮与旧超时回调。
			suite.reset_players()
			tm.current_phase = TurnManager.Phase.PLAY
			results.clear()
			launch(not grid, "next")
			old_click.call()
			old_timeout.call()
			suite.check(results.is_empty() and game._choice_prompt_stack.size() == 1,
				"E03b：旧按钮/超时不关闭或答复下一窗口")
			game._choice_prompt_stack[0].answer.submit(0)
			await game.get_tree().process_frame
			suite.check(results == [["next", 0]], "E03b：下一合法选择能独立完成")
	# 防御性重叠等待：任意一方先完成都不替另一方答复，计时归当前窗口。
	for newer_first in [false, true]:
		suite.reset_players()
		tm.current_phase = TurnManager.Phase.PLAY
		results.clear()
		launch(false, "older")
		game._step_remaining = 12.0
		var older = game._choice_prompt_stack[0]
		launch(true, "newer")
		var newer = game._choice_prompt_stack[1]
		var generation = game._countdown_generation
		if newer_first:
			newer.answer.submit(1)
			suite.check(results == [["newer", 1]] and game._step_remaining == 12.0,
				"E03b：新窗口先结束恢复旧窗口剩余时间，不重置每步时间")
			older.answer.submit(0)
		else:
			older.answer.submit(0)
			suite.check(results == [["older", 0]] and game._countdown_generation == generation,
				"E03b：旧窗口先结束不停止新窗口计时")
			newer.answer.submit(1)
		suite.check(results.size() == 2 and game._choice_prompt_stack.is_empty()
			and game._countdown_active, "E03b：两次独立答复完成后恢复出牌计时")
		await game.get_tree().process_frame
	# 觉醒失效不能被包装器转成永久免疫选项。
	suite.reset_players()
	tm.current_phase = TurnManager.Phase.PLAY
	var invalidate = func(): game._choice_prompt_stack[0].overlay.queue_free()
	invalidate.call_deferred()
	var awakening = await game._show_awaken_pick()
	suite.check(awakening == GameManager.CHOICE_INVALID, "E03b：觉醒窗口被销毁返回失效，不暗选永久效果")
	suite.reset_players()
	tm.current_phase = old_phase
