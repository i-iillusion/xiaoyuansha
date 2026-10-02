extends RefCounted

func run(suite):
	var game: GameManager = suite.game
	var tm = game.turn_manager
	var old_phase = tm.current_phase
	var specs = [
		["史蒂芬·彼特先斯", "装逼", "_is_zhuangbi_targeting", "_on_zhuangbi_target_click"],
		["杰基·斯特朗", "校园霸主", "_is_campus_targeting", "_on_campus_target_click"],
		["比尔·盖伊", "Gay", "_is_gay_targeting", "_on_gay_target_click"],
		["麦克斯·欧尼斯特", "没用", "_is_lanzhonghou_targeting", "_on_lanzhonghou_target_click"]]
	for spec in specs:
		for concrete in [false, true]:
			suite.reset_players()
			tm.current_phase = TurnManager.Phase.PLAY
			var p: Player = game.players[0]
			var target: Player = game.players[2]
			p.general_name = spec[0]
			p.hp = 5
			target.hp = 5
			target.gender = p.gender
			p.hand.append(CardBase.create(CardData.CardSubType.PEACH) if concrete else null)
			target.hand.append(null)
			game.set(spec[2], false)
			tm.play_actor_idx = 1
			await game._on_detail_skill_clicked(spec[1], p)
			suite.check(not game.get(spec[2]) and p.hand_size() == 1,
				"E03a：其他角色出牌时本人技能按钮不能开始选择：" + spec[1])
			# 直接生产执行入口也不能绕过操作者限制，不触发选择/支付。
			match spec[1]:
				"装逼": await game._execute_zhuangbi([target])
				"校园霸主": await game._execute_campus_dominator(p, target)
				"Gay": await game._execute_gay(p, target)
				"没用": await game._run_lanzhonghou(p, target)
			suite.check(p.hand_size() == 1 and target.hand_size() == 1 and p.hp == 5 and target.hp == 5,
				"E03a：越权执行不询问、不收费、不生效：" + spec[1])
			# 别人的回合赠给0号出牌阶段：按实际操作者合法进入。
			tm.current_player_idx = 1
			tm.play_actor_idx = 0
			await game._on_detail_skill_clicked(spec[1], p)
			suite.check(game.get(spec[2]), "E03a：获赠出牌阶段可合法进入技能选择：" + spec[1])
			# 阶段离开再返回同值，也不能接受旧目标。
			tm.current_phase = TurnManager.Phase.END
			tm.current_phase = TurnManager.Phase.PLAY
			tm.play_actor_idx = 0
			await game.call(spec[3], target)
			suite.check(not game.get(spec[2]) and p.hand_size() == 1 and target.hand_size() == 1,
				"E03a：阶段往返拒绝旧目标并清选择状态：" + spec[1])
			await game._on_detail_skill_clicked(spec[1], p)
			suite.check(game.get(spec[2]), "E03a：过期后下一合法选择仍可开始：" + spec[1])
			tm.play_actor_idx = 1
			await game.call(spec[3], target)
			suite.check(not game.get(spec[2]) and not game._play_btn.visible and not game._end_play_btn.visible,
				"E03a：操作者变化后旧点击不恢复本人出牌按钮：" + spec[1])
			tm.play_actor_idx = 0
			game._game_over = true
			await game._on_detail_skill_clicked(spec[1], p)
			suite.check(not game.get(spec[2]), "E03a：终局后技能按钮不能复活选择：" + spec[1])
	# 已取消的装逼确认不能重复支付。
	suite.reset_players()
	tm.current_phase = TurnManager.Phase.PLAY
	var actor: Player = game.players[0]
	actor.general_name = "史蒂芬·彼特先斯"
	actor.hand.append(null)
	game.players[1].hand.append(null)
	game._zhuangbi_targets.assign([game.players[1]])
	game._is_zhuangbi_targeting = false
	await game._on_confirm_zhuangbi()
	suite.check(actor.hand_size() == 1 and game.players[1].hand_size() == 1,
		"E03a：选择模式已关闭的装逼确认不支付")
	game._zhuangbi_targets.clear()
	# 暗置先拒绝越权，不打开类型选择；明置任意时机不受出牌限制。
	suite.reset_players()
	actor.general_name = "安普提·斯丢皮得"
	actor.hand.append(null)
	tm.play_actor_idx = 1
	await game._do_sao_hide(actor, false)
	suite.check(actor.hand_size() == 1 and not actor.has_hidden_equip(), "E03a：暗置入口先核对实际出牌操作者")
	suite.reset_players()
	tm.current_phase = old_phase
