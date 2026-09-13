# A2b-2：复用实际技能入口，具体费用选择取消后不产生技能效果。
extends RefCounted

var suite
var game: GameManager

func check(ok: bool, label: String):
	suite.check(ok, "技能选牌：" + label)

func reset_case():
	suite.reset_players()
	game.deck._discard.clear()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game._lanzhonghou_used = false
	game._lanzhonghou_pending.clear()
	for p in game.players:
		p.sage_activated = false
		p.sage_tokens = 0
		p.soul_blade_activated = false
		p.facedown = false

func run(host):
	suite = host
	game = host.game
	var p = game.players[0]
	var target = game.players[1]
	var other = game.players[2]
	var first = CardBase.create(CardData.CardSubType.STRIKE)
	var second = CardBase.create(CardData.CardSubType.PEACH)
	var third = CardBase.create(CardData.CardSubType.WINE)
	for mode in ["success", "cancel", "moved", "unequipped", "target_invalid"]:
		reset_case()
		p.hand.append(first)
		p.determined_cards.append(second)
		p.equipment["armor"] = CardData.CardSubType.SAGE_PROTECTION
		p.sage_tokens = 2
		var choices: Array = []
		game._rps_override = func(actor):
			choices.append(actor)
			return 0 if actor == p else 2
		game._hand_discard_override = func(_snapshot, count, mandatory):
			check(count == 1 and not mandatory, "贤者是一张可取消费用")
			if mode == "cancel": return []
			if mode == "moved": p.determined_cards.clear()
			if mode == "unequipped": p.equipment.clear()
			if mode == "target_invalid": target.hp = 0
			return [1]
		var result = await game._sage_ping(p, target)
		if mode == "success":
			check(result and p.sage_activated and p.sage_tokens == 0, "贤者指定原牌支付后第三标记正常激活")
			check(p.hand == [first] and p.determined_cards.is_empty() and game.deck._discard == [second], "贤者精确弃所选牌")
		else:
			check(not result and not p.sage_activated and p.sage_tokens == 2 and choices.is_empty(), "贤者取消或失效不拼点、不加标记：" + mode)
			check(p.hand == [first] and game.deck._discard.is_empty(), "贤者失效不误扣其他牌：" + mode)

	for mode in ["success", "cancel", "moved", "target_invalid"]:
		reset_case()
		p.general_name = "麦克斯·欧尼斯特"
		p.hand.append(first)
		p.determined_cards.append(second)
		target.equipment["weapon"] = CardData.CardSubType.LIANNU
		other.equipment["weapon"] = CardData.CardSubType.GUDING_BLADE
		var zones: Array = ["weapon", "done"]
		game._lanzhonghou_zone_override = func(): return zones.pop_front()
		game._hand_discard_override = func(_snapshot, count, mandatory):
			check(count == 1 and not mandatory, "烂忠厚一对交换选择一张费用")
			if mode == "cancel": return []
			if mode == "moved": p.determined_cards.clear()
			if mode == "target_invalid": other.hp = 0
			return [1]
		await game._run_lanzhonghou(target, other)
		if mode == "success":
			check(target.get_weapon() == CardData.CardSubType.GUDING_BLADE and other.get_weapon() == CardData.CardSubType.LIANNU and game._lanzhonghou_used, "烂忠厚支付后才交换并记次数")
			check(game.deck._discard == [second] and p.hand == [first], "烂忠厚只弃指定牌")
		else:
			check(target.get_weapon() == CardData.CardSubType.LIANNU and other.get_weapon() == CardData.CardSubType.GUDING_BLADE and not game._lanzhonghou_used, "烂忠厚取消或失效不交换、不占次数：" + mode)
			check(game.deck._discard.is_empty() and p.hand == [first], "烂忠厚失效不支付：" + mode)
		check(game._lanzhonghou_pending.is_empty(), "烂忠厚完成/取消后清理待交换记录")

	for mode in ["success", "cancel", "moved", "unequipped", "target_invalid"]:
		reset_case()
		p.hand.assign([first, third])
		p.determined_cards.append(second)
		p.equipment["weapon"] = CardData.CardSubType.SOUL_BLADE
		p.soul_blade_activated = true
		var rps: Array = [0, 2, 0, 1] # 先赢后输，对应弃两张的分支。
		game._rps_override = func(_actor): return rps.pop_front()
		game._soul_blade_activate_override = func(): return true
		game._soul_blade_discard_override = func(): return true
		game._hand_discard_override = func(_snapshot, count, mandatory):
			check(count == 2 and not mandatory, "摄魂刀两张费用可以取消")
			if mode == "cancel": return []
			if mode == "moved": p.determined_cards.clear()
			if mode == "unequipped": p.equipment.clear()
			if mode == "target_invalid": target.hp = 0
			return [1, 2]
		await game._try_soul_blade(p, target)
		if mode == "success":
			check(target.facedown and p.hand == [first] and p.determined_cards.is_empty(), "摄魂刀跨区选择两张后翻面")
			check(game.deck._discard == [third, second], "摄魂刀一次支付所选原牌")
		else:
			check(not target.facedown and p.hand == [first, third] and game.deck._discard.is_empty(), "摄魂刀取消/失效不部分扣费也不翻面：" + mode)
	reset_case()
	game._rps_override = Callable()
	game._lanzhonghou_zone_override = Callable()
	game._soul_blade_activate_override = Callable()
	game._soul_blade_discard_override = Callable()
	game = null
	suite = null
