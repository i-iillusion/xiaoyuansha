extends RefCounted

func _reset(suite):
	var game: GameManager = suite.game
	game.reset_game_over_state()
	game._hand_discard_override = func(snapshot, count, _mandatory): return snapshot.defaults(count)
	game._sacrifice_override = func(): return false
	game._sacrifice_actor_override = Callable()
	game._ai_response_override = func(_view, _kind, _options): return -1
	game._prep_replace_override = func(_leo, _user, _target, _sub, _options): return -1
	game._nullify_override = func(): return false
	game._rescue_choice_override = func(_rescuer, _dying, _options): return -1
	game._duel_respond_override = func(): return false
	game._yes_ah_override = Callable()
	game._clear_pending_determined_card()
	game.turn_manager.current_player_idx = 0
	game.turn_manager.play_actor_idx = -1
	game.turn_manager._reset_turn_counts()
	for p in game.players:
		p.reset_death_state()
		p.general_name = "稻草人"
		p.max_hp = 10
		p.hp = 10
		p.hand.clear()
		p.determined_cards.clear()
		p.equipment.clear()
		p.equipment_cards.clear()
		p.judgment_cards.clear()
		p.chained = false
		p.kneeling = false
		p.consume_wine_bonus()
		p.awoken = false
		p.awake_choice = 0
		p.prep_tokens = 0
		p.mount_plus = 0
		p.mount_minus = 0
		p.capture_game_start_state()

