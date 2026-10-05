extends "res://Test/play_skill_selection_generation_cases.gd"

func prepare(stage: String, option: int = 1):
	reset("麦克斯·欧尼斯特")
	game.turn_manager.current_player_idx = 0
	game.turn_manager.current_phase = TurnManager.Phase.START
	game.turn_manager.skip_full_turn = false
	game.turn_manager.granted_judge_target_idx = -1
	game.turn_manager.granted_draw_target_idx = -1
	game.turn_manager.granted_play_target_idx = -1
	game.players[1].judgment_cards.assign([CardBase.create(CardData.CardSubType.INDULGENCE)])
	game._meiyong_override = Callable() if stage == "activate" else func(): return true
	game._meiyong_option_override = Callable() if stage == "option" else func(): return option
	game._meiyong_target_override = Callable() if stage == "target" else func(): return game.players[1]

func run(host):
	suite = host
	game = host.game
	# TURN-03/Q3：真实等待窗口之间传递基础读条，不重置为30秒。
	prepare("activate")
	var remaining: Array = [30.0]
	var first = Control.new()
	game.get_node("UI").add_child(first)
	var first_answer = ChoicePromptAnswer.new()
	var confirm = func():
		game._step_remaining = 5.0
		first_answer.submit(0)
	confirm.call_deferred()
	suite.check(await game._wait_choice_prompt(first, first_answer, Callable(), true, 30.0, remaining) == 0 and remaining[0] == 5.0, "E03e-20c-0：确认前消耗25秒保存剩余5秒")
	var second = Control.new()
	game.get_node("UI").add_child(second)
	var second_answer = ChoicePromptAnswer.new()
	var finish = func():
		suite.check(game._step_remaining == 5.0 and game._countdown_active, "E03e-20c-0：下一真实窗口沿用5秒而非重置30秒")
		first_answer.submit(-1)
		suite.check(not second_answer.settled, "E03e-20c-0：旧窗口回答不结束续接窗口")
		game._step_remaining = 2.0
		second_answer.submit(-1)
	finish.call_deferred()
	suite.check(await game._wait_choice_prompt(second, second_answer, Callable(), true, remaining[0], remaining) == -1 and remaining[0] == 2.0, "E03e-20c-0：取消前保存续接窗口余量")
	await suite.process_frame
	for stage in ["activate", "option", "target"]:
		for mode in ["accept", "invalid", "phase", "end", "general", "duplicate", "old_signal"] + (["decline"] if stage == "activate" else []):
			prepare(stage)
			var actor = game.players[0]
			var act = func():
				var buttons = [] if stage == "target" else game._choice_prompt_stack.back().overlay.find_children("*", "Button", true, false)
				match mode:
					"decline": buttons[1].pressed.emit()
					"invalid":
						if stage == "target": game._meiyong_target_generation += 1
						else: game._choice_prompt_stack.back().overlay.queue_free()
					"phase": game.turn_manager.current_phase = TurnManager.Phase.DRAW
					"end": game._game_over = true
					"general": actor.general_name = "稻草人"
					"duplicate":
						var owner = game._meiyong_execution_owner
						var hands = actor.hand_size()
						suite.check(await game._maybe_meiyong(actor) == GameManager.CHOICE_INVALID and game._meiyong_execution_owner == owner and actor.hand_size() == hands, "E03e-20b：重复赠送不叠窗口或再摸一张")
					"old_signal":
						game._meiyong_pick_result.emit(game.players[2])
						if stage == "target": suite.check(not game._meiyong_target_answer.settled, "E03e-20b：旧共享赠送目标信号不回答实际等待")
				if mode not in ["decline", "invalid"]:
					if stage == "target": game._on_meiyong_target_click(game.players[1])
					else: buttons[0 if stage == "activate" else 1].pressed.emit()
			act.call_deferred()
			var reply = await game._maybe_meiyong(actor)
			var success = mode in ["accept", "duplicate", "old_signal"]
			suite.check(reply == (1 if success else (0 if mode == "decline" else GameManager.CHOICE_INVALID)) and game._meiyong_execution_owner == -1 and game.turn_manager.granted_draw_target_idx == (1 if success else -1) and game.turn_manager.granted_judge_target_idx == -1 and game.turn_manager.granted_play_target_idx == -1, "E03e-20b：仅有效正向赠送写阶段，技术失效不误赠送")
			suite.check(actor.hand_size() == (4 if success or stage != "activate" else 3), "E03e-20b：发动前失效不摸牌，技术失效保留已实际完成的摸牌")
			await suite.process_frame
	for option in [0, 1, 2]:
		prepare("target", option)
		var choose = func(): game._on_meiyong_target_click(game.players[1])
		choose.call_deferred()
		await game._maybe_meiyong(game.players[0])
		suite.check([game.turn_manager.granted_judge_target_idx, game.turn_manager.granted_draw_target_idx, game.turn_manager.granted_play_target_idx][option] == 1 and game.players[0].hand_size() == 4, "E03e-20b：三种正常赠送实际选人各写对应目标并摸一次")
		await suite.process_frame
	prepare("activate")
	var close = func(): game._choice_prompt_stack.back().overlay.queue_free()
	close.call_deferred()
	await game._do_start(0)
	suite.check(game.turn_manager.current_phase == TurnManager.Phase.START and game.players[0].hand_size() == 3 and game._start_phase_owner == -1, "E03e-20b：外层收到技术关闭不推进阶段或补摸牌")
	await suite.process_frame
	prepare("target")
	var done: Array = [false]
	var restart = func():
		var old_answer = game._meiyong_target_answer
		game.reset_game_over_state()
		var finish_new = func():
			var owner = game._meiyong_execution_owner
			old_answer.submit(1)
			suite.check(owner != -1 and game._meiyong_execution_owner == owner and game._is_meiyong_targeting and not game._meiyong_target_answer.settled and game._cancel_target_btn.visible, "E03e-20b：旧赠送答复不清新头像模式/按钮或新锁")
			game._on_meiyong_target_click(game.players[1])
		finish_new.call_deferred()
		await game._maybe_meiyong(game.players[0])
		done[0] = true
	restart.call_deferred()
	await game._maybe_meiyong(game.players[0])
	while not done[0]: await suite.process_frame
	suite.check(game.players[0].hand_size() == 5 and game.turn_manager.granted_draw_target_idx == 1 and game._meiyong_execution_owner == -1 and not game._is_meiyong_targeting, "E03e-20b：重开保留已完成两次摸牌，仅新有效选择赠送一次")
	await suite.process_frame
	reset("稻草人")
	game.turn_manager.granted_judge_target_idx = -1
	game.turn_manager.granted_draw_target_idx = -1
	game.turn_manager.granted_play_target_idx = -1
	game._meiyong_override = Callable()
	game._meiyong_option_override = Callable()
	game._meiyong_target_override = Callable()
	game._rps_override = Callable()
	suite = null
	game = null
