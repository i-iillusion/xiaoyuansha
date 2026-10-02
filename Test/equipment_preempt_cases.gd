# DEV-C01：真实出牌入口，抢先只针对尚未成功声明的他人唯一装备。
extends RefCounted

var suite
var game: GameManager

func check(ok: bool, label: String):
	suite.check(ok, "C01：" + label)

func reset_case():
	suite.reset_players()
	game.equipment_pool.clear()
	game.deck._discard.clear()
	game._clear_pending_determined_card()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	for p in game.players:
		p.hidden_equip_slot = ""
		p.hidden_equip_card = null
		p.mount_plus = 0
		p.mount_minus = 0

func run(host):
	suite = host
	game = host.game
	var phase = game.turn_manager.current_phase
	for concrete in [false, true]:
		for owner_seat in [0, 2]:
			for mode in ["accept", "refuse", "phase", "source_changed", "hand_changed", "self"]:
				reset_case()
				var owner: Player = game.players[owner_seat]
				var actor: Player = owner if mode == "self" else game.players[1]
				owner.general_name = "安普提·斯丢皮得"
				var hidden = CardBase.create(CardData.CardSubType.HIDDEN_EQUIPMENT)
				hidden.hidden_category = "weapon"
				owner.equip_hidden_card_to_slot("weapon", hidden)
				var sub = CardData.CardSubType.LIANNU
				var supplied: CardBase = CardBase.create(sub) if concrete else null
				actor.hand.append(supplied)
				game.turn_manager.current_player_idx = actor.seat_index
				var calls: Array = []
				game._sao_reveal_override = func():
					calls.append(true)
					if mode == "phase":
						game.turn_manager.current_phase = TurnManager.Phase.END
						game.turn_manager.current_phase = TurnManager.Phase.PLAY
					elif mode == "source_changed":
						owner.determined_cards.append(owner.remove_equipment("weapon"))
					elif mode == "hand_changed":
						actor.hand.clear()
					return mode != "refuse"
				await game.play_card(sub)
				check(calls.size() == (0 if mode == "self" else 1), "抢先询问人和次数：" + mode)
				if mode == "accept":
					check(owner.get_equipment_card("weapon") == hidden and hidden.sub_type == sub
						and actor.hand_size() == 1 and not actor.equipment.has("weapon"), "非0/0座位抢先后对方不支付")
				elif mode in ["refuse", "source_changed", "self"]:
					check(actor.get_weapon() == sub and actor.hand_size() == 0, "无合法抢先时原动作正常支付：" + mode)
					if concrete:
						check(actor.get_equipment_card("weapon") == supplied, "具体装备保留原实例")
					if mode == "refuse":
						check(owner.get_hidden_equipment_card("weapon") == hidden, "拒绝后仍暗置，不能追认已占名")
				else:
					check(not actor.equipment.has("weapon") and owner.get_hidden_equipment_card("weapon") == hidden,
						"行动/手牌过期不抢先也不继续旧出牌：" + mode)
					if actor.hand.is_empty():
						actor.hand.append(null)
					game._sao_reveal_override = func(): return false
					await game.play_card(sub)
					check(actor.get_weapon() == sub and actor.hand_size() == 0, "过期后下一合法出牌可继续")
	for sub in [CardData.CardSubType.MOUNT_PLUS, CardData.CardSubType.MOUNT_MINUS,
		CardData.CardSubType.MULE_PLUS, CardData.CardSubType.MULE_MINUS]:
		reset_case()
		var owner: Player = game.players[0]
		var actor: Player = game.players[1]
		owner.general_name = "安普提·斯丢皮得"
		var hidden = CardBase.create(CardData.CardSubType.HIDDEN_EQUIPMENT)
		hidden.hidden_category = "mount"
		owner.equip_hidden_card_to_slot("mount_1", hidden)
		var calls: Array = []
		game._sao_reveal_override = func():
			calls.append(true)
			return true
		actor.hand.append(null)
		game.turn_manager.current_player_idx = 1
		await game.play_card(sub)
		check(calls.is_empty() and actor.mount_count() == 1 and actor.hand_size() == 0
			and owner.get_hidden_equipment_card("mount_1") == hidden, "四种坐骑均不询问抢先阻止")
	game._sao_reveal_override = Callable()
	reset_case()
	game.turn_manager.current_phase = phase
