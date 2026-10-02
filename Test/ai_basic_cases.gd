extends RefCounted

var suite
var game: GameManager

func check(ok: bool, label: String):
	suite.check(ok, "D02a：" + label)

func reset_case():
	suite.reset_players()
	game.deck._discard.clear()
	game.equipment_pool.clear()
	game._clear_pending_determined_card()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game.turn_manager.current_player_idx = 1
	for p in game.players:
		p.mount_minus = 0
		p.mount_plus = 0
		p.hidden_equip_slot = ""
		p.hidden_equip_card = null

func run(host):
	suite = host
	game = host.game
	var phase = game.turn_manager.current_phase
	game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
	var previous_chooser = game.ai_driver.chooser
	game.ai_driver.chooser = func(_view, _options): return 0
	for concrete in [false, true]:
		reset_case()
		var p: Player = game.players[1]
		p.hp = 9
		var peach: CardBase = CardBase.create(CardData.CardSubType.PEACH) if concrete else null
		p.hand.append(peach)
		await game._run_ai_play(p)
		check(p.hp == 10 and p.hand_size() == 0 and game.turn_manager.current_phase == TurnManager.Phase.DISCARD,
			"非0号通过真实用桃支付并结束阶段，任意/具体牌")
		check(game.deck._discard.size() == 1 and (not concrete or game.deck._discard[0] == peach), "用桃原实例恰好入弃一次")
	reset_case()
	var actor: Player = game.players[1]
	var dodge = CardBase.create(CardData.CardSubType.DODGE)
	actor.determined_cards.append(dodge)
	await game._run_ai_play(actor)
	check(actor.determined_cards == [dodge] and game.turn_manager.strikes_used() == 0, "具体闪不能声明杀或装备")
	reset_case()
	actor.hand.append(CardBase.create(CardData.CardSubType.WINE))
	var strike = CardBase.create(CardData.CardSubType.STRIKE)
	actor.determined_cards.append(strike)
	await game._run_ai_play(actor)
	check(actor.hand_size() == 0 and game.players[0].hp == 8
		and game.turn_manager.strikes_used() == 1 and actor.wine_stacks == 0, "先酒后杀，真实伤害消费酒与杀次数")
	check(game.deck._discard.count(strike) == 1, "具体杀原实例支付一次")
	reset_case()
	actor.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	game.players[0].equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.TENGJIA))
	game.players[2].general_name = "凯文·罗本"
	check(game._ai_play_candidates(game._ai_observation(actor)).is_empty(), "藤甲/裸奔与距离限制共用合法目标查询")
	for concrete in [false, true]:
		reset_case()
		var sword: CardBase = CardBase.create(CardData.CardSubType.LIANNU) if concrete else null
		actor.hand.append(sword)
		game.turn_manager.use_strike()
		# 策略注入只从合法候选中选择连弩。
		game.ai_driver.chooser = func(_view, options):
			for i in options.size():
				if options[i].sub == CardData.CardSubType.LIANNU:
					return i
			return -1
		await game._run_ai_play(actor)
		check(actor.get_weapon() == CardData.CardSubType.LIANNU and actor.hand_size() == 0,
			"任意/具体连弩走真实装备入口")
		check(not concrete or actor.get_equipment_card("weapon") == sword, "具体装备保留原实例")
	reset_case()
	game.equipment_pool.claim(CardData.CardSubType.LIANNU)
	actor.hand.append(CardBase.create(CardData.CardSubType.LIANNU))
	check(game._ai_play_candidates(game._ai_observation(actor)).is_empty(), "唯一名已占用不能新造同名装备")
	reset_case()
	actor.hand.append(CardBase.create(CardData.CardSubType.PEACH))
	actor.hp = 9
	var old_choices = game._ai_play_candidates(game._ai_observation(actor))
	actor.hand.clear()
	actor.hand.append(null)
	await game._execute_ai_action(old_choices[0])
	check(actor.hp == 9 and actor.hand == [null], "决策期间换牌不挪用新牌支付旧动作")
	game.ai_driver.chooser = previous_chooser
	reset_case()
	game.turn_manager.current_player_idx = 0
	game.turn_manager.current_phase = phase
	game.turn_manager.phase_changed.connect(game._on_phase_changed)
