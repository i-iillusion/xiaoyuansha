extends RefCounted

var suite

func click(menu, text: String, partial: bool = false) -> Button:
	for button in menu.get_node("Center/Box/Page").get_children():
		if button is Button and not button.is_queued_for_deletion() and (text in button.text if partial else button.text == text):
			button.pressed.emit()
			return button
	suite.check(false, "G03a missing actual menu button: " + text)
	return null

func adopt(node):
	if node is GameManager and node.name == "Game" and node.get_parent() == suite.root:
		node.set_script(load("res://Test/scene_replay_observer.gd"))

func run(host):
	suite = host
	var previous = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general,
		GameManager.random_general, GameManager.random_identity, MainMenu.random_mode]
	var old_scene = suite.current_scene
	suite.node_added.connect(adopt)
	var error = suite.change_scene_to_file("res://Scenes/MainMenu.tscn")
	suite.check(error == OK, "G03a real main scene loads")
	await suite.process_frame
	await suite.process_frame
	for count in [2, 3, 5]:
		var retained: Array = []
		for repeat in 2:
			var menu = suite.current_scene
			suite.check(menu is MainMenu and menu.get_node("Center/Box/Title").text == "校园杀", "G03a real initial/returned menu renders title")
			MainMenu.random_mode = false
			click(menu, "开始游戏")
			click(menu, "测试模式")
			click(menu, "5人标准" if count == 5 else "%d人乱斗" % count)
			var choose = click(menu, "稻草人", true)
			# Same-frame duplicate click must not navigate twice or change selection.
			if choose != null: choose.pressed.emit()
			await suite.process_frame
			await suite.process_frame
			var game = suite.current_scene
			suite.check(game is GameManager and not game.opening.is_empty() and game.players.size() == count, "G03a actual scene change auto-starts chosen player count")
			if not game is GameManager: return
			suite.check(game.game_mode == (GameManager.MODE_CLASSIC_IDENTITY if count == 5 else GameManager.MODE_FREE_FOR_ALL) and game.players.all(func(p): return p.general_name == "稻草人"), "G03a actual menu selection preserved; no duplicate start")
			suite.check(game.opening.hands.all(func(n): return n == 4) and game.opening.hp[0] == (6 if count == 5 else 5) and game.opening.hp.slice(1).all(func(hp): return hp == 5) and game.opening.turn == 1, "G03a new game begins with original initial hands/HP/turn")
			suite.check(game.opening.pool == 0 and game.opening.discard == 0 and game.opening.counts.is_empty() and game.opening.windows == 0 and game.opening.pending == 0 and game.opening.dying == 0 and not game.opening.paused and not game.opening.yudaxi and game.opening.standalone.is_empty(), "G03a fresh equipment/deck/counts/windows/dying/scheduler/standalone context")
			for reference in retained:
				suite.check(reference != game.equipment_pool and reference != game.deck and reference != game.rule_scheduler and reference != game.yudaxi, "G03a new match owns fresh RefCounted resources")
			for frame in 300:
				if game._game_over: break
				await suite.process_frame
			suite.check(game._game_over and game.winners.size() == 1 and game.completed_turns > 0, "G03a real complete turn(s) to actual single terminal, %d/%d" % [count, repeat])
			suite.check(game.replay_violations.is_empty() and game.equipment_pool.is_claimed(CardData.CardSubType.LIANNU), "G03a legal card ownership and real equipment claim in every match")
			var outcome = IdentityVictory.evaluate(game.players) if count == 5 else FreeForAllVictory.evaluate(game.players)
			suite.check(not outcome.is_empty() and game.winners == [outcome.winner], "G03a real winner matches independent mode evaluator")
			await suite.process_frame
			await suite.process_frame
			suite.check(game._choice_prompt_stack.is_empty() and game._pending_card_actions.is_empty() and game._dying_contexts.is_empty() and game._ai_running_revisions.is_empty() and not game._countdown_active and not game.rule_scheduler.is_paused() and not game.yudaxi.is_active(), "G03a terminal drains windows, cards, dying, AI, timers and scheduler")
			var final_state = game.replay_state()
			var actions = game.replay_actions.size()
			await suite.process_frame
			suite.check(game.replay_state() == final_state and game.replay_actions.size() == actions and game.winners.size() == 1, "G03a late frame cannot act or end twice")
			retained = [game.equipment_pool, game.deck, game.rule_scheduler, game.yudaxi]
			var players = game.players.map(func(p): return weakref(p))
			var old_game = weakref(game)
			var return_buttons = game._game_over_overlay.find_children("*", "Button", true, false)
			suite.check(return_buttons.size() == 1 and return_buttons[0].text == "返回主菜单", "G03a real terminal overlay offers return")
			return_buttons[0].pressed.emit()
			return_buttons[0].pressed.emit()
			await suite.process_frame
			await suite.process_frame
			suite.check(suite.current_scene is MainMenu and old_game.get_ref() == null and players.all(func(ref): return ref.get_ref() == null), "G03a real return frees old game/players; duplicate click harmless")
			game = null
			await suite.process_frame
			suite.check(suite.current_scene is MainMenu and suite.current_scene.get_node("Center/Box/Page").get_child_count() == 2, "G03a late callback cannot leave new menu or duplicate its controls")
	suite.node_added.disconnect(adopt)
	var menu = suite.current_scene
	suite.current_scene = old_scene
	menu.queue_free()
	await suite.process_frame
	GameManager.selected_players = previous[0]
	GameManager.selected_mode = previous[1]
	GameManager.selected_general = previous[2]
	GameManager.random_general = previous[3]
	GameManager.random_identity = previous[4]
	MainMenu.random_mode = previous[5]
