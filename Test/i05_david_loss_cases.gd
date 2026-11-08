extends RefCounted
const Farming = preload("res://Test/i05_david_farming_cases.gd")
const DAVID = "大卫·法米尔"
const O = CardLossTransaction.Outcome

func fixture(t):
	var game = Farming.new().fixture(t)
	for p in game.players:
		p.general_name = "稻草人"
		p.hand.clear()
		p.determined_cards.clear()
	game.players[1].general_name = DAVID
	game.players[1].hp = 3
	game.players[1].capture_game_start_state()
	game._liehuo_override = func(): return false
	game._dodge_override = func(): return false
	return game

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	await zones(t)
	await forced(t)
	await stale(t)
	await ice(t)
	await swaps(t)
	await multiple_swaps(t)
	await disarm(t)
	await excluded(t)
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]

# The hook is ONLY a diagnostic pre-move outcome, not a completed Wrestle skill.
# Every check below drives a real paid parent effect or a precise boundary case.
func zones(t):
	for zone in ["hand", "equip", "judgment"]:
		for snatch in [false, true]:
			for prevent in [false, true]:
				var game = fixture(t)
				var source = game.players[0]
				var target = game.players[1]
				var card = CardBase.create(CardData.CardSubType.SILVER_LION if zone == "equip" else CardData.CardSubType.INDULGENCE)
				if zone == "hand": target.determined_cards.append(card)
				elif zone == "equip": target.equip_card_to_slot("armor", card)
				else: target.judgment_cards.append(card)
				source.hand.append(null)
				var calls: Array = []
				game._card_loss_reaction_override = func(owner, tx, valid):
					calls.append(tx)
					t.check(owner == target and tx.source == source and tx.reason == ("snatch" if snatch else "dismantle") and valid.call(), "I05b4a original source and selected zone survive paid parent")
					t.check(tx.losses.size() == 1 and tx.losses[0].card == card and source.hand_size() == 0 and target.hp == 3, "I05b4a callback runs after cost but before original card moves or Lion heals")
					return O.PREVENTED if prevent else O.ALLOW
				game._zone_pick_override = func(): return zone
				game._equip_pick_override = func(): return "armor"
				await game.execute_card_on_target(target, CardData.CardSubType.SNATCH if snatch else CardData.CardSubType.DISMANTLE)
				var kept = target.determined_cards.has(card) if zone == "hand" else (target.get_equipment_card("armor") == card if zone == "equip" else target.judgment_cards.has(card))
				t.check(calls.size() == 1 and kept == prevent and source.hand_size() == (1 if snatch and not prevent else 0), "I05b4a paid steal commits once or preserves original selected card")
				t.check(game.deck._discard.count(card) == (1 if not snatch and not prevent else 0) and target.hp == (4 if zone == "equip" and not prevent else 3), "I05b4a original discard identity and Lion loss side effects occur only on real move")
				t.check(game._pending_card_actions.is_empty() and game._card_loss_pending.is_empty(), "I05b4a paid parent and transaction leases finish without refund")
				await Farming.new().dispose(t, game)

func forced(t):
	for zone in ["hand", "equip", "judgment"]:
		for prevent in [false, true]:
			var game = fixture(t)
			var target = game.players[1]
			var card = CardBase.create(CardData.CardSubType.LIANNU)
			if zone == "hand": target.hand.assign([null]); target.determined_cards.append(card)
			elif zone == "equip": target.equip_card_to_slot("weapon", card)
			else: target.judgment_cards.append(card)
			game._prep_steal_pick_override = func(choices): return choices.size() - 1
			var calls: Array = []
			game._card_loss_reaction_override = func(_owner, tx, valid):
				calls.append(tx)
				t.check(valid.call() and tx.losses[0].card == card and tx.losses[0].zone == ("determined" if zone == "hand" else zone), "I05b4a forced selector preserves precise mixed-hand index or slot before move")
				return O.PREVENTED if prevent else O.ALLOW
			var result = await game._resolve_forced_steal_pick(game.players[0], target, true, func(): return true)
			t.check(result == 0 and calls.size() == 1 and game.players[0].hand_size() == (0 if prevent else 1), "I05b4a forced PREP boundary distinguishes prevention from technical invalidation")
			await Farming.new().dispose(t, game)

