extends "res://Test/play_skill_selection_generation_cases.gd"

func run(host):
	suite = host
	game = host.game
	var specs = [["史蒂芬·彼特先斯", "装逼", "_zhuangbi_execution_owner"], ["杰基·斯特朗", "校园霸主", "_campus_execution_owner"], ["比尔·盖伊", "Gay", "_gay_execution_owner"], ["麦克斯·欧尼斯特", "没用", "_lanzhonghou_execution_owner"]]
	for active in specs:
		reset(active[0])
		game.players[0].awoken = true
		game.players[2].equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.LIANNU))
		var actor = game.players[0]
		var target = game.players[1]
		var inspect = func():
			var owner = game.get(active[2])
			var selection = game._play_skill_selection_generation
			var overlays = game.get_node("UI").get_child_count()
			var prompts = game._choice_prompt_stack.size()
			# 防御性直接入口探测，不宣称同一武将在规则上能拥有四种技能。
			for spec in specs:
				actor.general_name = spec[0]
				await game._on_detail_skill_clicked(spec[1], actor)
				match spec[1]:
					"装逼":
						game._start_zhuangbi_mode()
						await game._execute_zhuangbi([target])
					"校园霸主":
						game._start_campus_mode()
						await game._execute_campus_dominator(actor, target)
					"Gay":
						await game._execute_gay(actor, target)
					"没用":
						game._start_lanzhonghou_mode()
						await game._run_lanzhonghou(target, game.players[2])
				actor.general_name = active[0]
				suite.check(game.get(active[2]) == owner and game._play_skill_selection_generation == selection and game.get_node("UI").get_child_count() == overlays and game._choice_prompt_stack.size() == prompts, "E03e-17b-4b：四主动详情/模式/执行重入不叠窗口、不换代次或执行锁")
				suite.check(actor.hand_size() == 3 and target.hand_size() == 1 and actor.hp == 1 and target.hp == 1 and not game._gay_used and not game._lanzhonghou_used, "E03e-17b-4b：忙入口不支付、不伤害/回血、不记次数")
			# 响应类窗口仍能合法嵌套，不被主动入口锁禁止。
			var respond = func():
				game._choice_prompt_stack.back().overlay.find_children("*", "Button", true, false)[0].pressed.emit()
			respond.call_deferred()
			suite.check(await game._show_choice_popup("工程响应嵌套", ["回应"]) == 0 and game.get(active[2]) == owner, "E03e-17b-4b：主动执行锁不限制内部响应窗口")
			var window = game.get_node("UI").get_children().filter(func(node): return node is ColorRect and not node.is_queued_for_deletion()).back()
			if active[1] == "没用":
				# 实际交换窗口的技术关闭独立等待属于下一子项18。
				window.find_children("*", "Button", true, false).filter(func(button): return button.text == "取消")[0].pressed.emit()
			else:
				window.queue_free()
		inspect.call_deferred()
		match active[1]:
			"装逼": await game._execute_zhuangbi([target])
			"校园霸主": await game._execute_campus_dominator(actor, target)
			"Gay": await game._execute_gay(actor, target)
			"没用": await game._run_lanzhonghou(target, game.players[2])
		suite.check(game.get(active[2]) == -1 and not game._play_skill_execution_busy() and actor.hand_size() == 3 and target.hand_size() == 1, "E03e-17b-4b：关闭或主动取消释放自己的执行锁，未支付费用")
		await suite.process_frame
	# 成功再选允许通过同一执行锁；再次真正执行仍重新收一次费用。
	reset("史蒂芬·彼特先斯")
	game.players[0].awoken = true
	game.players[1].hp = 5
	game.players[1].hand.assign([null, null])
	game._hand_discard_override = func(snapshot, count, _mandatory): return snapshot.defaults(count)
	game._zhuangbi_again_override = Callable()
	var repeat = func():
		game._choice_prompt_stack.back().overlay.find_children("*", "Button", true, false)[0].pressed.emit()
	repeat.call_deferred()
	await game._execute_zhuangbi([game.players[1]])
	suite.check(game._is_zhuangbi_targeting and game._zhuangbi_execution_owner == -1 and game.players[1].hp == 4 and game.players[0].hand_size() == 2, "E03e-17b-4b：装逼成功可以穿过自己的锁进入下一选目标模式")
	game._zhuangbi_again_override = func(): return false
	await game._execute_zhuangbi([game.players[1]])
	suite.check(game.players[1].hp == 3 and game.players[0].hand_size() == 1 and game.players[1].hand_size() == 0, "E03e-17b-4b：装逼再次独立支付、正常造成伤害一次")
	game._on_cancel_target_pressed()
	await suite.process_frame
	reset("稻草人")
	game._rps_override = Callable()
	game._zhuangbi_again_override = func(): return false
	suite = null
	game = null
