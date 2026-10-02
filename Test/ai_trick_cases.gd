extends RefCounted

var suite
var game: GameManager

func check(ok: bool, label: String):
	suite.check(ok, "D03b：" + label)

func reset_case():
	suite.reset_players()
	game.deck._discard.clear()
	game.equipment_pool.clear()
	game._clear_pending_determined_card()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game.turn_manager.current_player_idx = 1
	game.turn_manager.duel_count_this_turn = 0
	game.turn_manager.aoe_count_this_turn = 0
	game.turn_manager.steal_count_this_turn = 0
	game.turn_manager.harvest_count_this_turn = 0
	game.turn_manager.peach_garden_count_this_turn = 0
	game.turn_manager.disarm_count_this_turn = 0
	for p in game.players:
		p.mount_minus = 0
		p.mount_plus = 0
		p.judgment_cards.clear()
		p.hidden_equip_slot = ""
		p.hidden_equip_card = null

func run(host):
	suite = host
	game = host.game
	var phase = game.turn_manager.current_phase
	var previous_chooser = game.ai_driver.chooser
	game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
	for sub in GameManager.TARGET_TRICKS + GameManager.GLOBAL_TRICKS:
		for concrete in [false, true]:
			reset_case()
			var a: Player = game.players[1]
			var b: Player = game.players[2]
			var payment: CardBase = CardBase.create(sub) if concrete else null
			a.hand.append(payment)
			var retained = CardBase.create(CardData.CardSubType.DODGE)
			if sub in [CardData.CardSubType.SNATCH, CardData.CardSubType.DISMANTLE]:
				b.determined_cards.append(retained)
			if sub in [CardData.CardSubType.PEACH_GARDEN, CardData.CardSubType.HARVEST]:
				a.hp = 9
				b.hp = 9
			if sub == CardData.CardSubType.DISARM:
				b.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.LIANNU))
			var selected: Array = []
			game.ai_driver.chooser = func(_view, options):
				if not selected.is_empty():
					return -1
				for i in options.size():
					if options[i].sub == sub and options[i].target in [-1, 2]:
						selected.append(sub)
						return i
				return -1
			await game._run_ai_play(a)
			check(selected == [sub] and game.turn_manager.current_phase == TurnManager.Phase.DISCARD,
				"非0号合法候选真实执行并结束：" + CardData.get_type_name(sub))
			if sub in [CardData.CardSubType.INDULGENCE, CardData.CardSubType.SUPPLY_SHORTAGE, CardData.CardSubType.BURNING_CAMP]:
				check(b.judgment_cards.size() == 1 and b.judgment_cards[0].sub_type == sub
					and (not concrete or b.judgment_cards[0] == payment), "延时锦囊原牌进入目标判定区")
			else:
				check(not concrete or game.deck._discard.count(payment) == 1, "具体锦囊费用原实例恰好入弃一次")
			match sub:
				CardData.CardSubType.SNATCH:
					check(b.hand_size() == 0 and a.hand.has(retained), "顺走保持具体原牌，AI选区不依赖0号按钮")
				CardData.CardSubType.DISMANTLE:
					check(b.hand_size() == 0 and game.deck._discard.count(retained) == 1, "拆除真实目标原牌")
				CardData.CardSubType.DUEL, CardData.CardSubType.BARBARIAN_INVASION, CardData.CardSubType.VOLLEY_OF_ARROWS:
					check(b.hp == 9, "无响应时实际受到锦囊伤害")
				CardData.CardSubType.PEACH_GARDEN:
					check(a.hp == 10 and b.hp == 10, "群体回复依次结算")
				CardData.CardSubType.HARVEST:
					check(a.hand == [null] and b.hand == [null], "群体摸牌仍是任意牌")
				CardData.CardSubType.DISARM:
					check(b.equipment.is_empty() and b.hand == [null], "卸甲弃原装备并摸同数量任意牌")
				CardData.CardSubType.IRON_CHAIN:
					check(b.chained, "铁索真实单目标执行不进入真人选人窗口")
	reset_case()
	var actor: Player = game.players[1]
	actor.hand.append(CardBase.create(CardData.CardSubType.SNATCH))
	game.players[3].hand.append(null)
	check(not game.get_trick_targets(actor, CardData.CardSubType.SNATCH).has(game.players[3]), "顺手距离超限目标不可选")
	game.turn_manager.steal_count_this_turn = 2
	check(game._ai_play_candidates(game._ai_observation(actor)).is_empty(), "拆顺共用次数耗尽后无非法候选")
	game.ai_driver.chooser = previous_chooser
	reset_case()
	game.turn_manager.current_player_idx = 0
	game.turn_manager.current_phase = phase
	game.turn_manager.phase_changed.connect(game._on_phase_changed)