func stale(t):
	for change in ["hand", "equip", "judgment", "general", "phase", "death", "reset", "source", "parent", "nested"]:
		var game = fixture(t)
		var target = game.players[1]
		var original = CardBase.create(CardData.CardSubType.LIANNU)
		target.equip_card_to_slot("weapon", original)
		var allowed: Array = [true]
		game._equip_pick_override = func(): return "weapon"
		var before = game.deck._discard.size()
		game._card_loss_reaction_override = func(_p, tx, valid):
			t.check(tx.valid() and valid.call() and target.get_equipment_card("weapon") == original, "I05b4a valid original exists throughout pending transaction")
			await t.process_frame
			match change:
				"hand": target.hand.append(null)
				"equip": target.detach_equipment_quiet("weapon"); target.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.LIANNU))
				"judgment": target.judgment_cards.append(CardBase.create(CardData.CardSubType.LIGHTNING))
				"general": target.awakening_revision += 1
				"phase": game.turn_manager.current_phase = TurnManager.Phase.END
				"death": target.life_state = Player.LifeState.DEAD
				"reset": game._dying_lifecycle_generation += 1
				"source": game.players[0].awakening_revision += 1
				"parent": allowed[0] = false
				"nested":
					var result = await game._before_external_card_loss(game.players[0], "snatch", tx.losses)
					t.check(result == O.INVALIDATED and game._card_loss_pending.size() == 1, "I05b4a duplicate pending owner cannot replace parent lease")
					return O.ALLOW
			return O.PREVENTED
		var result = await game._steal_equip(game.players[0], target, true, "顺手牵羊", func(): return allowed[0])
		t.check((result == GameManager.CHOICE_INVALID) == (change != "nested") and game._card_loss_pending.is_empty(), "I05b4a stale context is INVALIDATED, never treated as optional decline or prevention")
		t.check(game.deck._discard.size() == before and game.players[0].hand_size() == (1 if change == "nested" else 0), "I05b4a stale response never moves later cards or discards a saved original")
		await Farming.new().dispose(t, game)

func ice(t):
	for count in [1, 2]:
		for prevent in [false, true]:
			var game = fixture(t)
			var source = game.players[0]
			var target = game.players[1]
			source.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.ICE_SWORD))
			source.hand.append(null)
			target.hand.resize(count)
			game._ice_sword_override = func(): return true
			var seen: Array = []
			game._card_loss_reaction_override = func(_owner, tx, valid):
				seen.append(tx)
				t.check(tx.reason == "ice_sword" and tx.losses.size() == count and target.hand_size() == count and valid.call(), "I05b4a Q3 Ice snapshots entire insufficient/all two-card loss before first move")
				return O.PREVENTED if prevent else O.ALLOW
			await game.execute_card_on_target(target, CardData.CardSubType.STRIKE)
			t.check(seen.size() == 1 and target.hand_size() == (count if prevent else 0) and target.hp == 3, "I05b4a Ice prevention keeps all cards; committed Ice has already replaced original damage")
			t.check(game._pending_card_actions.is_empty() and game._card_loss_pending.is_empty(), "I05b4a Ice restores actual Strike settlement and ownership")
			await Farming.new().dispose(t, game)

func swaps(t):
	for empty in [false, true]:
		for prevent in [false, true]:
			var game = fixture(t)
			var source = game.players[0]
			source.general_name = "麦克斯·欧尼斯特"
			source.hand.append(null)
			var target = game.players[1]
			var other = game.players[2]
			var first = CardBase.create(CardData.CardSubType.LIANNU)
			var second = CardBase.create(CardData.CardSubType.QINGGANG_SWORD)
			target.equip_card_to_slot("weapon", first)
			if not empty: other.equip_card_to_slot("weapon", second)
			var zones: Array = ["weapon", "done"]
			game._lanzhonghou_zone_override = func(): return zones.pop_front()
			game._hand_discard_override = func(snapshot, n, _m): return snapshot.defaults(n)
			var asks: Array = []
			game._card_loss_reaction_override = func(_owner, tx, valid):
				asks.append(tx)
				t.check(tx.source == source and tx.reason == "equipment_swap" and tx.losses.size() == (1 if empty else 2) and valid.call() and source.hand_size() == 0, "I05b4a swap records actual Max source, entire original pair and paid cost")
				return O.PREVENTED if prevent else O.ALLOW
			await game._run_lanzhonghou(target, other)
			t.check(asks.size() == 1 and target.get_equipment_card("weapon") == (first if prevent else (null if empty else second)) and other.get_equipment_card("weapon") == ((null if empty else second) if prevent else first), "I05b4a Q3 prevention cancels whole original pair, including one empty slot")
			t.check(source.hand_size() == 0 and game._lanzhonghou_used and game._card_loss_pending.is_empty(), "I05b4a prevention does not refund swap skill fee or stage use")
			await Farming.new().dispose(t, game)

