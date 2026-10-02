# DEV-B04b / E-06：持久状态跟随原牌，手牌持有者不获得佩戴效果。
extends RefCounted

var suite
var game: GameManager

func check(ok: bool, label: String):
	suite.check(ok, "B04b：" + label)

func run(host):
	suite = host
	game = host.game
	var previous_phase = game.turn_manager.current_phase
	for sub in [CardData.CardSubType.SOUL_BLADE, CardData.CardSubType.SAGE_PROTECTION]:
		for concrete in [false, true]:
			await check_transfer(sub, concrete)
	await check_hidden_state()
	await check_waiting_state()
	game._equip_pick_override = Callable()
	game._rps_override = Callable()
	game._lanzhonghou_zone_override = Callable()
	game.equipment_pool.clear()
	game.deck._discard.clear()
	suite.reset_players()
	for p in game.players:
		p.soul_blade_activated = false
		p.soul_blade_track_target = null
		p.soul_blade_track_count = 0
		p.sage_tokens = 0
		p.sage_activated = false
	game.turn_manager.current_phase = previous_phase

func check_transfer(sub: CardData.CardSubType, concrete: bool):
	suite.reset_players()
	game.equipment_pool.clear()
	game.deck._discard.clear()
	game._clear_pending_determined_card()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	var a: Player = game.players[1]
	var b: Player = game.players[2]
	var actor: Player = game.players[0]
	var slot = "weapon" if sub == CardData.CardSubType.SOUL_BLADE else "armor"
	for p in game.players:
		p.soul_blade_activated = false
		p.sage_tokens = 0
		p.sage_activated = false
	var supplied: CardBase = CardBase.create(sub) if concrete else null
	a.hand.append(supplied)
	game.turn_manager.current_player_idx = a.seat_index
	await game.play_card(sub)
	var original: CardBase = a.get_equipment_card(slot)
	check(original != null and (not concrete or original == supplied), "任意/具体来源首次出牌保留原牌")
	if sub == CardData.CardSubType.SOUL_BLADE:
		game._update_soul_blade_count(a, b, 3)
		check(a.soul_blade_activated, "真实累计入口激活摄魂刀")
	else:
		game._rps_override = func(p): return 0 if p == a else 2
		for i in 2:
			a.hand.append(null)
			check(await game._sage_ping(a, b), "真实贤者拼点取得标记")
		check(a.sage_tokens == 2 and not a.sage_activated, "贤者两标记尚未激活")
	game._equip_pick_override = func(): return "cancel"
	await game._steal_equip(actor, a, true, "顺手牵羊")
	check(a.get_equipment_card(slot) == original and has_state(a, sub, false), "取消顺走保留原牌状态")
	# 选择期间原牌已被另一入口移入手牌，旧答复不得误动牌；这是防御性状态注入。
	game._equip_pick_override = func():
		a.determined_cards.append(a.remove_equipment(slot))
		return slot
	await game._steal_equip(actor, a, true, "顺手牵羊")
	check(a.determined_cards.has(original) and b.determined_cards.is_empty() and no_state(a),
		"过期槽位答复不偷已离区原牌，旧持有者无效果")
	await game.play_card(sub)
	check(a.get_equipment_card(slot) == original and has_state(a, sub, false), "过期后下一合法复装恢复原牌状态")
	game._equip_pick_override = func(): return slot
	await game._steal_equip(b, a, true, "顺手牵羊")
	check(b.determined_cards.has(original) and no_state(a) and no_state(b), "顺走入手只移动原牌，不给双方佩戴状态")
	check(original.soul_blade_activated if sub == CardData.CardSubType.SOUL_BLADE else original.sage_tokens == 2,
		"持久状态保存在手牌原对象")
	if sub == CardData.CardSubType.SAGE_PROTECTION:
		b.hand.append(null)
		check(not await game._sage_ping(b, a) and b.hand_size() == 2, "仅手持贤者不能拼点或付费")
		b.hand.clear()
	else:
		var choices: Array = []
		game._rps_override = func(p):
			choices.append(p)
			return 0
		await game._try_soul_blade(b, a)
		check(choices.is_empty(), "仅手持摄魂刀不能发动拼点")
	game.turn_manager.current_player_idx = b.seat_index
	await game.play_card(sub)
	check(b.get_equipment_card(slot) == original and has_state(b, sub, false) and no_state(a), "B再装备继承状态且A不残留")
	if sub == CardData.CardSubType.SAGE_PROTECTION:
		game._rps_override = func(p): return 0 if p == b else 2
		b.hand.append(null)
		check(await game._sage_ping(b, a) and b.sage_tokens == 0 and b.sage_activated,
			"第三标记仍按规则消费并激活")
	await game._steal_equip(a, b, true, "顺手牵羊")
	check(a.determined_cards.has(original) and no_state(a) and no_state(b), "A取回入手仍无佩戴状态")
	game.turn_manager.current_player_idx = a.seat_index
	await game.play_card(sub)
	check(a.get_equipment_card(slot) == original and has_state(a, sub, true), "A取回复装保留激活及已消费标记")
	# 两侧占槽的真实没用入口必须走同一持久状态存取，不依赖技能手工搬字段。
	var other = CardBase.create(CardData.CardSubType.LIANNU if slot == "weapon" else CardData.CardSubType.RENWANG_DUN)
	b.equip_card_to_slot(slot, other)
	actor.general_name = "麦克斯·欧尼斯特"
	actor.hand.append(null)
	game.turn_manager.current_player_idx = 0
	game._lanzhonghou_used = false
	var zones: Array = [slot, "done"]
	game._lanzhonghou_zone_override = func(): return zones.pop_front()
	await game._run_lanzhonghou(a, b)
	check(b.get_equipment_card(slot) == original and a.get_equipment_card(slot) == other
		and has_state(b, sub, true) and no_state(a), "双方占槽交换状态跟原牌，不跟人")
	game._lanzhonghou_zone_override = Callable()
	await game._steal_equip(a, b, false, "过河拆桥")
	check(no_state(b) and game.deck._discard.count(original) == 1, "拆除清佩戴状态且原牌仅弃一次")

