extends RefCounted

func _reset(suite):
	suite.reset_players()
	var game: GameManager = suite.game
	game._dying_peach_override = Callable()
	game._clear_pending_determined_card()
	for player in game.players:
		player.judgment_cards.clear()
		player.mount_plus = 0
		player.mount_minus = 0
		player.facedown = false

func run(suite):
	var game: GameManager = suite.game
	var tm = game.turn_manager
	var old_phase = tm.current_phase
	var callback = game._on_phase_changed
	tm.phase_changed.disconnect(callback)
	var mode_before = game.game_mode
	var bank = game._bank_remaining
	# Legal single Leo: a real paid Duel, including Snatch replaced with Duel.
	for seat in [0, 2]:
		for concrete in [false, true]:
			for sub in [CardData.CardSubType.DUEL, CardData.CardSubType.SNATCH]:
				_reset(suite)
				game.deck._discard.clear()
				game.game_mode = GameManager.MODE_CLASSIC_IDENTITY
				tm.current_phase = TurnManager.Phase.PLAY
				tm.current_player_idx = seat
				var leo: Player = game.players[seat]
				var target: Player = game.players[seat + 1]
				leo.general_name = "里奥·普利威尔"
				leo.max_hp = 5 + leo.identity_max_hp_bonus
				leo.capture_game_start_state()
				leo.hp = 1
				leo.prep_tokens = 2
				var original = CardBase.create(sub) if concrete else null
				if concrete: leo.determined_cards.append(original)
				else: leo.hand.append(null)
				var retained = CardBase.create(CardData.CardSubType.DODGE)
				leo.determined_cards.append(retained)
				var armor = CardBase.create(CardData.CardSubType.SILVER_LION)
				var judgment = CardBase.create(CardData.CardSubType.INDULGENCE)
				leo.equip_card_to_slot("armor", armor)
				leo.judgment_cards.append(judgment)
				var public_before = leo.identity_revealed
				target.hp = 2
				var reply = CardBase.create(CardData.CardSubType.STRIKE)
				target.determined_cards.append(reply)
				game._zone_pick_override = func(): return "hand"
				game._prep_replace_override = func(_l, _u, _t, current, _options): return CardData.CardSubType.DUEL if current == CardData.CardSubType.SNATCH else -1
				game._ai_response_override = func(_view, _kind, options): return CardData.CardSubType.STRIKE if options.has(CardData.CardSubType.STRIKE) else -1
				var actions: Array[CardActionEvent] = []
				var collect = func(e): actions.append(e)
				game.card_action_committed.connect(collect)
				await game.execute_card_on_target(target, sub)
				game.card_action_committed.disconnect(collect)
				suite.check(leo.is_alive() and leo.hp == 1 and target.is_dead() and not game._game_over, "F03a real own Duel loss enters yudaxi and returns alive, not premature final death")
				suite.check(leo.determined_cards == [retained] and leo.hand == [null] and leo.get_equipment_card("armor") == armor and leo.judgment_cards == [judgment], "F03a successful yudaxi preserves exact three-zone resources, extra draw ignores choutai")
				suite.check(leo.identity_revealed == public_before and not game._dead_processed.has(leo) and game.deck._discard.count(armor) == 0 and game.deck._discard.count(judgment) == 0, "F03a successful yudaxi never clears and restores cards or reveals identity")
				suite.check(leo.prep_tokens == (3 if sub == CardData.CardSubType.DUEL else 2) and actions.size() == 2 and actions.all(func(e): return e.settlement_completed), "F03a replaced/original parent finishes after rescue; spends old mark and earns only completed own card")
				suite.check(game.deck._discard.count(reply) == 1 and (not concrete or actions[0].card == original and game.deck._discard.count(original) == 1), "F03a paid arbitrary/concrete parent and real response each keep original entity")
				suite.check(tm.duel_count_this_turn == 1 and tm.steal_count_this_turn == 0 and game.yudaxi.results.size() == 1 and game.yudaxi.results[0].deaths == 1 and game._pending_card_actions.is_empty() and game._dying_contexts.is_empty(), "F03a final category once, direct X and all receipts/contexts released")
	# Real two-Peach rescue from negative HP: no yudaxi when rescue succeeds.
	_reset(suite)
	game.deck._discard.clear()
	tm.current_phase = TurnManager.Phase.PLAY
	var leo: Player = game.players[0]
	leo.general_name = "里奥·普利威尔"
	leo.hp = -1
	var peaches: Array[CardBase] = [CardBase.create(CardData.CardSubType.PEACH), CardBase.create(CardData.CardSubType.PEACH)]
	leo.determined_cards.append_array(peaches)
	game._rescue_choice_override = func(rescuer, dying, options): return CardData.CardSubType.PEACH if rescuer == leo and dying == leo and options.has(CardData.CardSubType.PEACH) else -1
	await game._resolve_dying(leo, null, "F03 rescue")
	suite.check(leo.hp == 1 and leo.prep_tokens == 2 and leo.hand_size() == 0 and peaches.all(func(c): return game.deck._discard.count(c) == 1) and game.yudaxi.results.is_empty(), "F03a negative HP real rescue pays two original peaches, completes marks, bypasses yudaxi")
	suite.check(game.players[1].hp == 10 and game._dying_contexts.is_empty(), "F03a ordinary rescue success does not debit other players")
	# One Leo, real activated Sage window: accept, decline X>0, decline X=0, technical close/restart.
	for mode in ["accept", "success", "failure", "close", "restart"]:
		_reset(suite)
		game.deck._discard.clear()
		tm.current_phase = TurnManager.Phase.PLAY
		leo = game.players[0]
		leo.general_name = "里奥·普利威尔"
		leo.capture_game_start_state()
		leo.hp = 0
		leo.prep_tokens = 4
		leo.hand.append(null)
		var armor = CardBase.create(CardData.CardSubType.SAGE_PROTECTION)
		var judgment = CardBase.create(CardData.CardSubType.INDULGENCE)
		leo.equip_card_to_slot("armor", armor)
		leo.sage_activated = true
		leo.judgment_cards.append(judgment)
		game.players[1].hp = 2 if mode == "success" else 10
		game._sage_save_override = Callable()
		var asks: Array[int] = []
		var drive = func():
			asks.append(1)
			var pending = game._choice_prompt_stack.back()
			suite.check(game.yudaxi.results.is_empty() and leo.prep_tokens == 4 and leo.get_equipment_card("armor") == armor, "F03a Sage choice precedes yudaxi and original equipment/markers remain")
			if mode == "close": pending.overlay.queue_free()
			elif mode == "restart": game.reset_game_over_state()
			else: pending.overlay.find_children("*", "Button", true, false)[0 if mode == "accept" else 1].pressed.emit()
		drive.call_deferred()
		var result = await game._resolve_dying(leo, null, "F03 sage")
		if mode == "accept":
			suite.check(result == 0 and leo.is_alive() and leo.hp == leo.max_hp and leo.prep_tokens == 0 and leo.hand == [null, null, null, null] and leo.equipment.is_empty() and leo.judgment_cards.is_empty() and game.yudaxi.results.is_empty(), "F03a Sage resets start markers and three zones before drawing four; no yudaxi")
		elif mode == "success":
			suite.check(result == 0 and leo.hp == 1 and leo.prep_tokens == 4 and leo.hand == [null, null] and leo.get_equipment_card("armor") == armor and leo.judgment_cards == [judgment], "F03a declining Sage permits yudaxi, retains original activated armor and markers, no second Sage choice")
		elif mode == "failure":
			suite.check(result == 0 and leo.is_dead() and leo.hp == 0 and leo.hand_size() == 0 and leo.equipment.is_empty() and leo.judgment_cards.is_empty() and game.deck._discard.count(armor) == 1 and game.deck._discard.count(judgment) == 1, "F03a X zero final death clears original zones once, never reoffers refused Sage")
		else:
			suite.check(result == GameManager.CHOICE_INVALID and leo.is_dying() and leo.hand == [null] and leo.prep_tokens == 4 and leo.get_equipment_card("armor") == armor and game.yudaxi.results.is_empty(), "F03a technical Sage failure not refusal, no yudaxi/death/card clear")
		await suite.process_frame
		suite.check(asks.size() == 1 and game._choice_prompt_stack.is_empty() and game._sage_save_pending.is_empty() and game._dying_contexts.is_empty(), "F03a single Sage decision and no old window/context after completion")
	# Legal nested frame is another character's dying/rescue, not a duplicate Leo.
	_reset(suite)
	game.deck._discard.clear()
	tm.current_phase = TurnManager.Phase.PLAY
	leo = game.players[2]
	leo.general_name = "里奥·普利威尔"
	leo.hp = -4
	leo.max_hp = 1
	game.players[3].hp = 2
	game.players[4].hp = 2
	var child = game.players[3]
	var peach = CardBase.create(CardData.CardSubType.PEACH)
	child.determined_cards.append(peach)
	game._rescue_choice_override = func(rescuer, dying, options): return CardData.CardSubType.PEACH if rescuer == child and dying == child and options.has(CardData.CardSubType.PEACH) else -1
	await game._resolve_dying(leo, null, "F03 nested rescue")
	suite.check(leo.hp == 1 and child.hp == 1 and game.players[4].is_dead() and game.yudaxi.results[0].deaths == 1 and game.deck._discard.count(peach) == 1, "F03a negative HP parent awaits real child rescue, only direct final deaths enter X")
	suite.check(game._dying_contexts.is_empty() and not game.yudaxi.is_active(), "F03a legal parent/child windows both release")
	# DY-07: rotate A/B to seats 4/0 so B really activates the existing self UI
	# on a legal out-of-turn empty hand, rather than injecting a kneeling flag.
	_reset(suite)
	game.deck._discard.clear()
	tm.current_phase = TurnManager.Phase.PLAY
	tm.current_player_idx = 4
	var identities_before: Array = []
	var roles = ["忠臣", "反贼", "反贼", "内奸", "主公"]
	for i in game.players.size():
		var p = game.players[i]
		identities_before.append([p.identity, p.identity_revealed, p.identity_max_hp_bonus])
		p.identity_max_hp_bonus = 0
		p.identity = roles[i]
		p.identity_revealed = i == 4
		p.max_hp = 5
		p.hp = 5
	leo = game.players[4]
	leo.general_name = "里奥·普利威尔"
	leo.identity_max_hp_bonus = 1
	leo.capture_game_start_state()
	leo.hp = 1
	leo.hand.append(null)
	var armor = CardBase.create(CardData.CardSubType.SILVER_LION)
	var judgment = CardBase.create(CardData.CardSubType.INDULGENCE)
	leo.equip_card_to_slot("armor", armor)
	leo.judgment_cards.append(judgment)
	var bruce: Player = game.players[0]
	bruce.general_name = "布鲁斯·萨维奇"
	bruce.max_hp = 5
	bruce.hp = 1
	bruce.kneel_used = false
	game._kneel_override = func(): return true
	await game._on_kneel_skill_clicked(bruce)
	suite.check(bruce.kneeling and bruce.kneel_used and bruce.is_alive() and not game._get_all_alive_targets(leo).has(bruce), "F03c Q1 Bruce really enters legal kneeling; ordinary effect protection remains")
	await game._deal_damage_result(game.players[2], leo, 1, EffectChain.DamageType.PHYSICAL)
	suite.check(bruce.is_dead() and bruce.hp == -1 and game.yudaxi.results.size() == 1 and game.yudaxi.results[0].deaths == 1,
		"F03c Q1 kneeling Bruce deducts two and his final death enters direct X")
	suite.check(leo.is_alive() and leo.hp == 1 and leo.hand == [null, null] and leo.get_equipment_card("armor") == armor and leo.judgment_cards == [judgment],
		"F03c Q1 Leo restores to one, draws one arbitrary card and preserves all original zones")
	suite.check(game.players[1].hp == 3 and game.players[2].hp == 3 and game.players[3].hp == 3 and game._dying_contexts.is_empty() and not game.yudaxi.is_active() and not game._game_over,
		"F03c Q1 continues remaining targets and releases whole real damage/dying flow")
	suite.check(leo.identity == "主公" and leo.identity_revealed and leo.max_hp == 6 and bruce.identity == "忠臣" and bruce.identity_revealed,
		"F03c Q1 uses complete legal five-player identities and real base/lord HP; only final victim reveals")
	for i in game.players.size():
		game.players[i].identity = identities_before[i][0]
		game.players[i].identity_revealed = identities_before[i][1]
		game.players[i].identity_max_hp_bonus = identities_before[i][2]
	game._kneel_override = Callable()
	game._sage_save_override = Callable()
	game._zone_pick_override = Callable()
	suite.reset_players()
	game.game_mode = mode_before
	game._bank_remaining = bank
	tm.current_phase = old_phase
	tm.phase_changed.connect(callback)
