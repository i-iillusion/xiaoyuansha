extends RefCounted

var suite
var game: GameManager

func check(ok: bool, label: String):
	suite.check(ok, "D03a：" + label)

func reset_case():
	suite.reset_players()
	game.deck._discard.clear()
	game.equipment_pool.clear()
	game._clear_pending_determined_card()
	game._dodge_override = Callable()
	game._ai_response_override = Callable()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game.turn_manager.current_player_idx = 1
	game.turn_manager.aoe_count_this_turn = 0
	game.turn_manager.duel_count_this_turn = 0
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
	game.ai_driver.chooser = func(_view, options):
		for i in options.size():
			if options[i].target == 2:
				return i
		return 0
	for concrete in [false, true]:
		reset_case()
		var attacker: Player = game.players[1]
		var defender: Player = game.players[2]
		attacker.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
		var mount = CardBase.create(CardData.CardSubType.MOUNT_MINUS)
		attacker.determined_cards.append(mount)
		var dodge: CardBase = CardBase.create(CardData.CardSubType.DODGE) if concrete else null
		defender.hand.append(dodge)
		defender.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.BAGUA_ZHEN))
		var revision = game.turn_manager.get_context_revision()
		await game._run_ai_play(attacker)
		check(defender.hp == 10 and defender.hand == [null], "非0响应闪后八卦只摸一张，任意/具体支付")
		check(not concrete or game.deck._discard.count(dodge) == 1, "具体闪原实例恰好弃一次")
		check(attacker.get_equipment_card("mount_1") == mount and attacker.hand_size() == 0,
			"杀被AI闪后发起者继续装备，未被响应代次切换卡住")
		check(game.turn_manager.current_phase == TurnManager.Phase.DISCARD
			and game.turn_manager.get_context_revision() == revision + 1, "只在结束时离开PLAY，无响应阶段重入")
	reset_case()
	var a: Player = game.players[1]
	var b: Player = game.players[2]
	a.general_name = "杰基·斯特朗"
	var fire = CardBase.create(CardData.CardSubType.FIRE_STRIKE)
	b.determined_cards.append(fire)
	await game._play_duel(a, b)
	check(b.hp == 9 and b.hand_size() == 0 and game.deck._discard.count(fire) == 1,
		"霸王先支付第一张属性杀，缺第二张仍受伤且不退牌")
	check(game.turn_manager.strikes_used() == 0, "响应属性杀不消耗主动杀次数")
	reset_case()
	a.hand.append(CardBase.create(CardData.CardSubType.BARBARIAN_INVASION))
	var thunder = CardBase.create(CardData.CardSubType.THUNDER_STRIKE)
	b.hand.append(thunder)
	game.players[3].determined_cards.append(CardBase.create(CardData.CardSubType.DODGE))
	await game.play_card(CardData.CardSubType.BARBARIAN_INVASION)
	check(b.hp == 10 and b.hand_size() == 0 and game.deck._discard.count(thunder) == 1,
		"AI用原属性杀响应真实南蛮")
	check(game.players[3].hp == 9 and game.players[3].hand_size() == 1, "具体闪不能响应南蛮")
	reset_case()
	b.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	game._ai_response_override = func(view, _kind, options):
		check(view.actor == 2 and options == [CardData.CardSubType.STRIKE], "策略得到对应座位及合法响应类型")
		game.turn_manager.current_phase = TurnManager.Phase.END
		return options[0]
	await game._play_duel(a, b)
	check(b.hp == 10 and b.hand_size() == 1, "决斗响应过期不支付也不继续旧伤害")
	for concrete in [false, true]:
		reset_case()
		a.hand.append(CardBase.create(CardData.CardSubType.BARBARIAN_INVASION))
		var nullify: CardBase = CardBase.create(CardData.CardSubType.NULLIFICATION) if concrete else null
		b.hand.append(nullify)
		game._ai_response_override = func(view, kind, options):
			return options[0] if kind == "nullification" and view.actor == 2 and not options.is_empty() else -1
		await game.play_card(CardData.CardSubType.BARBARIAN_INVASION)
		check(b.hp == 10 and b.hand_size() == 0 and game.players[3].hp == 9,
			"非0号无懈仅抵消对自己的本次南蛮效果，后续目标继续")
		check(not concrete or game.deck._discard.count(nullify) == 1, "无懈保留具体牌原实例支付")
		reset_case()
		var c: Player = game.players[3]
		var sacrifice: CardBase = CardBase.create(CardData.CardSubType.SACRIFICE) if concrete else null
		c.hand.append(sacrifice)
		var retained = CardBase.create(CardData.CardSubType.DODGE)
		c.determined_cards.append(retained)
		game._ai_response_override = func(view, kind, options):
			return options[0] if kind == "sacrifice" and view.actor == 3 and not options.is_empty() else -1
		await game._deal_damage(a, b, 2, EffectChain.DamageType.PHYSICAL)
		check(b.hp == 10 and c.hp == 8 and c.determined_cards == [retained],
			"非0号舍己策略接独立伤害，不额外支付闪")
		check(c.hand.is_empty() and (not concrete or game.deck._discard.count(sacrifice) == 1), "舍己任意/具体牌只支付一次")
	reset_case()
	game._rescue_choice_override = Callable()
	b.hp = -1
	b.hand.append(null)
	var peach = CardBase.create(CardData.CardSubType.PEACH)
	b.determined_cards.append(peach)
	await game._run_rescue_round(b)
	check(b.hp == 1 and b.hand_size() == 0 and game.deck._discard.size() == 2
		and game.deck._discard.count(peach) == 1, "负体力AI通过统一策略连续支付两张桃自救")
	var view = game._ai_observation(b)
	view.mode = GameManager.MODE_CLASSIC_IDENTITY
	view.players[2].identity = "反贼"
	view.players[3].identity = ""
	view["response"] = {"target": 3}
	check(ResponsePolicy.choose(view, "rescue", [CardData.CardSubType.PEACH]) == -1, "救援策略不猜测未公开同阵营身份")
	view.players[3].identity = "反贼"
	check(ResponsePolicy.choose(view, "rescue", [CardData.CardSubType.PEACH]) == CardData.CardSubType.PEACH,
		"公开同阵营后保守策略愿意救援")
	game.ai_driver.chooser = previous_chooser
	suite.reset_players()
	game.turn_manager.current_phase = phase
	game.turn_manager.phase_changed.connect(game._on_phase_changed)