# 仅F02b-2a：原拆/顺→固定目标决斗。其余候选后续独立迁移。
func run(suite):
	var game: GameManager = suite.game
	var tm = game.turn_manager
	var phase = tm.current_phase
	var bank = game._bank_remaining
	var callback = game._on_phase_changed
	tm.phase_changed.disconnect(callback)
	for concrete in [false, true]:
		for sub in [CardData.CardSubType.SNATCH, CardData.CardSubType.DISMANTLE]:
			for mode in ["replace", "own", "decline", "illegal", "no_mark", "limit", "armor", "awake", "distance", "fresh_limit", "invalid", "restart"]:
				if mode == "distance" and sub == CardData.CardSubType.SNATCH: continue
				_reset(suite)
				game.deck._discard.clear()
				game.equipment_pool.clear()
				tm.current_phase = TurnManager.Phase.PLAY
				tm.current_player_idx = 1
				var user: Player = game.players[1]
				var target: Player = game.players[2]
				var leo: Player = user if mode == "own" else game.players[0]
				leo.general_name = "里奥·普利威尔"
				leo.prep_tokens = 0 if mode == "no_mark" else 1
				target.judgment_cards.clear()
				target.hand.append(CardBase.create(CardData.CardSubType.DODGE))
				var original: CardBase = CardBase.create(sub) if concrete else null
				if concrete: user.determined_cards.append(original)
				else: user.hand.append(null)
				if mode == "limit": tm.duel_count_this_turn = 2
				elif mode == "armor": target.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.ZHANQI))
				elif mode == "awake":
					target.general_name = "史蒂芬·彼特先斯"
					target.awoken = true
					target.awake_choice = 2
				elif mode == "distance":
					target.equip_card_to_slot("mount_1", CardBase.create(CardData.CardSubType.MOUNT_PLUS))
					target.equip_card_to_slot("mount_2", CardBase.create(CardData.CardSubType.MOUNT_PLUS))
				# 原入口合法性已在F02a验过；这里直调支付后的替换共同入口。
				var events: Array[CardActionEvent] = []
				var completed: Array[CardActionEvent] = []
				var commit = func(event): events.append(event)
				var finish = func(event): completed.append(event)
				game.card_action_committed.connect(commit)
				game.card_action_completed.connect(finish)
				var windows: Array[int] = [0]
				game._prep_replace_override = func(owner, actor, fixed, original_sub, candidates):
					windows[0] += 1
					suite.check(owner == leo and actor == user and fixed == target and original_sub == sub
						and candidates == [CardData.CardSubType.DUEL], "F02b-2a：候选保持原使用者/目标且无舍己")
					suite.check(events.size() == 1 and not events[0].settlement_completed and leo.prep_tokens == 1,
						"F02b-2a：原牌已成立，尚未提前累计或支付标记")
					if mode == "fresh_limit": tm.duel_count_this_turn = 2
					elif mode == "invalid":
						tm.current_phase = TurnManager.Phase.END
						tm.current_phase = TurnManager.Phase.PLAY
					elif mode == "restart": game.reset_game_over_state()
					if mode == "decline": return -1
					if mode == "illegal": return CardData.CardSubType.SACRIFICE
					return CardData.CardSubType.DUEL
				await game._play_steal_card(user, target, sub == CardData.CardSubType.SNATCH)
				game.card_action_committed.disconnect(commit)
				game.card_action_completed.disconnect(finish)
				var changed = mode in ["replace", "own"]
				var invalid = mode in ["invalid", "restart"]
				suite.check(events.size() == 1 and events[0].sub_type == sub and events[0].card.sub_type == sub
					and game.deck._discard.count(events[0].card) == 1 and (not concrete or events[0].card == original),
					"F02b-2a：任意/具体原实体只弃一次，替换不改持久牌名")
				suite.check(user.hand_size() == 0 or (sub == CardData.CardSubType.SNATCH and not changed and not invalid),
					"F02b-2a：不再次付手牌，顺手未改时仍可获取目标牌")
				suite.check(target.hp == (9 if changed else 10), "F02b-2a：只有合法换决斗伤害原目标")
				suite.check(tm.steal_count_this_turn == (0 if changed or invalid else 1), "F02b-2a：计数仅最终牌类别")
				var expected_duels = 1 if changed else (2 if mode in ["limit", "fresh_limit"] else 0)
				suite.check(tm.duel_count_this_turn == expected_duels, "F02b-2a：决斗新限额及计数")
				suite.check(leo.prep_tokens == (1 if mode == "own" else (0 if changed or mode == "no_mark" else 1)),
					"F02b-2a：只花已有标记，本人原手牌完成后才获得新标记")
				suite.check(completed.is_empty() if invalid else completed == events,
					"F02b-2a：失效不伪造完成，正常结果完成原事件")
				suite.check(game._pending_card_actions.is_empty(), "F02b-2a：本次凭据释放")
				if mode in ["limit", "armor", "awake", "distance", "no_mark"]:
					suite.check(windows[0] == 0, "F02b-2a：无已有标记或新牌非法不弹候选")
	# 真实新增窗口：基础读条/取消/关闭/重开及下一合法更换。
	for mode in ["confirm", "cancel", "timeout", "close", "restart"]:
		_reset(suite)
		tm.current_phase = TurnManager.Phase.PLAY
		tm.current_player_idx = 1
		var user: Player = game.players[1]
		var target: Player = game.players[2]
		var leo: Player = game.players[0]
		leo.general_name = "里奥·普利威尔"
		leo.prep_tokens = 1
		user.hand.append(null)
		target.judgment_cards.clear()
		target.hand.append(CardBase.create(CardData.CardSubType.DODGE))
		game._prep_replace_override = Callable()
		var drive = func():
			suite.check(game._choice_prompt_stack.size() == 1 and game._countdown_active
				and game._step_remaining > 29.0 and leo.prep_tokens == 1,
				"F02b-2a：真实窗口基础读条、已有标记未付")
			var pending = game._choice_prompt_stack.back()
			if mode == "restart": game.reset_game_over_state()
			elif mode == "close": pending.overlay.queue_free()
			elif mode == "timeout":
				game._step_remaining = 0.001
				game._bank_remaining = 0.0
				game._process(0.01)
			else: pending.answer.submit(0 if mode == "confirm" else -1)
		drive.call_deferred()
		await game._play_steal_card(user, target, false)
		var invalid = mode in ["close", "restart"]
		suite.check(leo.prep_tokens == (0 if mode == "confirm" else 1) and target.hp == (9 if mode == "confirm" else 10),
			"F02b-2a：确认换牌，取消/超时保标记，失效无伤害")
		suite.check(target.hand_size() == (0 if mode in ["cancel", "timeout"] else 1),
			"F02b-2a：取消/超时继续原拆，关闭/重开不伪装放弃")
		suite.check(user.hand_size() == 0 and game._pending_card_actions.is_empty(),
			"F02b-2a：旧窗口失效保留原费用并释放凭据")
		await suite.process_frame
		suite.check(game._choice_prompt_stack.is_empty(), "F02b-2a：旧弹窗完全清理")
		if invalid:
			user.hand.append(null)
			game._prep_replace_override = func(_owner, _actor, _fixed, _sub, _options): return CardData.CardSubType.DUEL
			await game._play_steal_card(user, target, false)
			suite.check(target.hp == 9 and leo.prep_tokens == 0, "F02b-2a：旧失效后下一合法更换正常")
	# 合法虚拟原牌仍可被替换，不创造第二张实体或第二次技能费用。
	_reset(suite)
	tm.current_phase = TurnManager.Phase.PLAY
	var user: Player = game.players[0]
	var target: Player = game.players[1]
	var leo: Player = game.players[2]
	user.general_name = "安普提·斯丢皮得"
	user.hand.append(null)
	leo.general_name = "里奥·普利威尔"
	leo.prep_tokens = 1
	target.judgment_cards.clear()
	target.hand.append(CardBase.create(CardData.CardSubType.DODGE))
	game._zone_pick_override = func(): return "hand"
	game._yes_ah_override = func(): return "skill"
	game._prep_replace_override = func(_owner, _actor, _fixed, _sub, _options): return CardData.CardSubType.DUEL
	var events: Array[CardActionEvent] = []
	var collect = func(event): events.append(event)
	game.card_action_committed.connect(collect)
	suite.check(await game._choose_yes_ah_for_play(user, "过河拆桥"), "F02b-2a：虚拟原牌经过真实技能确认入口")
	await game._play_steal_card(user, target, false)
	game.card_action_committed.disconnect(collect)
	suite.check(user.hp == 9 and user.hand_size() == 1 and target.hp == 9 and leo.prep_tokens == 0,
		"F02b-2a：虚拟原锦囊仅一次技能费用、合法换牌伤害与标记费用")
	suite.check(events.size() == 1 and events[0].is_virtual and events[0].settlement_completed
		and not events[0].from_hand and not game.deck._discard.has(events[0].card),
		"F02b-2a：虚拟替换保留原虚拟事实，不生成物理弃牌")
	game._zone_pick_override = Callable()
	game.equipment_pool.clear()
	_reset(suite)
	game._bank_remaining = bank
	tm.current_phase = phase
	tm.phase_changed.connect(callback)
