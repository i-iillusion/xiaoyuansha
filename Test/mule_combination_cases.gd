extends RefCounted

func run(suite):
	var game: GameManager = suite.game
	var prompt = load("res://Test/mule_prompt_cases.gd").new()
	prompt.suite = suite
	prompt.game = game
	for action in ["choose", "cancel", "close", "phase", "phase_idle"]:
		prompt.reset()
		var victim = game.players[0]
		var target = game.players[2]
		var minus = CardBase.create(CardData.CardSubType.MULE_MINUS)
		var plus = CardBase.create(CardData.CardSubType.MULE_PLUS)
		victim.equip_card_to_slot(Player.MOUNT_SLOTS[2], minus)
		victim.equip_card_to_slot(Player.MOUNT_SLOTS[3], plus)
		var plus_calls: Array = []
		game._plus_mule_target_override = func():
			plus_calls.append(true)
			return target
		prompt.drive.call_deferred(action, victim, target, CardData.CardSubType.MULE_MINUS)
		await game._deal_damage(game.players[1], victim, 1, EffectChain.DamageType.PHYSICAL)
		var valid = action in ["choose", "cancel"]
		suite.check(victim.hp == 9 and plus_calls.size() == (1 if valid else 0), "E03e-13a-i：同持两种马，前窗口取消继续、失效不打开后窗口")
		var minus_owners = game.players.filter(func(p): return p.equipment_cards.values().has(minus))
		var plus_owners = game.players.filter(func(p): return p.equipment_cards.values().has(plus))
		suite.check(minus_owners.size() == 1 and minus_owners[0] == (target if action == "choose" else victim), "E03e-13a-i：第一匹原马唯一，取消/失效不移动")
		suite.check(plus_owners.size() == 1 and plus_owners[0] == (target if valid else victim), "E03e-13a-i：第二匹按原后效顺序有效转移，不复用第一窗口答复")
		suite.check(not game.deck._discard.has(minus) and not game.deck._discard.has(plus) and game._choice_prompt_stack.is_empty(), "E03e-13a-i：非满槽无弃原马、独立等待清理")
		await suite.process_frame
	for sub in [CardData.CardSubType.MULE_MINUS, CardData.CardSubType.MULE_PLUS]:
		prompt.reset()
		var victim = game.players[2]
		var mule = CardBase.create(sub)
		victim.equip_card_to_slot(Player.MOUNT_SLOTS[1], mule)
		await game._deal_damage(game.players[1], victim, 1, EffectChain.DamageType.PHYSICAL)
		var owners = game.players.filter(func(p): return p.equipment_cards.values().has(mule))
		suite.check(victim.hp == 9 and owners.size() == 1 and owners[0] != victim and owners[0].is_alive(), "E03e-13a-i：两种马AI沿用其他存活角色随机策略，原马单一所有者")
		suite.check(not game.deck._discard.has(mule) and game._choice_prompt_stack.is_empty(), "E03e-13a-i：AI非满槽移动不造选择费用或人类窗口")
		await suite.process_frame
	prompt.reset()
	prompt.suite = null
	prompt.game = null
