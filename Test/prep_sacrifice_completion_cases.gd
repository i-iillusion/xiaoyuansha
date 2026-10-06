extends RefCounted

func run(suite):
	var game: GameManager = suite.game
	var tm = game.turn_manager
	var phase = tm.current_phase
	var callback = game._on_phase_changed
	tm.phase_changed.disconnect(callback)
	for owner in [0, 1]:
		for concrete in [false, true]:
			for nested in [false, true]:
				suite.reset_players()
				tm.current_player_idx = owner
				tm.current_phase = TurnManager.Phase.PLAY
				var actor: Player = game.players[1]
				actor.general_name = "里奥·普利威尔"
				var original: CardBase = CardBase.create(CardData.CardSubType.SACRIFICE) if concrete else null
				if concrete: actor.determined_cards.append(original)
				else: actor.hand.append(null)
				var robe = CardBase.create(CardData.CardSubType.CALAMITY_ROBE)
				var final_target: Player = game.players[3] if nested else actor
				final_target.equip_card_to_slot("armor", robe)
				if nested: game.players[3].hand.append(null)
				var actions: Array[CardActionEvent] = []
				var completed: Array[CardActionEvent] = []
				var commit = func(event):
					actions.append(event)
					suite.check(actor.prep_tokens == 0 and not event.settlement_completed,
						"F02b-1e-b：舍己支付成立、嵌套转移期间无新标记")
				var finish = func(event):
					completed.append(event)
					suite.check(final_target.hp == 9 and final_target.get_armor() == -1
						and game.players[4].get_equipment_card("armor") == robe,
						"F02b-1e-b：舍己完成通知在实际转移伤害及装备后效之后")
				game.card_action_committed.connect(commit)
				game.card_action_completed.connect(finish)
				game._sacrifice_actor_override = func(p, target, _amount):
					suite.check(actor.prep_tokens == 0, "F02b-1e-b：转移承受者的新伤害窗口仍无标记")
					return (p == actor and target == game.players[2]) \
						or (nested and p == game.players[3] and target == actor)
				game._calamity_robe_target_override = func():
					suite.check(actor.prep_tokens == 0 and final_target.hp == 9,
						"F02b-1e-b：灾厄袍选择时已受伤但舍己仍未完成")
					return game.players[4]
				var result = await game._deal_damage_result(game.players[0], game.players[2], 1, EffectChain.DamageType.PHYSICAL)
				game.card_action_committed.disconnect(commit)
				game.card_action_completed.disconnect(finish)
				suite.check(not result.invalidated and result.target == final_target
					and actions.size() == (2 if nested else 1) and completed.size() == actions.size(),
					"F02b-1e-b：单次/嵌套舍己完成，原目标不受伤、最终承受者正确")
				suite.check(game.players[2].hp == 10 and actor.hp == (10 if nested else 9)
					and actor.prep_tokens == (1 if owner == 1 else 0),
					"F02b-1e-b：真实伤害一次，手牌仅本人回合获一个标记")
				for event in actions:
					suite.check(game.deck._discard.count(event.card) == 1
						and event.card.sub_type == CardData.CardSubType.SACRIFICE,
						"F02b-1e-b：每张舍己原实体入弃一次且名称不变")
				suite.check(not concrete or actions[0].card == original, "F02b-1e-b：具体舍己保原实例")
				game._complete_card_actions(actions)
				suite.check(actor.prep_tokens == (1 if owner == 1 else 0)
					and game._pending_card_actions.is_empty(), "F02b-1e-b：重复完成幂等、无遗留凭据")
				game._calamity_robe_target_override = Callable()
	# 真实灾厄袍选择窗口：原舍己支付和伤害保留，但关闭/重开不计完成。
	for concrete in [false, true]:
		for restart in [false, true]:
			suite.reset_players()
			tm.current_phase = TurnManager.Phase.PLAY
			var actor: Player = game.players[0]
			actor.general_name = "里奥·普利威尔"
			actor.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.CALAMITY_ROBE))
			if concrete: actor.determined_cards.append(CardBase.create(CardData.CardSubType.SACRIFICE))
			else: actor.hand.append(null)
			var actions: Array[CardActionEvent] = []
			var completed: Array[CardActionEvent] = []
			var drive = func():
				suite.check(actor.hp == 9 and actor.prep_tokens == 0,
					"F02b-1e-b：真实伤害后选择前已付款/受伤但没有标记")
				if restart: game.reset_game_over_state()
				else: game._choice_prompt_stack.back().overlay.queue_free()
			var commit = func(event):
				actions.append(event)
				drive.call_deferred()
			var finish = func(event): completed.append(event)
			game.card_action_committed.connect(commit)
			game.card_action_completed.connect(finish)
			game._sacrifice_actor_override = func(p, target, _amount): return p == actor and target == game.players[1]
			game._calamity_robe_target_override = Callable()
			var result = await game._deal_damage_result(game.players[2], game.players[1], 1, EffectChain.DamageType.PHYSICAL)
			game.card_action_committed.disconnect(commit)
			game.card_action_completed.disconnect(finish)
			suite.check(result.invalidated and actor.hp == 9 and actor.hand_size() == 0
				and actions.size() == 1 and game.deck._discard.count(actions[0].card) == 1,
				"F02b-1e-b：真实失效保留已提交的原牌费用和伤害")
			suite.check(completed.is_empty() and actor.prep_tokens == 0 and game._pending_card_actions.is_empty(),
				"F02b-1e-b：真实后效失效不完成旧舍己，释放凭据")
			await suite.process_frame
			suite.check(game._choice_prompt_stack.is_empty(), "F02b-1e-b：真实旧窗口清理")
			actor.hand.append(null)
			game._calamity_robe_target_override = func(): return "cancel"
			await game._deal_damage_result(game.players[2], game.players[1], 1, EffectChain.DamageType.PHYSICAL)
			suite.check(actor.hp == 8 and actor.prep_tokens == 1 and game._pending_card_actions.is_empty(),
				"F02b-1e-b：下一次合法舍己完成，主动不转袍也正常完成")
			game._calamity_robe_target_override = Callable()
	# 安普提虚拟舍己：完整转移仍发布完成，不造物理弃牌或预习。
	suite.reset_players()
	tm.current_phase = TurnManager.Phase.PLAY
	var actor: Player = game.players[0]
	actor.general_name = "安普提·斯丢皮得"
	actor.hand.append(null)
	var actions: Array[CardActionEvent] = []
	var completed: Array[CardActionEvent] = []
	var commit = func(event): actions.append(event)
	var finish = func(event): completed.append(event)
	game.card_action_committed.connect(commit)
	game.card_action_completed.connect(finish)
	game._yes_ah_override = func(): return "skill"
	game._sacrifice_actor_override = func(p, target, _amount): return p == actor and target == game.players[1]
	await game._deal_damage_result(game.players[2], game.players[1], 1, EffectChain.DamageType.PHYSICAL)
	game.card_action_committed.disconnect(commit)
	game.card_action_completed.disconnect(finish)
	suite.check(actions.size() == 1 and completed == actions and actions[0].is_virtual
		and not actions[0].from_hand and actor.hp == 8 and actor.hand_size() == 1
		and not game.deck._discard.has(actions[0].card) and actor.prep_tokens == 0,
		"F02b-1e-b：合法虚拟舍己费用和伤害分别扣，实体/资格不伪造")
	# 神速合法虚拟杀：完成事实在伤害后；失效或重开不发布完成。
	for mode in ["hit", "invalid", "restart"]:
		suite.reset_players()
		tm.current_phase = TurnManager.Phase.PLAY
		actor = game.players[1]
		actor.general_name = "比尔·盖伊"
		game.players[0].hand.append(null) # 真实可响应，不能以空手跳过出闪测试窗口。
		actions.clear()
		completed.clear()
		game.card_action_committed.connect(commit)
		game.card_action_completed.connect(finish)
		game._dodge_override = func():
			suite.check(completed.is_empty(), "F02b-1e-b：神速响应阶段尚无完成事实")
			if mode == "restart": game.reset_game_over_state()
			return GameManager.CHOICE_INVALID if mode == "invalid" else false
		await game._execute_shensu_strike(actor, game.players[0])
		game.card_action_committed.disconnect(commit)
		game.card_action_completed.disconnect(finish)
		suite.check(actions.size() == 1 and actions[0].is_virtual and not actions[0].from_hand
			and completed.size() == (1 if mode == "hit" else 0)
			and not game.deck._discard.has(actions[0].card) and game._pending_card_actions.is_empty(),
			"F02b-1e-b：神速只正常完成一次，失效释放，虚拟不入弃")
	suite.reset_players()
	tm.current_phase = phase
	tm.phase_changed.connect(callback)