func no_state(p: Player) -> bool:
	return not p.soul_blade_activated and p.sage_tokens == 0 and not p.sage_activated

func has_state(p: Player, sub: CardData.CardSubType, activated_sage: bool) -> bool:
	if sub == CardData.CardSubType.SOUL_BLADE:
		return p.soul_blade_activated
	return p.sage_activated and p.sage_tokens == 0 if activated_sage else not p.sage_activated and p.sage_tokens == 2

# 暗置时不得将持久状态覆盖成佩戴者的零值；三个声明入口仍恢复同一原牌。
func check_hidden_state():
	for sub in [CardData.CardSubType.SOUL_BLADE, CardData.CardSubType.SAGE_PROTECTION]:
		for path in ["active", "snatch", "exchange"]:
			suite.reset_players()
			game.equipment_pool.clear()
			game.deck._discard.clear()
			game.turn_manager.current_phase = TurnManager.Phase.PLAY
			var owner: Player = game.players[1]
			var sao: Player = game.players[0]
			var recipient: Player = game.players[2]
			var slot = "weapon" if sub == CardData.CardSubType.SOUL_BLADE else "armor"
			owner.hand.append(null)
			game.turn_manager.current_player_idx = 1
			await game.play_card(sub)
			var original = owner.get_equipment_card(slot)
			owner.soul_blade_activated = sub == CardData.CardSubType.SOUL_BLADE
			owner.sage_tokens = 2 if sub == CardData.CardSubType.SAGE_PROTECTION else 0
			owner.sage_activated = false
			game._equip_pick_override = func(): return slot
			await game._steal_equip(sao, owner, true, "顺手牵羊")
			sao.general_name = "安普提·斯丢皮得"
			game.turn_manager.current_player_idx = 0
			game._sao_type_override = func(): return slot
			await game._do_sao_hide(sao, false)
			check(sao.get_hidden_equipment_card(slot) == original and no_state(sao), "暗置保存原牌且不激活佩戴效果：" + path)
			if path == "active":
				game._sao_reveal_sub_override = func(): return sub
				await game._do_sao_reveal(sao)
				check(has_state(sao, sub, false), "主动明置恢复原牌状态")
			elif path == "snatch":
				game._sao_transfer_declare_override = func(): return sub
				await game._steal_equip(recipient, sao, true, "顺手牵羊")
				check(no_state(recipient), "暗置顺走声明后手持者仍无效果")
				game.turn_manager.current_player_idx = 2
				await game.play_card(sub)
				check(recipient.get_equipment_card(slot) == original and has_state(recipient, sub, false), "暗置顺走声明复装恢复状态")
			else:
				check(game._swap_equip_slot(sao, slot, recipient, slot), "暗置原牌交换到空槽")
				game._sao_transfer_declare_override = func(): return sub
				await game._declare_exchanged_hidden_equipment(sao, recipient, slot, original)
				check(recipient.get_equipment_card(slot) == original and has_state(recipient, sub, false), "交换离区声明恢复状态")
			for p in game.players:
				p.soul_blade_activated = false
				p.sage_tokens = 0
				p.sage_activated = false
	game._sao_type_override = Callable()
	game._sao_reveal_sub_override = Callable()
	game._sao_transfer_declare_override = Callable()

