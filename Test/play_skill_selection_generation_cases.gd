extends RefCounted

var suite
var game: GameManager

func reset(general: String):
	suite.reset_players()
	game.deck._discard.clear()
	game._gay_used = false
	game._lanzhonghou_used = false
	game._zhuangbi_blocked_this_phase = false
	game._gay_x_override = Callable()
	game._lanzhonghou_zone_override = Callable()
	game._hand_discard_override = Callable()
	game._rps_override = func(p): return GameManager.RPS_ROCK if p.seat_index == 0 else GameManager.RPS_SCISSORS
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game.turn_manager.play_actor_idx = 0
	game._begin_play_skill_selection()
	game.players[0].general_name = general
	game.players[0].gender = "male"
	game.players[1].gender = "male"
	game.players[0].hp = 1
	game.players[1].hp = 1
	game.players[0].hand.assign([null, null, null])
	game.players[1].hand.assign([null])

func run(host):
	suite = host
	game = host.game
	var specs = [["史蒂芬·彼特先斯", "装逼", "_is_zhuangbi_targeting"], ["杰基·斯特朗", "校园霸主", "_is_campus_targeting"], ["比尔·盖伊", "Gay", "_is_gay_targeting"], ["麦克斯·欧尼斯特", "没用", "_is_lanzhonghou_targeting"]]
	reset("史蒂芬·彼特先斯")
	for spec in specs:
		game.players[0].general_name = spec[0]
		var previous = game._play_skill_selection_generation
		await game._on_detail_skill_clicked(spec[1], game.players[0])
		suite.check(game._play_skill_selection_generation > previous and specs.filter(func(other): return game.get(other[2])).size() == 1 and game.get(spec[2]), "E03e-17b-4a：新主动模式独立代次，清理其他旧模式")
		game._on_cancel_target_pressed()
		suite.check(not game.get(spec[2]) and game._play_skill_selection_generation > previous + 1, "E03e-17b-4a：取消使旧主动选择代次失效")
	for spec in specs.slice(1):
		reset(spec[0])
		var actor = game.players[0]
		var target = game.players[1]
		if spec[1] == "没用": game.players[2].equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.LIANNU))
		await game._on_detail_skill_clicked(spec[1], actor)
		if spec[1] == "没用": await game._on_lanzhonghou_target_click(target)
		var restart = func():
			var overlay = game.get_node("UI").get_children().back() if spec[1] == "没用" else game._choice_prompt_stack.back().overlay
			game.reset_game_over_state()
			await game._on_detail_skill_clicked(spec[1], actor)
			if spec[1] == "没用": await game._on_lanzhonghou_target_click(game.players[3])
			suite.check(game.get(spec[2]) and not game._play_btn.visible and not game._end_play_btn.visible, "E03e-17b-4a：重开后新模式正常隐藏出牌按钮")
			if spec[1] == "校园霸主":
				overlay.find_children("*", "CheckButton", true, false)[0].button_pressed = true
				overlay.confirm.pressed.emit()
			else:
				var buttons = overlay.find_children("*", "Button", true, false)
				if spec[1] == "没用": buttons.filter(func(button): return button.text == "取消")[0].pressed.emit()
				else: buttons[0].pressed.emit()
		restart.call_deferred()
		match spec[1]:
			"Gay": await game._on_gay_target_click(target)
			"校园霸主": await game._on_campus_target_click(target)
			"没用": await game._on_lanzhonghou_target_click(game.players[2])
		suite.check(game.get(spec[2]) and not game._play_btn.visible and not game._end_play_btn.visible and game._cancel_target_btn.visible, "E03e-17b-4a：旧执行完成不能恢复新主动模式按钮")
		suite.check(actor.hand_size() == 3 and target.hand_size() == 1 and actor.hp == 1 and target.hp == 1, "E03e-17b-4a：旧代次选择不支付、不回血或伤害")
		if spec[1] == "没用": suite.check(game._lanzhonghou_selected == [game.players[3]], "E03e-17b-4a：旧没用完成不清新目标列表")
		await suite.process_frame
	reset("麦克斯·欧尼斯特")
	var a = game.players[1]
	var b = game.players[2]
	var weapon = CardBase.create(CardData.CardSubType.LIANNU)
	a.equip_card_to_slot("weapon", weapon)
	var old_answer = ChoicePromptAnswer.new()
	var new_answer = ChoicePromptAnswer.new()
	var calls: Array = [0]
	var done: Array = [false]
	game._lanzhonghou_zone_override = func():
		calls[0] += 1
		if calls[0] == 2: return "weapon"
		await (old_answer.answered if calls[0] == 1 else new_answer.answered)
		return "done"
	game._hand_discard_override = func(_snapshot, _count, _mandatory): return [0]
	var start_new = func():
		game.reset_game_over_state()
		var finish = func():
			var new_owner = game._lanzhonghou_execution_owner
			old_answer.submit(0)
			await suite.process_frame
			suite.check(new_owner != -1 and game._lanzhonghou_execution_owner == new_owner, "E03e-17b-4b：重开后旧没用完成不清除新执行锁")
			suite.check(game._lanzhonghou_pending.size() == 1 and a.get_equipment_card("weapon") == weapon and not game._lanzhonghou_used, "E03e-17b-4a：旧没用只清旧暂存，新待交换原牌与费用未被破坏")
			new_answer.submit(0)
		finish.call_deferred()
		await game._run_lanzhonghou(a, b)
		done[0] = true
	start_new.call_deferred()
	await game._run_lanzhonghou(a, b)
	while not done[0]: await suite.process_frame
	suite.check(game.players[0].hand_size() == 2 and b.get_equipment_card("weapon") == weapon and game._lanzhonghou_used and game._lanzhonghou_pending.is_empty(), "E03e-17b-4a：只有新没用真实支付/移动一次，旧暂存清理隔离")
	await suite.process_frame
	reset("稻草人")
	game._rps_override = Callable()
	game._lanzhonghou_zone_override = Callable()
	suite = null
	game = null
