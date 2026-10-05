extends "res://Test/awaken_lifecycle_cases.gd"

func run(host):
	suite = host
	game = host.game
	var actor = setup()
	game._check_player_awaken(actor)
	game.reset_game_over_state()
	await frames()
	suite.check(actor.max_hp == 3 and actor.hand.is_empty() and not actor.awaken_effects_applied and game._choice_prompt_stack.is_empty(), "E03e-22d-3c：旧deferred觉醒不在同阶段重开后扣上限/摸牌/开窗口")
	actor = setup()
	actor.awoken = true
	game._awaken_pick_override = func():
		await suite.process_frame
		game.reset_game_over_state()
		return 2
	await game._do_awaken(actor)
	await frames()
	suite.check(actor.awake_choice == 0 and actor.max_hp == 2 and actor.hand_size() == 2 and game._choice_prompt_stack.is_empty() and game._awaken_in_progress.is_empty(), "E03e-22d-3c：重开旧答复不写免疫/重显旧窗口，已提交扣上限和摸牌保留")
	actor = setup()
	actor.awoken = true
	var completed: Array = [false]
	game._awaken_pick_override = func():
		game.reset_game_over_state()
		game._awaken_pick_override = func():
			await suite.process_frame
			await suite.process_frame
			await suite.process_frame
			return 1
		var next = func():
			await game._do_awaken(actor)
			completed[0] = true
		next.call_deferred()
		await suite.process_frame
		await suite.process_frame
		return 2
	await game._do_awaken(actor)
	suite.check(actor.awake_choice == 0 and game._awaken_in_progress.has(actor) and not completed[0], "E03e-22d-3c：旧觉醒完成不清同人物/同阶段新局租约")
	while not completed[0]: await suite.process_frame
	suite.check(actor.awake_choice == 1 and actor.max_hp == 2 and actor.hand_size() == 2 and game._awaken_in_progress.is_empty(), "E03e-22d-3c：新觉醒正常选择默认杀免疫，不重复扣上限/摸牌")
	game._awaken_pick_override = Callable()
	suite.reset_players()
	game = null
	suite = null
