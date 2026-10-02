extends RefCounted

const WINE = CardData.CardSubType.WINE

func run(suite):
	var game: GameManager = suite.game
	var tm = game.turn_manager
	var old_phase = tm.current_phase
	tm.phase_changed.disconnect(game._on_phase_changed)
	for seat in [0, 1]:
		for concrete in [false, true]:
			suite.reset_players()
			tm.current_player_idx = seat
			tm._change_phase(TurnManager.Phase.PLAY)
			var p: Player = game.players[seat]
			var target: Player = game.players[seat + 1]
			var first: CardBase = CardBase.create(WINE) if concrete else null
			var second: CardBase = CardBase.create(WINE) if concrete else null
			p.hand.append(first)
			await game.play_card(WINE)
			p.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
			await game.execute_card_on_target(target, CardData.CardSubType.STRIKE)
			suite.check(target.hp == 8 and p.wine_stacks == 0 and tm.wine_count_this_turn == 1,
				"E02c：真实酒杀消耗加伤层数，仍保留本回合用酒次数")
			if concrete:
				p.determined_cards.append(second)
			else:
				p.hand.append(null)
			await game.play_card(WINE)
			suite.check(p.hand_size() == 1 and p.wine_stacks == 0 and tm.wine_count_this_turn == 1
				and (not concrete or game.deck._discard.count(second) == 0),
				"E02c：出杀后同回合第二张普通酒被拒，不弃原牌")
			tm._change_phase(TurnManager.Phase.PLAY)
			suite.check(not game.can_declare_basic(p, WINE), "E02c：新增出牌阶段不刷新回合酒额度")
			p.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.RAGING_AXE))
			await game.play_card(WINE)
			p.hand.append(null)
			await game.play_card(WINE)
			suite.check(p.wine_stacks == 2 and p.raging_wine_stacks == 2 and tm.wine_count_this_turn == 3,
				"E02c：装备战斧后可超次数叠加，但仍记录真实使用历史")
			p.remove_equipment("weapon")
			p.hand.append(null)
			await game.play_card(WINE)
			suite.check(p.wine_stacks == 0 and p.hand_size() == 1 and tm.wine_count_this_turn == 3,
				"E02c：失去战斧清其加伤，不清次数或再获普通酒额度")
			tm.next_turn()
			tm._change_phase(TurnManager.Phase.PLAY)
			tm.play_actor_idx = seat
			await game.play_card(WINE)
			suite.check(p.hand_size() == 0 and p.wine_stacks == 1 and tm.wine_count_this_turn == 1,
				"E02c：新回合实际操作者重新获得普通酒额度")
			p.hp = -1
			for i in 2:
				p.hand.append(null)
				suite.check(game._use_rescue_card(p, p, WINE), "E02c：本回合主动酒已用仍可连续濒死自救")
			suite.check(p.hp == 1 and p.wine_stacks == 1 and tm.wine_count_this_turn == 1,
				"E02c：自救酒只回复，不加伤且不增加主动酒次数")
			suite.check(not concrete or game.deck._discard.count(first) == 1
				and game.deck._discard.count(second) == 1, "E02c：合法具体酒各以原实例弃一次")
	suite.reset_players()
	tm._change_phase(TurnManager.Phase.PLAY)
	var p: Player = game.players[0]
	p.hp = 0
	p.hand.assign([null, null])
	suite.check(game._use_rescue_card(p, p, WINE) and tm.wine_count_this_turn == 0
		and game.can_declare_basic(p, WINE), "E02c：先自救不会占用本回合尚未使用的主动酒额度")
	suite.reset_players()
	tm.current_phase = old_phase
	tm.phase_changed.connect(game._on_phase_changed)