func multiple_swaps(t):
	# Q12: prevent the entire multi-pair skill before any pair moves.
	for prevent_weapon in [false, true]:
		var game = fixture(t)
		var source = game.players[0]
		source.general_name = "麦克斯·欧尼斯特"
		source.hand.assign([null, null])
		var a = game.players[1]
		var b = game.players[2]
		var aw = CardBase.create(CardData.CardSubType.LIANNU)
		var bw = CardBase.create(CardData.CardSubType.QINGGANG_SWORD)
		var aa = CardBase.create(CardData.CardSubType.SILVER_LION)
		var ba = CardBase.create(CardData.CardSubType.ZHANQI)
		a.equip_card_to_slot("weapon", aw); b.equip_card_to_slot("weapon", bw)
		a.equip_card_to_slot("armor", aa); b.equip_card_to_slot("armor", ba)
		var zones: Array = ["weapon", "armor", "done"]
		game._lanzhonghou_zone_override = func(): return zones.pop_front()
		game._hand_discard_override = func(snapshot, n, _m): return snapshot.defaults(n)
		var asks: Array = []
		game._card_loss_reaction_override = func(_owner, tx, valid):
			asks.append(tx.losses.size())
			t.check(valid.call() and tx.losses.size() == 4 and a.get_equipment_card("weapon") == aw and a.get_equipment_card("armor") == aa, "I05b4a Q12 all original pairs remain unmoved before one whole-skill reaction")
			return O.PREVENTED if prevent_weapon and tx.losses[0].slot == "weapon" else O.ALLOW
		await game._run_lanzhonghou(a, b)
		t.check(asks == [4] and a.get_equipment_card("weapon") == (aw if prevent_weapon else bw) and b.get_equipment_card("weapon") == (bw if prevent_weapon else aw), "I05b4a Q12 whole-skill prevention retains both original weapons")
		t.check(a.get_equipment_card("armor") == (aa if prevent_weapon else ba) and b.get_equipment_card("armor") == (ba if prevent_weapon else aa) and source.hand_size() == 0, "I05b4a Q12 whole-skill prevention retains both armors without refunding either cost")
		await Farming.new().dispose(t, game)

func disarm(t):
	for prevent in [false, true]:
		var game = fixture(t)
		var target = game.players[1]
		var other = game.players[2]
		var lion = CardBase.create(CardData.CardSubType.SILVER_LION)
		var horse = CardBase.create(CardData.CardSubType.MOUNT_PLUS)
		target.equip_card_to_slot("armor", lion)
		other.equip_card_to_slot("mount_1", horse)
		game.players[0].hand.append(null)
		var asks: Array = []
		game._card_loss_reaction_override = func(owner, tx, valid):
			asks.append(owner)
			t.check(tx.reason == "disarm" and valid.call() and tx.losses.size() == 1 and tx.losses[0].owner == target, "I05b4a Q9 Disarm transaction contains only David's local segment")
			return O.PREVENTED if prevent else O.ALLOW
		await game.play_card(CardData.CardSubType.DISARM)
		t.check(asks == [target] and target.hand_size() == (0 if prevent else 1) and target.hp == (3 if prevent else 4), "I05b4a Q9 no compensation or Lion heal when David segment prevented")
		t.check(other.hand_size() == 1 and other.get_equipment_card("mount_1") == null and game.deck._discard.count(horse) == 1 and game._pending_card_actions.is_empty(), "I05b4a Q9 other Disarm target keeps normal equip discard and compensation")
		await Farming.new().dispose(t, game)

func excluded(t):
	var game = fixture(t)
	var target = game.players[1]
	target.hand.assign([null, null, null])
	var asks: Array = []
	game._card_loss_reaction_override = func(_o, _tx, _v): asks.append(true); return O.PREVENTED
	for reason in ["cost", "discard", "death", "sage", "unconfirmed"]:
		var result = await game._before_external_card_loss(game.players[0], reason, game._hand_loss_atoms(target, 1))
		t.check(result == O.ALLOW and asks.is_empty(), "I05b4a Q2/Q7/Q8 no authorization for costs, discard phase or either cleanup")
	var self_result = await game._before_external_card_loss(target, "dismantle", game._hand_loss_atoms(target, 1))
	t.check(self_result == O.ALLOW and asks.is_empty(), "I05b4a self-paid loss cannot become external skill reaction")
	game._david_rules_enabled = false
	await game._steal_hand(game.players[0], target, false, "过河拆桥")
	t.check(asks.is_empty() and target.hand_size() == 2, "I05b4a default-disabled private feature preserves original production loss")
	await Farming.new().dispose(t, game)
