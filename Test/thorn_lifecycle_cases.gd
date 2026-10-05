extends RefCounted

var suite
var game: GameManager

func prepare():
	suite.reset_players()
	game.deck._discard.clear()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	for p in game.players: p.judgment_cards.clear()
	game.players[0].equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.THORN_ARMOR))
	game._rps_override = Callable()
	game._gou_lian_slot_override = Callable()
	game._bloodthirsty_override = Callable()

func run(host):
	suite = host
	game = host.game
	prepare()
	var calls: Array = []
	game._rps_override = func(p):
		calls.append(p)
		return GameManager.RPS_SCISSORS if p.seat_index == 1 and calls.size() > 2 else GameManager.RPS_ROCK
	var reply = await game._deal_damage_result(game.players[1], game.players[0], 2, EffectChain.DamageType.PHYSICAL)
	suite.check(not reply.invalidated and game.players[0].hp == 8 and game.players[1].hp == 8 and calls.size() == 6, "E03e-22b：荆棘平局续猜，两点各获胜反伤，原伤害仅提交一次")
	suite.check(game.players[0].hand.is_empty() and game.players[1].hand.is_empty(), "E03e-22b：默认拼点不支付手牌")
	for mode in ["close", "reset", "armor", "phase", "end"]:
		prepare()
		game.players[0].general_name = "凯文·罗本"
		var action = func():
			var pending = game._choice_prompt_stack.back()
			match mode:
				"close": pending.overlay.queue_free()
				"reset": game.reset_game_over_state()
				"armor": game.players[0].remove_equipment("armor")
				"phase": game.turn_manager.current_phase = TurnManager.Phase.END
				"end": game._game_over = true
		action.call_deferred()
		reply = await game._deal_damage_result(game.players[1], game.players[0], 2, EffectChain.DamageType.PHYSICAL)
		suite.check(reply.invalidated and game.players[0].hp == 8 and game.players[1].hp == 10 and game.players[0].hand.is_empty(), "E03e-22b：荆棘实际出拳失效停止反伤及凯文后效，不回滚已受两点：" + mode)
		await suite.process_frame
	prepare()
	calls.clear()
	game._rps_override = func(p):
		calls.append(p)
		if calls.size() == 3:
			game.players[0].remove_equipment("armor")
			game.players[0].equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.THORN_ARMOR))
		return GameManager.RPS_ROCK if p.seat_index == 0 else GameManager.RPS_SCISSORS
	reply = await game._deal_damage_result(game.players[1], game.players[0], 2, EffectChain.DamageType.PHYSICAL)
	suite.check(reply.invalidated and game.players[0].hp == 8 and game.players[1].hp == 9 and calls.size() == 3, "E03e-22b：同名新防具不接管旧逐点窗口，保留第一点反伤")
	for invalid in [false, true]:
		prepare()
		game.players[1].hp = 1
		game.players[1].identity = "忠臣"
		calls.clear()
		game._rps_override = func(p):
			calls.append(p)
			return GameManager.RPS_ROCK if p.seat_index == 0 else GameManager.RPS_SCISSORS
		if invalid:
			game.players[0].hand.assign([null])
			game._rescue_choice_override = Callable()
			var close = func(): game._choice_prompt_stack.back().overlay.queue_free()
			close.call_deferred()
		reply = await game._deal_damage_result(game.players[1], game.players[0], 2, EffectChain.DamageType.PHYSICAL)
		suite.check(reply.invalidated == invalid and game.players[0].hp == 8 and game.players[1].hp == 0 and calls.size() == 2 and (game.players[1].is_dying() if invalid else game.players[1].is_dead()), "E03e-22b：反伤濒死失效回传原链，正常最终死亡停止死人拼点而非技术失效")
		await suite.process_frame
	prepare()
	game.players[0].remove_equipment("armor")
	game.players[0].equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.BLOODTHIRSTY_BLADE))
	game.players[1].general_name = "凯文·罗本"
	game._bloodthirsty_override = func(): return GameManager.CHOICE_INVALID
	calls.clear()
	game._rps_override = func(p): calls.append(p); return GameManager.RPS_ROCK
	reply = await game._deal_damage_result(game.players[0], game.players[1], 1, EffectChain.DamageType.PHYSICAL)
	suite.check(reply.invalidated and game.players[1].hp == 9 and calls.is_empty() and game.players[1].hand.is_empty(), "E03e-22b：噬血失效停止受伤后凯文窗口，原伤害保留")
	prepare()
	game.players[0].remove_equipment("armor")
	game.players[0].equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.GOU_LIAN_CLAW))
	game.players[1].equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.THORN_ARMOR))
	var mount = CardBase.create(CardData.CardSubType.MOUNT_MINUS)
	game.players[1].equip_card_to_slot("mount_1", mount)
	calls.clear()
	game._rps_override = func(p): calls.append(p); return GameManager.RPS_ROCK
	var close_claw = func(): game._choice_prompt_stack.back().overlay.queue_free()
	close_claw.call_deferred()
	reply = await game._deal_damage_result(game.players[0], game.players[1], 1, EffectChain.DamageType.PHYSICAL)
	suite.check(reply.invalidated and game.players[1].hp == 9 and game.players[1].get_equipment_card("mount_1") == mount and calls.is_empty(), "E03e-22b：勾镰关闭显式失效，不转移原马、不继续荆棘")
	await suite.process_frame
	for mode in ["decline", "invalid", "mount_invalid", "reset"]:
		prepare()
		game.players[0].remove_equipment("armor")
		game.players[0].equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.GUANSHI_AXE))
		game.players[0].equip_card_to_slot("mount_1", CardBase.create(CardData.CardSubType.MOUNT_MINUS))
		game._dodge_override = func(): return true
		game.players[1].hand.assign([null])
		game._guanshi_override = func():
			if mode == "reset": game.reset_game_over_state()
			return false if mode == "decline" else (GameManager.CHOICE_INVALID if mode == "invalid" else true)
		game._guanshi_mount_override = func(): return ""
		var result = await suite.strike(game.players[0], game.players[1])
		suite.check(typeof(result) == TYPE_BOOL and not result if mode == "decline" else typeof(result) == TYPE_INT and result == GameManager.CHOICE_INVALID, "E03e-22b：贯石正常放弃与确认/坐骑/重开失效区分：" + mode)
		suite.check(game.players[1].hp == 10 and game.players[0].mount_count() == 1, "E03e-22b：贯石失效不补付费用或重新命中")
	prepare()
	game._rps_override = Callable()
	game._guanshi_override = Callable()
	game._guanshi_mount_override = Callable()
	game._bloodthirsty_override = Callable()
	game = null
	suite = null
