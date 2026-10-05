extends "res://Test/grant_prompt_lifecycle_cases.gd"

func setup_human():
	prepare("activate", 2)
	game.players[0].general_name = "稻草人"
	game.players[1].general_name = "麦克斯·欧尼斯特"
	game.players[1].hand.assign([null])
	game.turn_manager.current_player_idx = 1
	game._meiyong_override = func(): return true
	game._meiyong_option_override = func(): return 2
	game._meiyong_target_override = func(): return game.players[0]

func run(host):
	suite = host
	game = host.game
	var connected = game.turn_manager.phase_changed.is_connected(game._on_phase_changed)
	if connected: game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
	for concrete in [false, true]:
		setup_human()
		var source = game.players[1]
		var target = game.players[0]
		target.hand.assign([CardBase.create(CardData.CardSubType.WINE) if concrete else null])
		var turn = game.turn_manager.turn_id
		var phase = game.turn_manager.phase_id
		var act = func():
			suite.check(game.turn_manager.current_phase == TurnManager.Phase.PLAY and game.turn_manager.current_player_idx == 1 and game.turn_manager.get_play_actor_idx() == 0 and game.turn_manager.phase_id > phase and game.turn_manager.turn_id == turn, "E03e-20c-2b：独立出牌保留源回合，新阶段ID和实际操作者")
			suite.check(game._play_btn.visible and game._end_play_btn.visible and game._countdown_active and source.hand_size() == 2, "E03e-20c-2b：玩家0获得真实出牌按钮/读条，源已摸1")
			await game.play_card(CardData.CardSubType.WINE)
			suite.check(target.hand_size() == 0 and game.turn_manager._get_turn_count("wine", 0) == 1 and game.turn_manager._get_turn_count("wine", 1) == 0 and source.hand_size() == 2, "E03e-20c-2b：任意/具体酒支付及回合次数归获赠者，源不被扣牌")
			game._on_end_play_pressed()
		act.call_deferred()
		suite.check(await game._maybe_meiyong(source) == 1 and game.turn_manager.current_phase == TurnManager.Phase.START and game.turn_manager.current_player_idx == 1 and game.turn_manager.play_actor_idx == -1 and game.turn_manager.turn_id == turn and not game._countdown_active and game.turn_manager.granted_play_completed, "E03e-20c-2b：结束按钮恢复源START，不送弃牌/额外回合且停止目标读条")
		game.turn_manager.current_phase = TurnManager.Phase.PLAY
		await game._do_play(1)
		suite.check(game.turn_manager.current_phase == TurnManager.Phase.DISCARD and not game.turn_manager.granted_play_completed and game.turn_manager.granted_play_target_idx == -1 and game.turn_manager.turn_id == turn, "E03e-20c-2b：源自己的出牌阶段仅跳过，不重复赠送或重置次数")
		await suite.process_frame
	for mode in ["timeout", "phase", "end", "reset", "duplicate"]:
		setup_human()
		var source = game.players[1]
		var act = func():
			match mode:
				"timeout": game._countdown_on_timeout.call()
				"phase": game.turn_manager.current_phase = TurnManager.Phase.DRAW
				"end": game._game_over = true
				"reset": game.reset_game_over_state()
				"duplicate":
					var frame = game.turn_manager._standalone_play_frame
					suite.check(await game._maybe_meiyong(source) == GameManager.CHOICE_INVALID and is_same(frame, game.turn_manager._standalone_play_frame) and source.hand_size() == 2, "E03e-20c-2b：重复发动不覆盖获赠出牌或额外摸牌")
					game.end_play_phase()
		act.call_deferred()
		var reply = await game._maybe_meiyong(source)
		var success = mode in ["timeout", "duplicate"]
		suite.check(reply == (1 if success else GameManager.CHOICE_INVALID) and game.turn_manager._standalone_play_frame.is_empty() and source.hand_size() == 2 and game._meiyong_execution_owner == -1, "E03e-20c-2b：正常结束与技术失效分开，保留已提交摸牌且释放自身帧")
		if not success: suite.check(game.turn_manager.current_phase != TurnManager.Phase.START, "E03e-20c-2b：技术失效不擅自恢复并推进源START")
		await suite.process_frame
	setup_human()
	var restarted: Array = [false]
	var restart = func():
		var old_frame = game.turn_manager._standalone_play_frame
		var old_timeout = game._countdown_on_timeout
		game.reset_game_over_state()
		setup_human()
		var finish_new = func():
			var new_frame = game.turn_manager._standalone_play_frame
			old_timeout.call()
			game.turn_manager.standalone_play_finished.emit(old_frame)
			suite.check(is_same(new_frame, game.turn_manager._standalone_play_frame) and not new_frame.completed and game.turn_manager.current_phase == TurnManager.Phase.PLAY and game._meiyong_execution_owner != -1, "E03e-20c-2b：旧超时/完成信号不结束重开后的新独立出牌")
			game.end_play_phase()
		finish_new.call_deferred()
		suite.check(await game._maybe_meiyong(game.players[1]) == 1, "E03e-20c-2b：重开后的新赠送可正常完成")
		restarted[0] = true
	restart.call_deferred()
	suite.check(await game._maybe_meiyong(game.players[1]) == GameManager.CHOICE_INVALID, "E03e-20c-2b：旧赠送完成不得恢复新局START或占新锁")
	while not restarted[0]: await suite.process_frame
	await suite.process_frame
	setup_human()
	var source_judge = CardBase.create(CardData.CardSubType.INDULGENCE)
	game.players[1].judgment_cards.assign([source_judge])
	var complete_outer = func():
		suite.check(game.players[1].judgment_cards == [source_judge] and game.turn_manager.current_phase == TurnManager.Phase.PLAY and game.turn_manager.get_play_actor_idx() == 0 and game._start_phase_owner != -1, "E03e-20c-2b：外层START在目标出牌期间挂起，源尚未判定")
		game.end_play_phase()
	complete_outer.call_deferred()
	await game._do_start(1)
	suite.check(game.turn_manager.current_phase == TurnManager.Phase.JUDGE and game.players[1].judgment_cards == [source_judge] and game._start_phase_owner == -1 and game._meiyong_execution_owner == -1, "E03e-20c-2b：外层正常恢复后只推进一次到源判定阶段")
	await suite.process_frame
	prepare("activate", 2)
	game._meiyong_override = func(): return true
	game._meiyong_option_override = func(): return 2
	game._meiyong_target_override = func(): return game.players[1]
	game.players[1].hp = 5
	game.players[1].hand.assign([CardBase.create(CardData.CardSubType.PEACH)])
	var chooser = game.ai_driver.chooser
	game.ai_driver.chooser = Callable()
	var turn = game.turn_manager.turn_id
	suite.check(await game._maybe_meiyong(game.players[0]) == 1 and game.players[1].hp == 6 and game.players[1].hand_size() == 0 and game.turn_manager.current_phase == TurnManager.Phase.START and game.turn_manager.turn_id == turn, "E03e-20c-2b：真实AI获赠阶段用具体桃并正常结束后源才继续")
	game.ai_driver.chooser = chooser
	reset("稻草人")
	game.turn_manager._begin_turn()
	game._meiyong_override = Callable()
	game._meiyong_option_override = Callable()
	game._meiyong_target_override = Callable()
	if connected: game.turn_manager.phase_changed.connect(game._on_phase_changed)
	suite = null
	game = null
