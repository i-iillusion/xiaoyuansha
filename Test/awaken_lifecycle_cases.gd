extends RefCounted

var game: GameManager
var suite

func setup() -> Player:
	suite.reset_players()
	game._awaken_pick_override = Callable()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	var p: Player = game.players[0]
	p.general_name = "史蒂芬·彼特先斯"
	p.max_hp = 3
	p.hp = 3
	p.capture_game_start_state()
	return p

func frames():
	for i in range(3):
		await game.get_tree().process_frame

func run(host):
	suite = host
	game = host.game
	var old_pick = game._awaken_pick_override
	var old_phase = game.turn_manager.current_phase
	for invalidation in ["none", "close", "phase"]:
		var p = setup()
		game._check_player_awaken(p) # 排队的旧deferred与直接调用重叠。
		game._do_awaken(p)
		await game._do_awaken(p)
		await frames()
		suite.check(p.max_hp == 2 and p.hand_size() == 2 and p.awaken_effects_applied
			and game._choice_prompt_stack.size() == 1,
			"E03c：重复直接/延迟觉醒只扣一次上限、摸两张、开一个窗口")
		var previous = game._choice_prompt_stack[0]
		if invalidation == "close":
			previous.overlay.queue_free()
		elif invalidation == "phase":
			game.turn_manager.current_phase = TurnManager.Phase.END
			game.turn_manager.current_phase = TurnManager.Phase.PLAY
			previous.answer.submit(1)
		if invalidation != "none":
			await frames()
			suite.check(p.awake_choice == 0 and p.max_hp == 2 and p.hand_size() == 2
				and game._choice_prompt_stack.size() == 1
				and game._choice_prompt_stack[0].answer != previous.answer,
				"E03c：失效后重新显示必选项，不重做上限与摸牌：" + invalidation)
			previous.answer.submit(0)
			game._check_player_awaken(p)
			await frames()
		game._choice_prompt_stack[0].answer.submit(2)
		await frames()
		suite.check(p.awake_choice == 3 and p.max_hp == 2 and p.hand_size() == 2
			and game._choice_prompt_stack.is_empty() and not game._awaken_in_progress.has(p),
			"E03c：新窗口完成真实三选一，旧答复不能污染且清等待状态")
		await game._do_awaken(p)
		suite.check(p.max_hp == 2 and p.hand_size() == 2, "E03c：已选完后重复觉醒无额外效果")
	# 实际贤者复原期间旧窗口退出；新一轮觉醒有不同代次。
	var p = setup()
	game._check_player_awaken(p)
	await frames()
	var stale_answer = game._choice_prompt_stack[0].answer
	var old_revision = p.awakening_revision
	p.hp = 0
	game._do_sage_save(p)
	await frames()
	suite.check(not p.awoken and not p.awaken_effects_applied and p.awake_choice == 0
		and p.max_hp == 3 and p.hand_size() == 4 and p.awakening_revision > old_revision
		and game._choice_prompt_stack.is_empty(), "E03c：贤者复原清觉醒效果标记并自动释放旧必选窗口")
	for i in range(4):
		p.remove_from_hand(null)
	await frames()
	stale_answer.submit(0)
	suite.check(p.awoken and p.awake_choice == 0 and p.max_hp == 2 and p.hand_size() == 2
		and game._choice_prompt_stack.size() == 1, "E03c：复原后再次失去最后手牌只新觉醒一次，旧答复不写入")
	game._choice_prompt_stack[0].answer.submit(1)
	await frames()
	suite.check(p.awake_choice == 2, "E03c：复原后的新觉醒可选不同永久效果")
	p = setup()
	game._check_player_awaken(p)
	await frames()
	game._finish_game("平局", "E03c回归")
	await frames()
	suite.check(p.awake_choice == 0 and game._choice_prompt_stack.is_empty()
		and not game._awaken_in_progress.has(p) and not game._countdown_active,
		"E03c：终局退出必选，不复活窗口或倒计时")
	game._awaken_pick_override = old_pick
	suite.reset_players()
	game.turn_manager.current_phase = old_phase
