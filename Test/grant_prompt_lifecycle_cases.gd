extends "res://Test/play_skill_selection_generation_cases.gd"

func prepare(stage: String, option: int = 1):
	reset("麦克斯·欧尼斯特")
	game.turn_manager.current_player_idx = 0
	game.turn_manager.current_phase = TurnManager.Phase.START
	game.turn_manager.skip_full_turn = false
	game.turn_manager.skip_judge_phase = false
	game.turn_manager.skip_play_phase = false
	game.turn_manager.supply_shortage_active = false
	game.turn_manager.granted_judge_target_idx = -1
	game.turn_manager.granted_draw_target_idx = -1
	game.turn_manager.granted_judge_completed = false
	game.turn_manager.granted_draw_completed = false
	game.turn_manager.granted_play_target_idx = -1
	game.turn_manager.granted_play_completed = false
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
		for mode in ["accept", "invalid", "phase", "end", "general", "duplicate", "old_signal", "decline", "timeout"]:
			prepare(stage)
			var actor = game.players[0]
			var act = func():
				var buttons = game._choice_prompt_stack.back().overlay.find_children("*", "Button", true, false)
				if stage == "target":
					game._on_meiyong_target_click(game.players[1])
					suite.check(not game._meiyong_target_answer.settled and actor.hand_size() == 3, "E03e-20c-1：已选头像未按阶段仍不提交或摸牌")
				match mode:
					"decline": buttons[1 if stage == "activate" else 3].pressed.emit()
					"timeout": game._countdown_on_timeout.call()
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
				if mode not in ["decline", "timeout", "invalid"]:
					if stage != "activate": game._on_meiyong_target_click(game.players[1])
					buttons[0 if stage == "activate" else 1].pressed.emit()
			act.call_deferred()
			var reply = await game._maybe_meiyong(actor)
			var success = mode in ["accept", "duplicate", "old_signal"]
			suite.check(reply == (1 if success else (0 if mode in ["decline", "timeout"] else GameManager.CHOICE_INVALID)) and game._meiyong_execution_owner == -1 and game.turn_manager.granted_draw_target_idx == (1 if success else -1) and game.turn_manager.granted_judge_target_idx == -1 and game.turn_manager.granted_play_target_idx == -1, "E03e-20c-1：仅有效正向赠送写阶段，取消/超时不发动，失效不误赠送")
			suite.check(actor.hand_size() == (4 if success else 3), "E03e-20c-1：最终阶段确认前的取消或失效均不摸牌")
			await suite.process_frame
	prepare("activate")
	game._meiyong_option_override = Callable()
	game._meiyong_target_override = Callable()
	var combined_checks = func():
		var buttons = game._choice_prompt_stack.back().overlay.find_children("*", "Button", true, false)
		suite.check(buttons.size() == 4 and buttons[0].disabled and buttons[1].disabled and buttons[2].disabled and not buttons[3].disabled and game._step_remaining == 5.0, "E03e-20c-1：四按钮初始仅取消可用，技能第二屏实际剩5秒")
		buttons[1].pressed.emit()
		suite.check(game.players[0].hand_size() == 3 and not game._meiyong_target_answer.settled, "E03e-20c-1：伪造禁用按钮不提交或摸牌")
		game.players[2].judgment_cards.clear()
		game._on_meiyong_target_click(game.players[2])
		suite.check(buttons[0].disabled and not buttons[1].disabled and not buttons[2].disabled and game.players[0].hand_size() == 3 and game._step_remaining == 5.0, "E03e-20c-1：无判定牌目标只开摸/出牌且头像点击不摸牌或重置读条")
		game._on_meiyong_target_click(game.players[1])
		suite.check(not buttons[0].disabled and game.players[0].hand_size() == 3 and game._step_remaining == 5.0, "E03e-20c-1：改选判定区有牌目标开放判定，仍不摸牌或重置")
		buttons[1].pressed.emit()
	var first_confirm = func():
		suite.check(game._choice_prompt_stack.back().overlay.find_children("*", "Button", true, false).size() == 2, "E03e-20c-1：最初确认界面恰好两个按钮")
		game._step_remaining = 5.0
		combined_checks.call_deferred()
		game._choice_prompt_stack.back().overlay.find_children("*", "Button", true, false)[0].pressed.emit()
	first_confirm.call_deferred()
	suite.check(await game._maybe_meiyong(game.players[0]) == 1 and game.players[0].hand_size() == 4 and game.turn_manager.granted_draw_target_idx == 1, "E03e-20c-1：完整确认→选人→阶段只摸一次并提交最终目标")
	await suite.process_frame
	for option in [0, 1, 2]:
		prepare("target", option)
		var old_chooser = game.ai_driver.chooser
		game.ai_driver.chooser = func(_view, _choices): return -1
		var choose = func():
			game._on_meiyong_target_click(game.players[1])
			game._meiyong_combined_state.buttons[option].pressed.emit()
		choose.call_deferred()
		await game._maybe_meiyong(game.players[0])
		game.ai_driver.chooser = old_chooser
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
			game._meiyong_combined_state.buttons[1].pressed.emit()
		finish_new.call_deferred()
		await game._maybe_meiyong(game.players[0])
		done[0] = true
	restart.call_deferred()
	await game._maybe_meiyong(game.players[0])
	while not done[0]: await suite.process_frame
	suite.check(game.players[0].hand_size() == 4 and game.turn_manager.granted_draw_target_idx == 1 and game._meiyong_execution_owner == -1 and not game._is_meiyong_targeting, "E03e-20c-1：重开旧选择不摸牌，仅新有效阶段点击摸一次")
	await suite.process_frame
	await check_immediate_judge_draw()
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

