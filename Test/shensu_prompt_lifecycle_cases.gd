extends "res://Test/play_skill_selection_generation_cases.gd"

func prepare(stage: String):
	reset("比尔·盖伊")
	game.turn_manager.current_player_idx = 0
	game.turn_manager.current_phase = TurnManager.Phase.START
	game.turn_manager.skip_full_turn = false
	game.turn_manager.skip_judge_phase = false
	game.turn_manager.skip_play_discard_phase = false
	game.players[0].shensu_penalty = 0
	game.players[0].shensu_used_this_turn = false
	game.players[0].judgment_cards.assign([CardBase.create(CardData.CardSubType.INDULGENCE)])
	game.players[1].hp = 5
	game._shensu_override = Callable() if stage == "activate" else func(): return true
	game._shensu_option_override = (func(): return 2) if stage == "activate" else ((func(): return 1) if stage == "target" else Callable())
	game._shensu_target_override = Callable()

func run(host):
	suite = host
	game = host.game
	for stage in ["activate", "option", "target"]:
		for mode in ["accept", "cancel", "invalid", "phase", "end", "general", "duplicate", "old_signal"] + ([] if stage == "activate" else ["judgment"]):
			prepare(stage)
			var actor = game.players[0]
			var act = func():
				var buttons = [] if stage == "target" else game._choice_prompt_stack.back().overlay.find_children("*", "Button", true, false)
				var choose = func():
					if stage == "target": game._on_shensu_target_click(game.players[1])
					else: buttons[0 if stage == "activate" or mode == "judgment" else 1].pressed.emit()
				match mode:
					"cancel":
						if stage == "target": game._on_cancel_target_pressed()
						else: buttons[1 if stage == "activate" else 2].pressed.emit()
					"invalid":
						if stage == "target": game._shensu_target_generation += 1
						else: game._choice_prompt_stack.back().overlay.queue_free()
					"phase": game.turn_manager.current_phase = TurnManager.Phase.JUDGE
					"end": game._game_over = true
					"general": actor.general_name = "稻草人"
					"judgment": actor.judgment_cards.clear()
					"duplicate":
						var owner = game._shensu_execution_owner
						var prompts = game._choice_prompt_stack.size()
						suite.check(await game._maybe_shensu(actor) == GameManager.CHOICE_INVALID and game._shensu_execution_owner == owner and game._choice_prompt_stack.size() == prompts, "E03e-20a：重复神速不叠窗口或阶段效果")
					"old_signal":
						game._shensu_pick_result.emit(game.players[2])
						if stage == "target": suite.check(not game._shensu_target_answer.settled, "E03e-20a：旧目标信号不能答新独立等待")
				if mode not in ["cancel", "invalid"]: choose.call()
			act.call_deferred()
			var reply = await game._maybe_shensu(actor)
			var success = mode in ["accept", "duplicate", "old_signal"]
			suite.check(reply == (1 if success else (0 if mode == "cancel" else GameManager.CHOICE_INVALID)) and game._shensu_execution_owner == -1, "E03e-20a：实际确认/选项/头像区分成功、主动放弃和技术失效")
			suite.check(game.turn_manager.skip_judge_phase == (success and stage == "target") and game.turn_manager.skip_play_discard_phase == (success and stage != "target") and actor.shensu_penalty == (1 if success and stage != "target" else 0) and actor.hand_size() == 3 and game.players[1].hp == (4 if success and stage == "target" else 5), "E03e-20a：失效不跳阶段/记减益/出旧杀，成功不耗手牌且只生效一次")
			await suite.process_frame
	# 原选项映射不会因等待中判定区变化而把选项1误解释为2。
	prepare("option")
	game.players[0].judgment_cards.clear()
	var add_judgment = func():
		game.players[0].judgment_cards.append(CardBase.create(CardData.CardSubType.LIGHTNING))
		game._choice_prompt_stack.back().overlay.find_children("*", "Button", true, false)[0].pressed.emit()
	add_judgment.call_deferred()
	await game._maybe_shensu(game.players[0])
	suite.check(game.turn_manager.skip_play_discard_phase and game.players[0].shensu_penalty == 1 and not game.turn_manager.skip_judge_phase, "E03e-20a：原无判定牌窗口后来新增判定仍选择原选项2")
	await suite.process_frame
	# 实际START外层在技术关闭后不自动advance到判定/摸牌。
	prepare("activate")
	var close = func(): game._choice_prompt_stack.back().overlay.queue_free()
	close.call_deferred()
	await game._do_start(0)
	suite.check(game.turn_manager.current_phase == TurnManager.Phase.START and game._start_phase_owner == -1 and game.players[0].hand_size() == 3, "E03e-20a：外层回合开始收到技术失效，不推进阶段或补摸牌")
	await suite.process_frame
	prepare("target")
	var done: Array = [false]
	var restart = func():
		var old_answer = game._shensu_target_answer
		game.reset_game_over_state()
		var finish_new = func():
			var owner = game._shensu_execution_owner
			old_answer.submit(1)
			suite.check(owner != -1 and game._shensu_execution_owner == owner and game._is_shensu_targeting and not game._shensu_target_answer.settled and game._cancel_target_btn.visible, "E03e-20a：旧头像答复不清新选择/按钮或执行锁")
			game._on_shensu_target_click(game.players[1])
		finish_new.call_deferred()
		await game._maybe_shensu(game.players[0])
		done[0] = true
	restart.call_deferred()
	await game._maybe_shensu(game.players[0])
	while not done[0]: await suite.process_frame
	suite.check(game.players[1].hp == 4 and game.turn_manager.skip_judge_phase and game._shensu_execution_owner == -1 and not game._is_shensu_targeting, "E03e-20a：同人物同START重开仅新神速一次虚拟杀")
	await suite.process_frame
	reset("稻草人")
	game._shensu_override = Callable()
	game._shensu_option_override = Callable()
	game._shensu_target_override = Callable()
	game._rps_override = Callable()
	suite = null
	game = null
