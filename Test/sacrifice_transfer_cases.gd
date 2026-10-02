# C04：从真实伤害链检查原伤害防止、独立记录及转移后的修正。
extends RefCounted

var suite
var game: GameManager

func check(ok: bool, label: String):
	suite.check(ok, "C04：" + label)

func run(host):
	suite = host
	game = host.game
	var phase = game.turn_manager.current_phase
	for mode in ["plain", "source", "original_armor", "receiver_armor", "again", "chain", "source_dead", "stale"]:
		for concrete in [false, true]:
			suite.reset_players()
			game.deck._discard.clear()
			game.turn_manager.current_phase = TurnManager.Phase.PLAY
			var a: Player = game.players[0]
			var b: Player = game.players[1]
			var c: Player = game.players[2]
			var d: Player = game.players[3]
			var payment: CardBase = CardBase.create(CardData.CardSubType.SACRIFICE) if concrete else null
			c.hand.append(payment)
			var second = CardBase.create(CardData.CardSubType.SACRIFICE)
			if mode == "again":
				d.determined_cards.append(second)
			if mode == "source":
				a.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.CALAMITY_SWORD))
			if mode == "original_armor":
				b.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.SILVER_LION))
			if mode == "receiver_armor":
				c.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.SILVER_LION))
			if mode == "chain":
				c.chained = true
				d.chained = true
			game._sacrifice_actor_override = func(p, target, _amount):
				if p == c and target == b:
					if mode == "source_dead":
						a.mark_dead() # 防御性注入：等待期间来源已完成最终死亡。
					if mode == "stale":
						game.turn_manager.current_phase = TurnManager.Phase.END
					return true
				return mode == "again" and p == d and target == c
			var card = CardBase.create(CardData.CardSubType.FIRE_STRIKE)
			var original = game._new_damage_chain(a, b, card, 3, EffectChain.DamageType.FIRE)
			original.damage.is_chain = mode == "chain"
			var responses: Array = []
			original.response_callback = func(_chain, target, _sub, _source):
				responses.append(target)
				return false
			original.completion_callback = func(done):
				check(done.current_phase == EffectChain.Phase.DONE and not done.damage.committed, "新伤害开始前原链已结束")
				await game._resolve_transferred_damage(done)
			await original.start()
			await game._finish_damage_chain(original)
			check(original.current_phase == EffectChain.Phase.DONE and original.is_cancelled
				and not original.damage.committed and original.damage.target == b and b.hp == 10,
				"原目标不改写、原伤害防止并结束：" + mode)
			check(responses == [b], "只有原目标获得杀响应：" + mode)
			if mode == "stale":
				check(original.damage.transferred_damage == null and c.hp == 10
					and c.hand.has(payment) and game.deck._discard.is_empty(), "过期选择不支付、不转移")
				continue
			var moved: DamageRecord = original.damage.transferred_damage
			check(moved != null and moved != original.damage and moved.original_target == c
				and moved.source == (null if mode == "source_dead" else a) and moved.card == card and moved.from_strike
				and moved.element == EffectChain.DamageType.FIRE,
				"转移创建独立记录并继承渠道和属性：" + mode)
			check(c.hand.is_empty() and ((concrete and game.deck._discard.count(payment) == 1) or (not concrete and game.deck._discard.size() == (2 if mode == "again" else 1))),
				"任意牌/具体牌通过共同支付且仅入弃一次")
			var expected = 2 if mode == "source" else (1 if mode in ["original_armor", "receiver_armor"] else 3)
			var final = original.damage.final_damage()
			check(final.committed and final.applied_amount == expected
				and final.target.hp == 10 - expected, "来源不重复修正、目标各自修正：" + mode)
			if mode == "again":
				check(c.hp == 10 and final.target == d and moved.transferred_damage == final
					and game.deck._discard.count(second) == 1, "可以再次转移，每次仅支付自己的牌")
			if mode == "chain":
				check(final.is_chain and d.hp == 10, "连环性质保留、不产生第二轮传导")
	# 原杀被闪时没有受到伤害窗口，舍己不能提前替换目标。
	suite.reset_players()
	var offers: Array = []
	game._sacrifice_actor_override = func(p, _target, _amount):
		offers.append(p)
		return true
	var dodged = game._new_damage_chain(game.players[0], game.players[1],
		CardBase.create(CardData.CardSubType.STRIKE), 1, EffectChain.DamageType.PHYSICAL)
	dodged.response_callback = func(_chain, _target, _sub, _source): return true
	await dodged.start()
	check(dodged.response_result == EffectChain.ResponseResult.DODGED and offers.is_empty(), "闪后不询问舍己")
	suite.reset_players()
	game.turn_manager.current_phase = phase