func check_immediate_judge_draw():
	for option in [0, 1]:
		prepare("activate", option)
		game._meiyong_override = func(): return true
		game._meiyong_option_override = func(): return option
		game._meiyong_target_override = func(): return game.players[1]
		var source = game.players[0]
		var target = game.players[1]
		var own_judgment = CardBase.create(CardData.CardSubType.INDULGENCE)
		source.judgment_cards.assign([own_judgment])
		var target_card = target.judgment_cards[0]
		var source_hand = source.hand_size()
		var target_hand = target.hand_size()
		var turn_id = game.turn_manager.turn_id
		var reply = await game._maybe_meiyong(source)
		suite.check(reply == 1 and game.turn_manager.current_phase == TurnManager.Phase.START and game.turn_manager.current_player_idx == 0 and game.turn_manager.turn_id == turn_id and source.hand_size() == source_hand + 1, "E03e-20c-2a：获赠判定/摸牌在源START完成，不新增回合且源只摸1")
		if option == 0:
			suite.check(target.judgment_cards.is_empty() and game.deck._discard.has(target_card) and source.judgment_cards == [own_judgment] and not game.turn_manager.skip_play_phase, "E03e-20c-2a：目标立即判定乐不失效，源判定牌保留")
			game.turn_manager.current_phase = TurnManager.Phase.JUDGE
			await game._do_judge(0)
			suite.check(source.judgment_cards == [own_judgment] and target.judgment_cards.is_empty() and game.turn_manager.granted_judge_target_idx == -1 and not game.turn_manager.granted_judge_completed, "E03e-20c-2a：源判定阶段仅跳过，不重复赠送或结算自己")
		else:
			suite.check(target.hand_size() == target_hand + 2 and game.turn_manager.granted_draw_completed, "E03e-20c-2a：普通目标当场摸2张任意牌")
			game.turn_manager.current_phase = TurnManager.Phase.DRAW
			game._do_draw(0)
			suite.check(source.hand_size() == source_hand + 1 and target.hand_size() == target_hand + 2 and game.turn_manager.granted_draw_target_idx == -1 and not game.turn_manager.granted_draw_completed, "E03e-20c-2a：源摸牌阶段只跳过，双方不重复摸牌")
		await suite.process_frame
	prepare("activate", 1)
	game._meiyong_override = func(): return true
	game._meiyong_option_override = func(): return 1
	game._meiyong_target_override = func(): return game.players[1]
	game.players[1].general_name = "比尔·盖伊"
	game.players[1].shensu_penalty = 1
	game.players[1].shensu_used_this_turn = false
	game.turn_manager.supply_shortage_active = true
	await game._maybe_meiyong(game.players[0])
	suite.check(game.players[1].hand_size() == 3 and game.players[1].shensu_penalty == 0 and game.turn_manager.supply_shortage_active, "E03e-20c-2a：获赠摸牌执行目标英姿及下个摸牌减益，不消耗源兵粮")
	game.turn_manager._begin_turn()
	suite.check(not game.turn_manager.granted_draw_completed and not game.turn_manager.granted_judge_completed, "E03e-20c-2a：下一回合清理已完成赠送标记")
	await suite.process_frame
	prepare("activate", 0)
	game._meiyong_override = func(): return true
	game._meiyong_option_override = func(): return 0
	game._meiyong_target_override = func(): return game.players[1]
	var old_nullification = game._nullify_override
	game._nullify_override = Callable()
	var lightning = CardBase.create(CardData.CardSubType.LIGHTNING)
	game.players[1].judgment_cards.assign([lightning])
	var close_judge = func():
		game._choice_prompt_stack.back().overlay.queue_free()
	close_judge.call_deferred()
	var reply = await game._maybe_meiyong(game.players[0])
	suite.check(reply == GameManager.CHOICE_INVALID and game.players[0].hand_size() == 4 and game.players[1].judgment_cards == [lightning] and not game.deck._discard.has(lightning) and game.players[1].hp == 1, "E03e-20c-2a：已提交赠送的真实无懈窗口关闭保留源摸牌，不误判定闪电或丢原牌")
	suite.check(game.turn_manager.current_phase == TurnManager.Phase.START and game._meiyong_execution_owner == -1 and game.turn_manager.granted_judge_completed, "E03e-20c-2a：判定技术失效停旧执行，不在源阶段重新赠送")
	game._nullify_override = old_nullification
	game.turn_manager._begin_turn()
	await suite.process_frame
