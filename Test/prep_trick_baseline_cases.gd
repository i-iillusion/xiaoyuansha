extends RefCounted

# F02a仅验原锦囊真实入口；没有替换效果或新次数/目标裁决。
func run(suite):
	var game: GameManager = suite.game
	var tm = game.turn_manager
	var old_phase = tm.current_phase
	var old_chooser = game.ai_driver.chooser
	var callback = game._on_phase_changed
	tm.phase_changed.disconnect(callback)
	var events: Array[CardActionEvent] = []
	var collect = func(event): events.append(event)
	game.card_action_committed.connect(collect)
	var originals = [CardData.CardSubType.DUEL, CardData.CardSubType.SNATCH,
		CardData.CardSubType.DISMANTLE, CardData.CardSubType.IRON_CHAIN,
		CardData.CardSubType.BARBARIAN_INVASION, CardData.CardSubType.VOLLEY_OF_ARROWS,
		CardData.CardSubType.PEACH_GARDEN, CardData.CardSubType.HARVEST, CardData.CardSubType.DISARM]
	for sub in originals:
		for concrete in [false, true]:
			suite.reset_players()
			events.clear()
			game.deck._discard.clear()
			game.equipment_pool.clear()
			game._clear_pending_determined_card()
			tm.current_player_idx = 1
			tm.current_phase = TurnManager.Phase.PLAY
			var actor: Player = game.players[1]
			var target: Player = game.players[2]
			actor.general_name = "里奥·普利威尔"
			var original: CardBase = CardBase.create(sub) if concrete else null
			if concrete: actor.determined_cards.append(original)
			else: actor.hand.append(null)
			if sub in [CardData.CardSubType.SNATCH, CardData.CardSubType.DISMANTLE]:
				target.hand.append(CardBase.create(CardData.CardSubType.DODGE))
			if sub in [CardData.CardSubType.PEACH_GARDEN, CardData.CardSubType.HARVEST]:
				actor.hp = 9
				target.hp = 9
			if sub == CardData.CardSubType.DISARM:
				target.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.LIANNU))
			var selected: Array = []
			game.ai_driver.chooser = func(_view, options):
				if not selected.is_empty(): return -1
				for i in options.size():
					if options[i].sub == sub and options[i].target in [-1, 2]:
						selected.append(sub)
						return i
				return -1
			await game._run_ai_play(actor)
			suite.check(selected == [sub] and tm.current_phase == TurnManager.Phase.DISCARD,
				"F02a：九种原锦囊任意/具体手牌经共同真实入口成立并结束阶段")
			suite.check(events.size() == 1 and events[0].sub_type == sub
				and events[0].actor_seat == 1 and events[0].turn_owner_seat == 1
				and events[0].kind == CardActionEvent.Kind.USE and events[0].from_hand
				and not events[0].is_virtual and actor.prep_tokens == 1,
				"F02a：九种原锦囊每张只产生一个手牌使用事实和一个预习标记")
			suite.check(events.size() == 1 and game.deck._discard.count(events[0].card) == 1
				and (not concrete or events[0].card == original),
				"F02a：原牌入弃一次且已具体手牌不换实例；不预设替换后的牌名")
	for owner in [0, 1]:
		for sub in [CardData.CardSubType.NULLIFICATION, CardData.CardSubType.SACRIFICE]:
			suite.reset_players()
			events.clear()
			game.deck._discard.clear()
			tm.current_player_idx = owner
			tm.current_phase = TurnManager.Phase.PLAY
			var actor: Player = game.players[1]
			actor.general_name = "里奥·普利威尔"
			var original = CardBase.create(sub)
			actor.determined_cards.append(original)
			if sub == CardData.CardSubType.NULLIFICATION:
				game._ai_response_override = func(view, kind, options):
					return sub if view.actor == 1 and kind == "nullification" and options.has(sub) else -1
				await game._ask_nullification_round("F02a原使用事实")
			else:
				game._sacrifice_actor_override = func(p, _target, _amount): return p == actor
				await game._deal_damage(game.players[0], game.players[2], 1, EffectChain.DamageType.PHYSICAL)
			suite.check(events.size() == 1 and events[0].card == original
				and events[0].kind == CardActionEvent.Kind.USE and events[0].turn_owner_seat == owner
				and actor.prep_tokens == (1 if owner == 1 else 0),
				"F02a：无懈/舍己不能触发替换原牌，但其本人回合真实手牌使用仍得预习")
			suite.check(actor.hand_size() == 0 and game.deck._discard.count(original) == 1,
				"F02a：响应锦囊实际原牌只支付入弃一次")
	game.ai_driver.chooser = old_chooser
	game.card_action_committed.disconnect(collect)
	suite.reset_players()
	tm.current_phase = old_phase
	tm.phase_changed.connect(callback)
