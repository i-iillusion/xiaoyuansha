extends RefCounted

func run(suite):
	var game: GameManager = suite.game
	var tm = game.turn_manager
	var phase = tm.current_phase
	var callback = game._on_phase_changed
	tm.phase_changed.disconnect(callback)
	for concrete in [false, true]:
		for sub in [CardData.CardSubType.LIANNU, CardData.CardSubType.RENWANG_DUN,
			CardData.CardSubType.MOUNT_PLUS, CardData.CardSubType.LIGHTNING,
			CardData.CardSubType.INDULGENCE, CardData.CardSubType.SUPPLY_SHORTAGE,
			CardData.CardSubType.BURNING_CAMP]:
			suite.reset_players()
			game.equipment_pool.clear()
			tm.current_phase = TurnManager.Phase.PLAY
			var actor: Player = game.players[0]
			actor.general_name = "里奥·普利威尔"
			var original: CardBase = CardBase.create(sub) if concrete else null
			if concrete: actor.determined_cards.append(original)
			else: actor.hand.append(null)
			var events: Array[CardActionEvent] = []
			var completed: Array[CardActionEvent] = []
			var commit = func(event):
				events.append(event)
				suite.check(actor.prep_tokens == 0 and not event.settlement_completed,
					"F02b-1c：装备/延时成立时未提前获标记")
			var finish = func(event):
				completed.append(event)
				suite.check(actor.prep_tokens == 1 and event.settlement_completed,
					"F02b-1c：同步结算完成时只获一个标记")
			game.card_action_committed.connect(commit)
			game.card_action_completed.connect(finish)
			if sub in [CardData.CardSubType.INDULGENCE, CardData.CardSubType.SUPPLY_SHORTAGE, CardData.CardSubType.BURNING_CAMP]:
				await game.execute_card_on_target(game.players[1], sub)
			else: await game.play_card(sub)
			game.card_action_committed.disconnect(commit)
			game.card_action_completed.disconnect(finish)
			suite.check(events.size() == 1 and completed == events and actor.hand_size() == 0
				and game._pending_card_actions.is_empty(), "F02b-1c：费用成立完成均一次且无遗留凭据")
			var card = events[0].card
			var category = CardData.get_equipment_slot_type(sub)
			var placed = actor.get_equipment_card("mount_1" if category == "mount" else category) if category != "" else null
			if sub == CardData.CardSubType.LIGHTNING: placed = actor.judgment_cards.back()
			elif sub in [CardData.CardSubType.INDULGENCE, CardData.CardSubType.SUPPLY_SHORTAGE, CardData.CardSubType.BURNING_CAMP]: placed = game.players[1].judgment_cards.back()
			suite.check(card == placed and (not concrete or card == original)
				and not game.deck._discard.has(card), "F02b-1c：原实体落位、不为未来判定延迟本次完成")
	# 最后一个名称的声明会同步清理他人暗置装备；此后才能完成本张。
	suite.reset_players()
	tm.current_phase = TurnManager.Phase.PLAY
	game.equipment_pool.clear()
	var actor: Player = game.players[0]
	actor.general_name = "里奥·普利威尔"
	actor.hand.append(null)
	var hidden = CardBase.create(CardData.CardSubType.HIDDEN_EQUIPMENT)
	hidden.hidden_category = "weapon"
	var holder: Player = game.players[1]
	holder.general_name = "安普提·斯丢皮得"
	holder.equip_hidden_card_to_slot("weapon", hidden)
	for sub in game.SAO_WEAPON_SUBS:
		if sub != CardData.CardSubType.LIANNU: game.equipment_pool.claim(sub)
	var commit = func(_event):
		suite.check(holder.get_hidden_equipment_card("weapon") == hidden and actor.prep_tokens == 0,
			"F02b-1c：成立事实保留在名称声明清理之前")
	var finish = func(_event):
		suite.check(holder.get_hidden_equipment_card("weapon") == null
			and game.deck._discard.count(hidden) == 1 and hidden.sub_type == CardData.CardSubType.HIDDEN_EQUIPMENT
			and actor.prep_tokens == 1, "F02b-1c：名称耗尽清理完成后获标记")
	game.card_action_committed.connect(commit)
	game.card_action_completed.connect(finish)
	# 抢先声明不发动，检验正常装备后名称耗尽的分支。
	game._sao_reveal_override = func(): return false
	await game.play_card(CardData.CardSubType.LIANNU)
	game.card_action_committed.disconnect(commit)
	game.card_action_completed.disconnect(finish)
	suite.reset_players()
	game.equipment_pool.clear()
	tm.current_phase = phase
	tm.phase_changed.connect(callback)
