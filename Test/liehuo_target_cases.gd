# C02：新盾只在拆/顺的目标窗口询问一次；区域移动不再提供通用替代。
extends RefCounted

var suite
var game: GameManager

func check(ok: bool, label: String):
	suite.check(ok, "C02：" + label)

func reset_case():
	suite.reset_players()
	game.deck._discard.clear()
	game.equipment_pool.clear()
	game._clear_pending_determined_card()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	for p in game.players:
		p.judgment_cards.clear()
		p.identity = "反贼" if p.seat_index == 1 else ("主公" if p.seat_index == 0 else "忠臣")
		p.sage_activated = false
	game._zone_pick_override = func(): return "hand"
	game._equip_pick_override = func(): return "armor"

func run(host):
	suite = host
	game = host.game
	var phase = game.turn_manager.current_phase
	for snatch in [false, true]:
		for concrete in [false, true]:
			for mode in ["accept", "refuse", "phase", "shield_moved", "saved", "dead"]:
				reset_case()
				var actor: Player = game.players[0]
				var target: Player = game.players[1]
				var shield = CardBase.create(CardData.CardSubType.LIEHUO_SHIELD)
				target.equip_card_to_slot("armor", shield)
				var retained = CardBase.create(CardData.CardSubType.STRIKE)
				target.hand.append(retained)
				var sub = CardData.CardSubType.SNATCH if snatch else CardData.CardSubType.DISMANTLE
				var payment: CardBase = CardBase.create(sub) if concrete else null
				actor.hand.append(payment)
				if mode in ["saved", "dead"]:
					target.hp = 1
				if mode == "saved":
					game.players[2].hand.append(CardBase.create(CardData.CardSubType.PEACH))
					game._rescue_choice_override = func(rescuer, _dying, options):
						return CardData.CardSubType.PEACH if rescuer == game.players[2] and options.has(CardData.CardSubType.PEACH) else -1
				var calls: Array = []
				game._liehuo_override = func():
					calls.append(true)
					if mode == "phase":
						game.turn_manager.current_phase = TurnManager.Phase.END
						game.turn_manager.current_phase = TurnManager.Phase.PLAY
					elif mode == "shield_moved":
						target.determined_cards.append(target.remove_equipment("armor"))
					return mode != "refuse"
				await game._play_steal_card(actor, target, snatch)
				check(calls.size() == 1, "每次拆/顺只问一次盾：" + mode)
				if concrete:
					check(game.deck._discard.count(payment) == 1, "拆/顺原牌费用只弃一次")
				if mode in ["accept", "saved", "phase"]:
					check(target.hand == [retained] and not actor.hand.has(retained), "整牌无效/过期后不继续移动目标牌：" + mode)
					check(target.hp == (9 if mode == "accept" else (1 if mode == "saved" else 10)), "确认只失血一次；过期不失血：" + mode)
				elif mode == "dead":
					check(target.is_dead() and game.deck._discard.count(retained) == 1
						and game.deck._discard.count(shield) == 1 and actor.hand.is_empty(), "盾致死只清牌一次且无击杀奖励/偷牌")
				else:
					check(target.hp == 10 and target.hand.is_empty(), "拒绝或盾离区不支付体力，拆/顺正常继续")
					check(actor.hand.has(retained) if snatch else game.deck._discard.count(retained) == 1, "正常拆/顺仍移动具体原牌一次")
	# 装备/判定区也由同一目标窗口保护，不晚到选装备时重复询问。
	for zone in ["equip", "judgment"]:
		reset_case()
		var actor: Player = game.players[0]
		var target: Player = game.players[1]
		var shield = CardBase.create(CardData.CardSubType.LIEHUO_SHIELD)
		var judgment = CardBase.create(CardData.CardSubType.INDULGENCE)
		target.equip_card_to_slot("armor", shield)
		target.judgment_cards.append(judgment)
		actor.hand.append(null)
		game._zone_pick_override = func(): return zone
		game._liehuo_override = func(): return true
		await game._play_steal_card(actor, target, true)
		check(target.hp == 9 and target.get_equipment_card("armor") == shield
			and target.judgment_cards == [judgment], "目标窗口保护所有选中区域：" + zone)
	reset_case()
	game._liehuo_override = Callable()
	game._zone_pick_override = Callable()
	game._equip_pick_override = Callable()
	game.turn_manager.current_phase = phase
