extends RefCounted

func run(suite):
	var game: GameManager = suite.game
	var prompt = load("res://Test/calamity_robe_prompt_cases.gd").new()
	prompt.suite = suite
	prompt.game = game
	for concrete in [false, true]:
		for kind in ["empty", "hidden_any", "hidden_concrete"]:
			for action in ["choose", "cancel", "phase"]:
				prompt.reset()
				var source = game.players[1]
				var victim = game.players[0]
				var target = game.players[2]
				var hidden: CardBase = null
				if kind != "empty":
					target.general_name = "安普提·斯丢皮得"
					if kind == "hidden_any": target.hand.append(null)
					else: target.determined_cards.append(CardBase.create(CardData.CardSubType.QINGGANG_SHIELD))
					game.turn_manager.play_actor_idx = 2
					game._sao_type_override = func(): return "armor"
					await game._do_sao_hide(target, false)
					game._sao_type_override = Callable()
					hidden = target.get_hidden_equipment_card("armor")
					suite.check(hidden != null and target.hand_size() == 0, "E03e-12b：真实支付任意/具体原牌暗置防具")
				var robe = CardBase.create(CardData.CardSubType.CALAMITY_ROBE)
				victim.equip_card_to_slot("armor", robe)
				game._claim_equipment_name(CardData.CardSubType.CALAMITY_ROBE, robe)
				if concrete: source.determined_cards.append(CardBase.create(CardData.CardSubType.STRIKE))
				else: source.hand.append(null)
				game.turn_manager.play_actor_idx = 1
				var declarations: Array = []
				game._sao_reveal_sub_override = func():
					declarations.append(true)
					return CardData.CardSubType.RENWANG_DUN
				prompt.drive.call_deferred(action, victim, target)
				await game.execute_card_on_target(victim, CardData.CardSubType.STRIKE)
				var moved = action == "choose"
				suite.check(game._equipment_resource_for_pick(target, "armor") == (robe if moved else hidden) and victim.get_equipment_card("armor") == (null if moved else robe), "E03e-12b：空槽/暗置槽仅转移原袍一次")
				suite.check(hidden == null or (hidden.sub_type == CardData.CardSubType.HIDDEN_EQUIPMENT and game.deck._discard.count(hidden) == (1 if moved else 0)), "E03e-12b：被替换暗置原牌保持暗置且仅弃一次")
				suite.check(declarations.is_empty() and game.equipment_pool.is_claimed_original(CardData.CardSubType.CALAMITY_ROBE, robe), "E03e-12b：被弃不声明，原袍转移不另造占名")
				suite.check(victim.hp == 9 and source.hand_size() == 0 and game._choice_prompt_stack.is_empty(), "E03e-12b：真实伤害和费用保留，等待释放")
				await suite.process_frame
	game._sao_reveal_sub_override = Callable()
	# 统一伤害入口与AI策略，不虚构用牌事件。
	prompt.reset()
	var victim = game.players[0]
	var robe = CardBase.create(CardData.CardSubType.CALAMITY_ROBE)
	victim.equip_card_to_slot("armor", robe)
	prompt.drive.call_deferred("choose", victim, game.players[2])
	await game._deal_damage(game.players[1], victim, 2, EffectChain.DamageType.FIRE)
	suite.check(victim.hp == 7 and game.players[2].get_equipment_card("armor") == robe, "E03e-12b：统一火伤加一后转移原袍")
	prompt.reset()
	victim = game.players[2]
	robe = CardBase.create(CardData.CardSubType.CALAMITY_ROBE)
	victim.equip_card_to_slot("armor", robe)
	await game._deal_damage(game.players[1], victim, 1, EffectChain.DamageType.PHYSICAL)
	var owners = game.players.filter(func(p): return p.get_equipment_card("armor") == robe)
	suite.check(victim.hp == 9 and owners.size() == 1 and owners[0] != victim and game._choice_prompt_stack.is_empty(), "E03e-12b：AI沿用其他存活角色随机策略，不等待0号或复制原袍")
	# 舍己真实支付后，承受者的袍窗口失效传播回原伤害链。
	for concrete in [false, true]:
		for action in ["cancel", "close", "phase"]:
			prompt.reset()
			victim = game.players[0]
			victim.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.CALAMITY_ROBE))
			var sacrifice = CardBase.create(CardData.CardSubType.SACRIFICE) if concrete else null
			if concrete: victim.determined_cards.append(sacrifice)
			else: victim.hand.append(null)
			game._sacrifice_override = Callable()
			var accept = func():
				game._choice_prompt_stack.back().overlay.find_children("*", "Button", true, false)[0].pressed.emit()
				prompt.drive.call_deferred(action, victim, game.players[2])
			accept.call_deferred()
			var chain = game._new_damage_chain(game.players[1], game.players[2], null, 2, EffectChain.DamageType.PHYSICAL)
			chain.skip_targeting = true
			chain.skip_response = true
			await chain.start()
			await game._finish_damage_chain(chain)
			suite.check(game.players[2].hp == 10 and victim.hp == 8 and chain.damage.final_damage().committed, "E03e-12b：已付舍己与独立新伤害不因后续袍失效撤销")
			suite.check(chain.is_cancelled and chain.continuation_invalid == (action != "cancel") and victim.hand_size() == 0 and (not concrete or game.deck._discard.count(sacrifice) == 1), "E03e-12b：正常防止原伤害与子链交互失效分开，原牌只付一次")
			await suite.process_frame
	# 真实酒杀经舍己后仍算造成伤害，合法袍取消后允许原剑后效；失效则停止。
	for concrete in [false, true]:
		for action in ["cancel", "close", "phase"]:
			prompt.reset()
			victim = game.players[0]
			var source = game.players[1]
			victim.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.CALAMITY_ROBE))
			victim.hand.append(null)
			source.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.CALAMITY_SWORD))
			source.wine_stacks = 1
			if concrete: source.determined_cards.append(CardBase.create(CardData.CardSubType.STRIKE))
			else: source.hand.append(null)
			game.turn_manager.play_actor_idx = 1
			game._sacrifice_override = Callable()
			var sword_calls: Array = []
			game._calamity_target_override = func():
				sword_calls.append(true)
				return "cancel"
			var accept = func():
				game._choice_prompt_stack.back().overlay.find_children("*", "Button", true, false)[0].pressed.emit()
				prompt.drive.call_deferred(action, victim, game.players[2])
			accept.call_deferred()
			await game.execute_card_on_target(game.players[2], CardData.CardSubType.STRIKE)
			suite.check(game.players[2].hp == 10 and victim.hp == 9 and source.hand_size() == 0 and victim.hand_size() == 0, "E03e-12b：真实酒杀减伤、舍己支付及独立新伤害各一次")
			suite.check(sword_calls.size() == (1 if action == "cancel" else 0), "E03e-12b：正常舍己不误判交互失效，袍失效才阻止原剑后效")
			await suite.process_frame
	game._calamity_target_override = Callable()
	# 实际连环传播中袍窗口失效，不再结算尚未提交的下一名。
	for action in ["cancel", "close", "phase"]:
		prompt.reset()
		victim = game.players[0]
		victim.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.CALAMITY_ROBE))
		for p in [victim, game.players[2], game.players[3]]: p.chained = true
		prompt.drive.call_deferred(action, victim, game.players[2])
		var chain = game._new_damage_chain(game.players[1], game.players[3], null, 1, EffectChain.DamageType.FIRE)
		chain.skip_targeting = true
		chain.skip_response = true
		await chain.start()
		await game._finish_damage_chain(chain)
		suite.check(game.players[3].hp == 9 and victim.hp == 8 and game.players[2].hp == (9 if action == "cancel" else 10), "E03e-12b：连环已伤保留，取消继续下一名、失效停止传播")
		suite.check(chain.continuation_invalid == (action != "cancel") and game._choice_prompt_stack.is_empty(), "E03e-12b：连环子窗口失效回传，独立等待清理")
		await suite.process_frame
	prompt.reset()
	prompt.suite = null
	prompt.game = null
