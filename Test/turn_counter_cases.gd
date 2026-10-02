extends RefCounted

func run(suite):
	var tm = TurnManager.new()
	tm.debug_log = false
	tm.start_game()
	var first_turn = tm.turn_id
	tm.advance_phase()
	# 回合开始/判定中已有的使用记录不能被后续摸牌抹掉。
	for key in ["duel", "aoe", "steal", "peach_garden", "harvest", "disarm"]:
		tm.use_card(key)
	tm.use_strike()
	suite.check(tm.record_strike_played(0), "E02a：本回合首次使用或打出杀登记")
	tm.advance_phase()
	tm.advance_phase()
	suite.check(tm.strikes_used() == 1 and tm.duel_count_this_turn == 1
		and tm.aoe_count_this_turn == 1 and tm.steal_count_this_turn == 1
		and not tm.can_use("peach_garden") and not tm.can_use("harvest")
		and not tm.can_use("disarm"), "E02a：判定/摸牌/出牌切换不清回合次数")
	var phase = tm.phase_id
	var revision = tm.get_context_revision()
	tm.start_waiting("strike", 1)
	tm.end_waiting()
	suite.check(tm.turn_id == first_turn and tm.phase_id == phase
		and tm.get_context_revision() > revision and tm.strikes_used() == 1,
		"E02a：响应返回保留规则阶段和次数，仅交互代次变化")
	suite.check(not tm.record_strike_played(0), "E02a：响应返回不再授予青龙首次资格")
	tm.play_actor_idx = 1
	suite.check(tm.current_player_idx == 0 and tm.can_play_strike()
		and tm.can_use("disarm"), "E02a：获赠操作者不继承回合主人的已用次数")
	tm.use_card("disarm")
	tm.use_card("duel")
	tm.use_card("duel")
	tm.use_strike()
	suite.check(not tm.can_use("duel") and not tm.can_use("disarm")
		and not tm.can_play_strike(), "E02a：获赠操作者独立达到本回合次数限制")
	tm.play_actor_idx = 0
	suite.check(tm.duel_count_this_turn == 1 and tm.disarm_count_this_turn == 1
		and tm.strikes_used() == 1, "E02a：返回原操作者恢复其既有次数")
	tm._change_phase(TurnManager.Phase.PLAY)
	suite.check(tm.phase_id == phase + 1 and tm.turn_id == first_turn
		and not tm.can_use("disarm"), "E02a：显式新阶段产生新ID但不刷新回合次数")
	tm.next_turn()
	suite.check(tm.turn_id == first_turn + 1 and tm.current_player_idx == 1
		and tm.strikes_used() == 0 and tm.can_use("disarm")
		and tm.record_strike_played(0), "E02a：下一回合开始才重置所有角色的回合历史")
	tm.use_card("disarm")
	tm.skip_play_phase = true
	tm.granted_play_target_idx = 2
	tm.start_game()
	suite.check(tm.current_player_idx == 0 and tm.can_use("disarm")
		and not tm.skip_play_phase and tm.granted_play_target_idx == -1,
		"E02a：重开清理计数及旧跳阶段/赠送调度")
	tm.free()
	# 共同出牌入口实际支付、弃装备、登记次数；赠送与原操作者各自限一次。
	var game: GameManager = suite.game
	var old_phase = game.turn_manager.current_phase
	suite.reset_players()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	var first: Player = game.players[0]
	var second: Player = game.players[1]
	var victim: Player = game.players[2]
	first.hand.append(null)
	first.hand.append(null)
	second.hand.append(null)
	second.hand.append(null)
	for seat in [0, 1]:
		game.turn_manager.play_actor_idx = seat
		var mount = CardBase.create(CardData.CardSubType.MOUNT_PLUS)
		victim.equip_card_to_slot("mount_1", mount)
		await game.play_card(CardData.CardSubType.DISARM)
		suite.check(game.players[seat].hand_size() == 1 and victim.get_equipment_card("mount_1") == null
			and game.deck._discard.count(mount) == 1 and game.turn_manager.disarm_count_this_turn == 1,
			"E02a：实际操作者独立支付卸甲、弃原装备并登记次数")
		var retained = CardBase.create(CardData.CardSubType.MOUNT_PLUS)
		victim.equip_card_to_slot("mount_1", retained)
		await game.play_card(CardData.CardSubType.DISARM)
		suite.check(game.players[seat].hand_size() == 1 and victim.get_equipment_card("mount_1") == retained,
			"E02a：同操作者第二张卸甲被真实入口拒绝且不付费")
		victim.remove_equipment("mount_1")
	game.turn_manager.play_actor_idx = 0
	suite.check(not game.turn_manager.can_use("disarm") and game.turn_manager.current_player_idx == 0,
		"E02a：结束借用操作者后原回合身份与次数保留")
	suite.reset_players()
	game.turn_manager.current_phase = old_phase
