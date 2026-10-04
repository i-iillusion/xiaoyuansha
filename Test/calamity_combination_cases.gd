extends RefCounted

func run(suite):
	var game: GameManager = suite.game
	var prompt = load("res://Test/calamity_prompt_cases.gd").new()
	prompt.suite = suite
	prompt.game = game
	var events: Array = []
	var collect = func(event): events.append(event)
	game.card_action_committed.connect(collect)
	for concrete in [false, true]:
		for kind in ["empty", "hidden_any", "hidden_concrete"]:
			for action in ["choose", "cancel", "phase"]:
				prompt.reset()
				var source = game.players[0]
				var victim = game.players[1]
				var target = game.players[2]
				var hidden: CardBase = null
				if kind != "empty":
					target.general_name = "安普提·斯丢皮得"
					if kind == "hidden_any": target.hand.append(null)
					else: target.determined_cards.append(CardBase.create(CardData.CardSubType.QINGLONG_BLADE))
					game.turn_manager.play_actor_idx = 2
					game._sao_type_override = func(): return "weapon"
					await game._do_sao_hide(target, false)
					game._sao_type_override = Callable()
					game.turn_manager.play_actor_idx = -1
					hidden = target.get_hidden_equipment_card("weapon")
					suite.check(hidden != null and target.hand_size() == 0, "E03e-11b：目标真实支付原牌暗置武器")
				var sword = CardBase.create(CardData.CardSubType.CALAMITY_SWORD)
				source.equip_card_to_slot("weapon", sword)
				game._claim_equipment_name(CardData.CardSubType.CALAMITY_SWORD, sword)
				source.wine_stacks = 1
				var kill = CardBase.create(CardData.CardSubType.STRIKE) if concrete else null
				if concrete: source.determined_cards.append(kill)
				else: source.hand.append(null)
				var declarations: Array = []
				game._sao_reveal_sub_override = func():
					declarations.append(true)
					return CardData.CardSubType.LIANNU
				events.clear()
				prompt.drive.call_deferred(action, source, target)
				await game.execute_card_on_target(victim, CardData.CardSubType.STRIKE)
				var moved = action == "choose"
				suite.check(game._equipment_resource_for_pick(target, "weapon") == (sword if moved else hidden) and source.get_equipment_card("weapon") == (null if moved else sword), "E03e-11b：空槽或暗置槽只移动原剑一次")
				suite.check(hidden == null or (game.deck._discard.count(hidden) == (1 if moved else 0) and hidden.sub_type == CardData.CardSubType.HIDDEN_EQUIPMENT), "E03e-11b：替换暗置原牌仍暗置且仅弃一次")
				suite.check(declarations.is_empty() and game.equipment_pool.is_claimed_original(CardData.CardSubType.CALAMITY_SWORD, sword), "E03e-11b：被弃不声明，转移不另造或释放占名")
				suite.check(victim.hp == 9 and events.size() == 1 and source.hand_size() == 0, "E03e-11b：真实伤害及一次原杀支付保留")
				await suite.process_frame
	game._sao_reveal_sub_override = Callable()
	prompt.reset()
	var source = game.players[0]
	var victim = game.players[1]
	var sword = CardBase.create(CardData.CardSubType.CALAMITY_SWORD)
	source.equip_card_to_slot("weapon", sword)
	events.clear()
	prompt.drive.call_deferred("choose", source, game.players[2])
	await game._deal_damage(source, victim, 3, EffectChain.DamageType.PHYSICAL)
	suite.check(victim.hp == 8 and game.players[2].get_equipment_card("weapon") == sword and events.is_empty(), "E03e-11b：统一伤害入口减伤及原剑转移，不虚构使用牌")
	prompt.reset()
	source = game.players[1]
	victim = game.players[2]
	sword = CardBase.create(CardData.CardSubType.CALAMITY_SWORD)
	source.equip_card_to_slot("weapon", sword)
	source.wine_stacks = 1
	source.hand.append(null)
	game.turn_manager.play_actor_idx = 1
	await game.execute_card_on_target(victim, CardData.CardSubType.STRIKE)
	var owners = game.players.filter(func(p): return p.get_equipment_card("weapon") == sword)
	suite.check(victim.hp == 9 and owners.size() == 1 and owners[0] != source and game._choice_prompt_stack.is_empty(), "E03e-11b：AI原策略随机其他存活角色，不等待0号或复制剑")
	game.card_action_committed.disconnect(collect)
	await suite.process_frame
	prompt.reset()
	prompt.suite = null
	prompt.game = null
