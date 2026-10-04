extends RefCounted

func run(suite):
	var game: GameManager = suite.game
	var prompt = load("res://Test/ice_sword_prompt_cases.gd").new()
	prompt.suite = suite
	prompt.game = game
	for concrete_kill in [false, true]:
		for concrete_hand in [false, true]:
			for action in ["yes", "no", "phase", "close"]:
				prompt.reset()
				var source = game.players[0]
				var target = game.players[1]
				target.hp = 3
				source.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.ICE_SWORD))
				var only = CardBase.create(CardData.CardSubType.PEACH) if concrete_hand else null
				if concrete_hand: target.determined_cards.append(only)
				else: target.hand.append(null)
				var kill = CardBase.create(CardData.CardSubType.STRIKE) if concrete_kill else null
				if concrete_kill: source.determined_cards.append(kill)
				else: source.hand.append(null)
				prompt.drive.call_deferred(action, source, target)
				await game.execute_card_on_target(target, CardData.CardSubType.STRIKE)
				suite.check(target.hp == (2 if action == "no" else 3), "E03-R01a：一张手牌可发动防伤，拒绝正常受伤")
				suite.check(target.hand_size() == (0 if action == "yes" else 1), "E03-R01a：不足全弃，拒绝或失效保留原牌")
				suite.check(not concrete_hand or game.deck._discard.count(only) == (1 if action == "yes" else 0), "E03-R01a：唯一具体原牌只弃一次")
				suite.check(source.hand_size() == 0 and (not concrete_kill or game.deck._discard.count(kill) == 1), "E03-R01a：防伤或失效不退原杀费用")
				await suite.process_frame
	prompt.reset()
	var source = game.players[0]
	var target = game.players[1]
	source.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.ICE_SWORD))
	source.hand.append(null)
	await game.execute_card_on_target(target, CardData.CardSubType.STRIKE)
	suite.check(target.hp == 9 and game._choice_prompt_stack.is_empty(), "E03-R01a：零手牌不发动，不打开等待窗口")
	prompt.reset()
	prompt.suite = null
	prompt.game = null
