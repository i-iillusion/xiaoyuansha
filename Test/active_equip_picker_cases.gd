extends RefCounted

var suite
var game: GameManager
var windows: Array = []

func reset():
	suite.reset_players()
	game.deck._discard.clear()
	game.equipment_pool.clear()
	game._clear_pending_determined_card()
	game._mount_replace_override = Callable()
	game._weapon_replace_override = Callable()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	for p in game.players:
		p.hidden_equip_slot = ""
		p.hidden_equip_card = null
		p.mount_plus = 0
		p.mount_minus = 0

func drive(action: String, p: Player, slot: String, old_sub: int):
	var pending = game._choice_prompt_stack.back()
	windows.append(pending.overlay)
	var buttons = pending.overlay.find_children("*", "Button", true, false)
	suite.check(not game._countdown_active and buttons.size() == (5 if slot.begins_with("mount") else 2), "E03e-15b：主动装备替换独立无计时")
	match action:
		"close":
			pending.overlay.queue_free()
			return
		"phase", "phase_idle":
			game.turn_manager.current_phase = TurnManager.Phase.END
			game.turn_manager.current_phase = TurnManager.Phase.PLAY
			if action == "phase_idle": return
		"actor":
			game.turn_manager.play_actor_idx = 1
			game.turn_manager.play_actor_idx = -1
		"same":
			p.determined_cards.append(p.remove_equipment(slot))
			p.equip_card_to_slot(slot, CardBase.create(old_sub))
		"dead":
			p.hp = 0
			p.mark_dead()
		"ended":
			game._finish_game("平局", "主动装备替换回归")
			return
	buttons[-1 if action == "cancel" else (2 if slot.begins_with("mount") else 0)].pressed.emit()
	pending.answer.submit(1)

func run(host):
	suite = host
	game = host.game
	var events: Array = []
	var collect = func(event): events.append(event)
	game.card_action_committed.connect(collect)
	for category in ["weapon", "armor", "mount"]:
		for concrete in [false, true]:
			for action in ["choose", "cancel", "close", "phase", "phase_idle", "actor", "same", "dead", "ended"]:
				reset()
				events.clear()
				var p = game.players[0]
				p.hp = 8
				var slot = "mount_3" if category == "mount" else category
				var old_sub = CardData.CardSubType.LIANNU if category == "weapon" else (CardData.CardSubType.SILVER_LION if category == "armor" else CardData.CardSubType.MOUNT_PLUS)
				var incoming_sub = CardData.CardSubType.QINGLONG_BLADE if category == "weapon" else (CardData.CardSubType.RENWANG_DUN if category == "armor" else CardData.CardSubType.MOUNT_MINUS)
				if category == "mount":
					for mount_slot in Player.MOUNT_SLOTS:
						if mount_slot != slot: p.equip_card_to_slot(mount_slot, CardBase.create(CardData.CardSubType.MOUNT_MINUS))
				var old = CardBase.create(old_sub)
				p.equip_card_to_slot(slot, old)
				var incoming = CardBase.create(incoming_sub) if concrete else null
				if concrete:
					p.determined_cards.append(incoming)
					game._pending_determined_card = incoming
				else: p.hand.append(null)
				drive.call_deferred(action, p, slot, old_sub)
				await game.play_card(incoming_sub)
				var moved = action == "choose"
				var current = p.get_equipment_card(slot)
				suite.check(current != null and current.sub_type == (incoming_sub if moved else old_sub) and (not concrete or not moved or current == incoming), "E03e-15b：有效选择原装备落位，旧答复不替换后来者")
				suite.check(events.size() == (1 if moved else 0) and game.deck._discard.count(old) == (1 if moved else 0), "E03e-15b：成功支付一次/弃旧一次，失效不付新牌")
				suite.check((not p.determined_cards.has(incoming) if moved else p.determined_cards.has(incoming)) if concrete else (p.hand.is_empty() if moved else p.hand == [null]), "E03e-15b：任意/具体手牌支付边界保持")
				suite.check(p.hp == (0 if action == "dead" else (9 if category == "armor" and action in ["choose", "same"] else 8)), "E03e-15b：主动替换按EQ-01失去狮子回血一次")
				suite.check(category != "mount" or (p.mount_count() == 4 and p.mount_plus == (0 if moved else 1) and p.mount_minus == (4 if moved else 3)), "E03e-15b：所选第三马位替换及四槽计数一致")
				suite.check(game._choice_prompt_stack.is_empty(), "E03e-15b：确认等待清理")
				await suite.process_frame
	suite.check(windows.all(func(window): return not is_instance_valid(window)), "E03e-15b：全部窗口实际释放")
	game.card_action_committed.disconnect(collect)
	reset()
	var p = game.players[0]
	for slot in Player.MOUNT_SLOTS: p.equip_card_to_slot(slot, CardBase.create(CardData.CardSubType.MOUNT_PLUS))
	var old: Array = []
	var capture = func():
		var pending = game._choice_prompt_stack.back()
		old.append(pending.overlay.find_children("*", "Button", true, false)[0].get_signal_connection_list("pressed")[0].callable)
		pending.overlay.queue_free()
	capture.call_deferred()
	suite.check(await game._show_weapon_replace_confirm(CardData.CardSubType.LIANNU, CardData.CardSubType.QINGLONG_BLADE) == GameManager.CHOICE_INVALID, "E03e-15b：替换确认关闭不是主动取消")
	await suite.process_frame
	var next = func():
		var pending = game._choice_prompt_stack.back()
		old[0].call()
		game._weapon_replace_result.emit(true)
		game._mount_replace_result.emit("mount_1")
		suite.check(not pending.answer.settled, "E03e-15b：旧确认按钮/两种共享信号不污染新坐骑选择")
		pending.overlay.find_children("*", "Button", true, false)[2].pressed.emit()
	next.call_deferred()
	suite.check(await game._show_mount_replace_picker(p) == "mount_3", "E03e-15b：下一合法第三槽选择正常完成")
	await suite.process_frame
	reset()
	suite = null
	game = null
