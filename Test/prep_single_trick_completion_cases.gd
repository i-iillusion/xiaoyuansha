extends RefCounted

func run(suite):
	var game: GameManager = suite.game
	var tm = game.turn_manager
	var phase = tm.current_phase
	var callback = game._on_phase_changed
	tm.phase_changed.disconnect(callback)
	for concrete in [false, true]:
		for sub in [CardData.CardSubType.DUEL, CardData.CardSubType.DISMANTLE,
			CardData.CardSubType.SNATCH, CardData.CardSubType.IRON_CHAIN]:
			for mode in ["normal", "invalid", "restart", "nullified"]:
				suite.reset_players()
				tm.current_phase = TurnManager.Phase.PLAY
				var actor: Player = game.players[0]
				actor.general_name = "里奥·普利威尔"
				var original: CardBase = CardBase.create(sub) if concrete else null
				if concrete: actor.determined_cards.append(original)
				else: actor.hand.append(null)
				game.players[1].hand.append(CardBase.create(CardData.CardSubType.DODGE))
				var events: Array[CardActionEvent] = []
				var completed: Array[CardActionEvent] = []
				var commit = func(event):
					if event.actor_seat != 0: return
					events.append(event)
					suite.check(actor.prep_tokens == 0 and not event.settlement_completed,
						"F02b-1d-b：单体/铁索成立时不提前计数")
				var finish = func(event):
					if event.actor_seat != 0: return
					completed.append(event)
					suite.check(actor.prep_tokens == 1 and event.settlement_completed,
						"F02b-1d-b：单体/铁索正常结束唯一完成")
				game.card_action_committed.connect(commit)
				game.card_action_completed.connect(finish)
				var windows: Array[int] = [0]
				game._nullify_override = func():
					windows[0] += 1
					suite.check(actor.prep_tokens == 0, "F02b-1d-b：生效前/铁索逐目标无懈期间仍0")
					if windows[0] == 1:
						if mode == "restart": game.reset_game_over_state()
						elif mode == "invalid":
							tm.current_phase = TurnManager.Phase.END
							tm.current_phase = TurnManager.Phase.PLAY
					return false
				if mode == "nullified":
					game.players[3].determined_cards.append(CardBase.create(CardData.CardSubType.NULLIFICATION))
					game._ai_response_override = func(_view, kind, options):
						return CardData.CardSubType.NULLIFICATION if kind == "nullification" and options.has(CardData.CardSubType.NULLIFICATION) else -1
				game._zone_pick_override = func(): return "hand"
				if sub == CardData.CardSubType.IRON_CHAIN:
					var targets: Array[Player] = [game.players[1], game.players[2]]
					await game._execute_iron_chain(targets)
				else: await game.execute_card_on_target(game.players[1], sub)
				game.card_action_committed.disconnect(commit)
				game.card_action_completed.disconnect(finish)
				var normal = mode in ["normal", "nullified"]
				suite.check(events.size() == 1 and completed.size() == (1 if normal else 0)
					and actor.prep_tokens == (1 if normal else 0) and game._pending_card_actions.is_empty(),
					"F02b-1d-b：正常抵消也完成，技术失效无完成无遗留")
				suite.check(game.deck._discard.count(events[0].card) == 1
					and (not concrete or events[0].card == original), "F02b-1d-b：单体原牌费用与实体一次")
	# 装备选择：主动取消属正常结束，空串技术失效不是同一结果。
	for concrete in [false, true]:
		for choice in ["cancel", "", "weapon"]:
			suite.reset_players()
			tm.current_phase = TurnManager.Phase.PLAY
			var actor: Player = game.players[0]
			actor.general_name = "里奥·普利威尔"
			if concrete: actor.determined_cards.append(CardBase.create(CardData.CardSubType.DISMANTLE))
			else: actor.hand.append(null)
			var weapon = CardBase.create(CardData.CardSubType.LIANNU)
			game.players[1].equip_card_to_slot("weapon", weapon)
			game._zone_pick_override = func(): return "equip"
			game._equip_pick_override = func():
				suite.check(actor.prep_tokens == 0, "F02b-1d-b：选装备窗口无本张标记")
				return choice
			await game.execute_card_on_target(game.players[1], CardData.CardSubType.DISMANTLE)
			suite.check(actor.prep_tokens == (0 if choice == "" else 1) and game._pending_card_actions.is_empty(),
				"F02b-1d-b：选槽主动取消正常完成，技术失效不完成")
			suite.check(game.deck._discard.has(weapon) == (choice == "weapon"), "F02b-1d-b：仅有效槽位移动装备")
	# 真实窗口关闭/重开：分别在选槽、决斗响应、原持有者声明处等待。
	for concrete in [false, true]:
		for restart in [false, true]:
			for kind in ["equip", "duel", "declare"]:
				suite.reset_players()
				game.equipment_pool.clear()
				tm.current_phase = TurnManager.Phase.PLAY
				tm.current_player_idx = 0 if kind == "equip" else 1
				var actor: Player = game.players[tm.current_player_idx]
				var target: Player = game.players[1 if kind == "equip" else 0]
				# 此例只提供装备区/响应手牌，排除前例保留的延时牌区。
				target.judgment_cards.clear()
				actor.general_name = "里奥·普利威尔"
				var sub = CardData.CardSubType.DISMANTLE if kind == "equip" else (
					CardData.CardSubType.DUEL if kind == "duel" else CardData.CardSubType.SNATCH)
				if concrete: actor.determined_cards.append(CardBase.create(sub))
				else: actor.hand.append(null)
				var equipment: CardBase = null
				if kind == "equip":
					equipment = CardBase.create(CardData.CardSubType.LIANNU)
					target.equip_card_to_slot("weapon", equipment)
				elif kind == "declare":
					target.general_name = "安普提·斯丢皮得"
					equipment = CardBase.create(CardData.CardSubType.HIDDEN_EQUIPMENT)
					equipment.hidden_category = "weapon"
					target.equip_hidden_card_to_slot("weapon", equipment)
				else: target.hand.append(null)
				game._zone_pick_override = func(): return "equip"
				game._equip_pick_override = Callable()
				game._duel_respond_override = Callable()
				game._sao_transfer_declare_override = Callable()
				var drive = func():
					suite.check(actor.prep_tokens == 0, "F02b-1d-b：真实选槽/决斗/声明窗口无新标记")
					if restart: game.reset_game_over_state()
					else: game._choice_prompt_stack.back().overlay.queue_free()
				drive.call_deferred()
				await game.execute_card_on_target(target, sub)
				suite.check(actor.prep_tokens == 0 and game._pending_card_actions.is_empty(),
					"F02b-1d-b：真实窗口失效传到外层、不完成原锦囊")
				if kind == "declare":
					suite.check(actor.determined_cards.has(equipment)
						and equipment.sub_type == CardData.CardSubType.HIDDEN_EQUIPMENT,
						"F02b-1d-b：已顺走实体不回滚、技术失效不默认明置")
				elif kind == "equip":
					suite.check(target.get_equipment_card("weapon") == equipment, "F02b-1d-b：选槽失效不移牌")
				else: suite.check(target.hp == 10, "F02b-1d-b：决斗旧响应失效不造成伤害")
				await suite.process_frame
				suite.check(game._choice_prompt_stack.is_empty(), "F02b-1d-b：真实旧窗口清理完毕")
	game.equipment_pool.clear()
	game._zone_pick_override = Callable()
	game._equip_pick_override = Callable()
	suite.reset_players()
	tm.current_phase = phase
	tm.phase_changed.connect(callback)
