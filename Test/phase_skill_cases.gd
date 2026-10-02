extends RefCounted

func run(suite):
	var game: GameManager = suite.game
	var tm = game.turn_manager
	var old_phase = tm.current_phase
	var old_gay = game._gay_x_override
	var old_zone = game._lanzhonghou_zone_override
	tm.phase_changed.disconnect(game._on_phase_changed)
	suite.reset_players()
	tm._change_phase(TurnManager.Phase.PLAY)
	game._gay_used = true
	game._lanzhonghou_used = true
	game._zhuangbi_blocked_this_phase = true
	tm.start_waiting("test", 1)
	tm.end_waiting()
	game._reset_turn_flags()
	suite.check(game._gay_used and game._lanzhonghou_used and game._zhuangbi_blocked_this_phase,
		"E02b：响应返回和装备回合暂态刷新不抹阶段技能历史")
	tm.play_actor_idx = 1
	suite.check(not game._gay_used and not game._lanzhonghou_used and not game._zhuangbi_blocked_this_phase,
		"E02b：不同操作者不共享阶段技能次数")
	tm.play_actor_idx = 0
	suite.check(game._gay_used and game._lanzhonghou_used and game._zhuangbi_blocked_this_phase,
		"E02b：恢复操作者仍保留原阶段历史")
	tm._change_phase(TurnManager.Phase.PLAY)
	suite.check(not game._gay_used and not game._lanzhonghou_used and not game._zhuangbi_blocked_this_phase,
		"E02b：真正新阶段刷新三项阶段技能")
	suite.reset_players()
	var actor: Player = game.players[0]
	var target: Player = game.players[2]
	actor.general_name = "比尔·盖伊"
	actor.hp = 5
	target.hp = 5
	actor.hand.assign([null, null, null])
	game._gay_x_override = func(): return 1
	await game._execute_gay(actor, target)
	await game._execute_gay(actor, target)
	suite.check(actor.hand_size() == 2 and actor.hp == 6 and target.hp == 6,
		"E02b：真实Gay同阶段第二次不支付或回复")
	# 进入麦克斯的新回合，在授予阶段入口继续使用0号比尔的技能。
	tm.current_player_idx = 0
	tm.next_turn()
	game.players[1].general_name = "麦克斯·欧尼斯特"
	tm.granted_play_target_idx = 0
	tm._change_phase(TurnManager.Phase.PLAY)
	await game._do_play(1)
	await game._execute_gay(actor, target)
	suite.check(tm.current_player_idx == 1 and tm.get_play_actor_idx() == 0
		and actor.hand_size() == 1 and actor.hp == 7 and target.hp == 7,
		"E02b：实际获赠出牌阶段按新阶段允许Gay再次支付回复")
	tm.start_waiting("test", 2)
	tm.end_waiting()
	await game._do_play(1)
	suite.check(tm.get_play_actor_idx() == 0 and game._play_btn.visible and game._end_play_btn.visible
		and game._gay_used and tm.current_phase == TurnManager.Phase.PLAY,
		"E02b：获赠阶段响应返回仍由获赠者操作且保留技能次数")
	suite.reset_players()
	tm._change_phase(TurnManager.Phase.PLAY)
	actor.general_name = "麦克斯·欧尼斯特"
	actor.hand.assign([null, null])
	var other: Player = game.players[3]
	var sword = CardBase.create(CardData.CardSubType.LIANNU)
	target.equip_card_to_slot("weapon", sword)
	var choices: Array = ["weapon", "done"]
	game._lanzhonghou_zone_override = func(): return choices.pop_front()
	await game._run_lanzhonghou(target, other)
	await game._run_lanzhonghou(target, other)
	suite.check(actor.hand_size() == 1 and other.get_equipment_card("weapon") == sword,
		"E02b：真实没用同阶段第二次不选区、不收费、不交换")
	tm._change_phase(TurnManager.Phase.PLAY)
	choices.assign(["weapon", "done"])
	await game._run_lanzhonghou(target, other)
	suite.check(actor.hand_size() == 0 and target.get_equipment_card("weapon") == sword,
		"E02b：真实新阶段允许再次支付并交换原装备")
	for skill in ["gay", "exchange"]:
		suite.reset_players()
		tm._change_phase(TurnManager.Phase.PLAY)
		actor.general_name = "比尔·盖伊" if skill == "gay" else "麦克斯·欧尼斯特"
		actor.hand.append(null)
		target.hp = 5
		target.equip_card_to_slot("weapon", sword)
		var change_phase = func():
			tm._change_phase(TurnManager.Phase.PLAY)
			return 1 if skill == "gay" else "weapon"
		if skill == "gay":
			game._gay_x_override = change_phase
			await game._execute_gay(actor, target)
		else:
			game._lanzhonghou_zone_override = change_phase
			await game._run_lanzhonghou(target, other)
		suite.check(actor.hand_size() == 1 and target.hp == 5 and not game._gay_used
			and not game._lanzhonghou_used and target.get_equipment_card("weapon") == sword,
			"E02b：选项期间阶段已变不扣旧费用、不占新阶段次数：" + skill)
	game._gay_x_override = old_gay
	game._lanzhonghou_zone_override = old_zone
	suite.reset_players()
	tm.current_phase = old_phase
	tm.phase_changed.connect(game._on_phase_changed)