# 仅以回调注入模拟等待期过期，不将换装注入当作合法规则时机。
func check_waiting_state():
	for sub in [CardData.CardSubType.SOUL_BLADE, CardData.CardSubType.SAGE_PROTECTION]:
		for mode in ["same_name", "phase", "dead", "cancel", "success"]:
			suite.reset_players()
			game.deck._discard.clear()
			game.turn_manager.current_phase = TurnManager.Phase.PLAY
			var actor: Player = game.players[0]
			var target: Player = game.players[1]
			var slot = "weapon" if sub == CardData.CardSubType.SOUL_BLADE else "armor"
			var original = CardBase.create(sub)
			actor.equip_card_to_slot(slot, original)
			actor.soul_blade_activated = sub == CardData.CardSubType.SOUL_BLADE
			actor.sage_tokens = 2 if sub == CardData.CardSubType.SAGE_PROTECTION else 0
			actor.sage_activated = false
			var fee = CardBase.create(CardData.CardSubType.PEACH)
			actor.hand.append(fee)
			var calls: Array = []
			game._hand_discard_override = func(snapshot, count, _mandatory): return [] if mode == "cancel" else snapshot.defaults(count)
			game._soul_blade_activate_override = func(): return mode != "cancel"
			game._rps_override = func(p):
				calls.append(p)
				if calls.size() == 1:
					if mode == "same_name":
						actor.determined_cards.append(actor.remove_equipment(slot))
						actor.equip_card_to_slot(slot, CardBase.create(sub))
					elif mode == "phase":
						game.turn_manager.current_phase = TurnManager.Phase.END
						game.turn_manager.current_phase = TurnManager.Phase.PLAY
					elif mode == "dead":
						target.mark_dead()
				return 0 if p == actor else 2
			if sub == CardData.CardSubType.SAGE_PROTECTION:
				var result = await game._sage_ping(actor, target)
				check(result == (mode == "success"), "贤者等待结果：" + mode)
				check(actor.sage_tokens == 0 if mode == "same_name" or mode == "success" else actor.sage_tokens == 2, "旧拼点不写入后来装备：" + mode)
				check(game.deck._discard.count(fee) == 0 if mode == "cancel" else game.deck._discard.count(fee) == 1, "已支付费用不回滚：" + mode)
			else:
				await game._try_soul_blade(actor, target)
				check(target.facedown == (mode == "success"), "摄魂刀过期不继续翻面：" + mode)
			var expected_calls = 1
			if mode == "cancel":
				expected_calls = 0
			elif mode == "success":
				expected_calls = 2 if sub == CardData.CardSubType.SAGE_PROTECTION else 4
			check(calls.size() == expected_calls, "过期后不继续询问下一拳：" + mode)
	game._soul_blade_activate_override = Callable()
