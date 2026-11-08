extends RefCounted
const Loss = preload("res://Test/i05_david_loss_cases.gd")
const Farming = preload("res://Test/i05_david_farming_cases.gd")
const O = CardLossTransaction.Outcome

func fixture(t):
	var game = Loss.new().fixture(t)
	game._wrestling_rules_enabled = true
	game.players[0].max_hp = 4
	game.players[0].hp = 4
	game.players[1].max_hp = 4
	game.players[1].capture_game_start_state()
	game._wrestling_choice_override = func(_owner, _valid): return 1
	game._zone_pick_override = func(): return "equip"
	game._equip_pick_override = func(): return "armor"
	return game

func equip(game):
	var card = CardBase.create(CardData.CardSubType.SILVER_LION)
	game.players[1].equip_card_to_slot("armor", card)
	return card

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	await declarations(t)
	await refusals(t)
	await counter_chain(t)
	await response_cards(t)
	await dead_disarm_source(t)
	await granted_and_ai(t)
	await replacements(t)
	await continuous_replacements(t)
	await borrowed_replacement(t)
	await paid_equipment_effects(t)
	await death(t)
	await sage_during_counter(t)
	await round_and_restore(t)
	await forced_minus_mule(t)
	await stale(t)
	for owner in [0, 1]:
		for mode in ["accept", "cancel", "timeout", "restore"]: await bridge_case(t, owner, mode)
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]

func declarations(t):
	for blocked in ["none", "flag", "awake", "dead", "range"]:
		var game = fixture(t)
		var source = game.players[0]
		var owner = game.players[1]
		var card = equip(game)
		if blocked == "flag": source.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.ZHANQI))
		elif blocked == "awake": source.general_name = "史蒂芬·彼特先斯"; source.awoken = true; source.awake_choice = 2
		elif blocked == "dead": source.life_state = Player.LifeState.DEAD; source.hp = 0
		elif blocked == "range":
			for slot in Player.MOUNT_SLOTS: source.equip_card_to_slot(slot, CardBase.create(CardData.CardSubType.MOUNT_PLUS))
		var facts: Array = []
		game.card_action_committed.connect(func(a): facts.append(a))
		game.turn_manager._set_turn_count("duel", 2, owner.seat_index)
		game.turn_manager._set_turn_count("duel", 2, source.seat_index)
		var result = await game._steal_equip(source, owner, true, "顺手牵羊")
		var has_duel = blocked in ["none", "range"]
		t.check(result == O.PREVENTED and owner.get_equipment_card("armor") == card and owner.hp == 3, "I05b4b confirmed prevention retains original Lion without false healing")
		t.check(source.hp == (3 if has_duel else (0 if blocked == "dead" else 4)) and facts.size() == (1 if has_duel else 0), "I05b4b Q6/Q10/Q11 no card for flag/awakening/dead target; distant legal source receives actual Duel")
		if has_duel:
			t.check(facts[0].actor_body == owner and facts[0].sub_type == CardData.CardSubType.DUEL and facts[0].is_virtual and not facts[0].from_hand and facts[0].settlement_completed, "I05b4b extra Duel publishes exactly one complete non-hand USE by real David")
			t.check(not game.deck._discard.has(facts[0].card) and owner.farm_hand_actions == 0 and owner.farm_empty_fields == 0, "I05b4b virtual Duel neither creates physical discard nor farming pair")
		t.check(game.turn_manager._get_turn_count("duel", owner.seat_index) == 2 and game.turn_manager._get_turn_count("duel", source.seat_index) == 2, "I05b4b extra original Duel neither checks nor occupies either ordinary Duel quota")
		t.check(owner.wrestle_round == game.turn_manager.rounds.round_id and not game._wrestling_ready(owner) and game._card_loss_pending.is_empty() and game._wrestling_resolving.is_empty(), "I05b4b confirmation commits once-per-round even without legal counter and releases leases")
		await Farming.new().dispose(t, game)

func refusals(t):
	for reply in [0, -1, GameManager.CHOICE_INVALID]:
		var game = fixture(t)
		var card = equip(game)
		game._wrestling_choice_override = func(_o, _v): return reply
		var facts: Array = []
		game.card_action_committed.connect(func(a): facts.append(a))
		var result = await game._steal_equip(game.players[0], game.players[1], true, "顺手牵羊")
		t.check((result == GameManager.CHOICE_INVALID) == (reply == GameManager.CHOICE_INVALID), "I05b4b optional refusal differs from technical invalidation")
		t.check(game.players[1].get_equipment_card("armor") == (card if reply == GameManager.CHOICE_INVALID else null) and facts.is_empty() and game.players[1].wrestle_round == -1, "I05b4b decline moves original normally; invalidation preserves it; neither spends round quota")
		await Farming.new().dispose(t, game)

func counter_chain(t):
	for nullified in [false, true]:
		var game = fixture(t)
		var card = equip(game)
		var owner = game.players[1]
		game.players[0].hand.append(null)
		if nullified: game.players[2].hand.append(null)
		var facts: Array = []
		var virtuals: Array = []
		var used: Array = []
		game.card_action_committed.connect(func(a):
			facts.append(a)
			if a.actor_body == owner and a.is_virtual: virtuals.append(a))
		game._nullify_override = func():
			if not nullified or virtuals.is_empty() or not used.is_empty(): return false
			used.append(true)
			return true
		await game.execute_card_on_target(owner, CardData.CardSubType.SNATCH)
		t.check(facts.size() == (3 if nullified else 2) and facts.all(func(a): return a.settlement_completed), "I05b4b paid parent, virtual Duel and optional actual Nullification complete their own facts")
		t.check(owner.get_equipment_card("armor") == card and owner.hp == 3 and game.players[0].hp == (4 if nullified else 3), "I05b4b nullifying counter never reverses committed prevention or triggers Lion")
		t.check(game.players[0].hand_size() == 0 and game._pending_card_actions.is_empty() and game._input_seat == 0, "I05b4b no refunded parent cost, dangling action or wrong responder after nested chain")
		await Farming.new().dispose(t, game)

func response_cards(t):
	var game = fixture(t)
	var owner = game.players[1]
	var source = game.players[0]
	var original = equip(game)
	source.hand.assign([null, null])
	owner.hand.append(null)
	game._duel_respond_override = func(): return true
	var facts: Array = []
	game.card_action_committed.connect(func(a): facts.append(a))
	await game.execute_card_on_target(owner, CardData.CardSubType.SNATCH)
	t.check(facts.size() == 4 and facts[2].actor_body == source and facts[3].actor_body == owner and facts[2].kind == CardActionEvent.Kind.RESPONSE and facts[3].kind == CardActionEvent.Kind.RESPONSE, "I05b4b counter Duel pays actual response cards in target-first order")
	t.check(facts.all(func(a): return a.settlement_completed) and source.hp == 3 and owner.hp == 3 and source.hand_size() == 0 and owner.hand_size() == 0, "I05b4b both actual response payments resume full Duel and complete parent after hands change")
	t.check(owner.get_equipment_card("armor") == original and not game.deck._discard.has(original) and owner.farm_hand_actions == 0, "I05b4b post-confirmation response hand changes cannot invalidate committed prevention or farm outside own turn")
	await Farming.new().dispose(t, game)

func dead_disarm_source(t):
	var game = fixture(t)
	game.lan_enabled = false
	var user = game.players[0]
	var owner = game.players[1]
	user.general_name = "安普提·斯丢皮得"
	user.hp = 1
	user.hand.append(null)
	var original = equip(game)
	game.players[2].hand.append(null)
	game._nullify_override = func(): return user.is_alive()
	game._yes_ah_override = func(): return "card" if user.hand_size() > 0 else "skill"
	game._rps_override = func(actor): return game.RPS_ROCK if actor == user else game.RPS_PAPER
	game._ai_response_override = func(view, kind, options):
		if kind == "nullification" and user.is_dead() and view.actor == 2 and options.has(CardData.CardSubType.NULLIFICATION): return CardData.CardSubType.NULLIFICATION
		return -1
	var facts: Array = []
	game.card_action_committed.connect(func(a): facts.append(a))
	await game.play_card(CardData.CardSubType.DISARM)
	t.check(user.is_dead() and not game._game_over and facts.size() == 3 and facts[1].is_virtual and facts[1].actor_body == user and facts[2].actor_body == game.players[2], "I05b4b Q10 actual Disarm source dies paying virtual Nullification, then real counter restores Disarm")
	t.check(facts.all(func(a): return a.settlement_completed) and owner.get_equipment_card("armor") == original and owner.hp == 3 and owner.hand_size() == 0, "I05b4b Q10 exact timeline prevents local Disarm segment with no Duel USE, Lion heal or compensation")
	t.check(owner.wrestle_round == game.turn_manager.rounds.round_id and game._pending_card_actions.is_empty(), "I05b4b Q10 exact source-death reaction consumes its round and completes original retained source action")
	await Farming.new().dispose(t, game)

func granted_and_ai(t):
	var game = fixture(t)
	var donor = game.players[0]
	var owner = game.players[1]
	var actor = game.players[2]
	donor.general_name = "麦克斯·欧尼斯特"
	actor.hand.append(null)
	var original = equip(game)
	game.turn_manager.current_phase = TurnManager.Phase.START
	game._meiyong_override = func(): return true
	game._meiyong_option_override = func(): return 2
	game._meiyong_target_override = func(): return actor
	var facts: Array = []
	game.card_action_committed.connect(func(a): facts.append(a))
	var action = func():
		t.check(game._play_actor() == actor, "I05b4b gifted PLAY starts with actual recipient")
		await game.execute_card_on_target(owner, CardData.CardSubType.DISMANTLE)
		t.check(facts.size() == 2 and facts[0].actor_body == actor and facts[1].actor_body == owner and facts[0].turn_owner_key == donor.seat_index and facts[1].turn_owner_key == donor.seat_index, "I05b4b counter inside actual gifted PLAY retains both real users and original turn owner")
		game.end_play_phase()
	action.call_deferred()
	await game._maybe_meiyong(donor)
	t.check(game.turn_manager.current_phase == TurnManager.Phase.START and game._play_actor() == donor and owner.get_equipment_card("armor") == original and actor.hp == 4, "I05b4b nested prevention returns from full gift to donor START without transferring protected equipment")
	t.check(game.turn_manager._get_turn_count("steal", actor.seat_index) == 1 and game.turn_manager._get_turn_count("steal", donor.seat_index) == 0 and game._pending_card_actions.is_empty(), "I05b4b gift parent counted only for recipient and all nested actions complete")
	await Farming.new().dispose(t, game)
	game = fixture(t)
	game.lan_enabled = false
	game._wrestling_choice_override = Callable()
	original = equip(game)
	var result = await game._steal_equip(game.players[0], game.players[1], true, "顺手牵羊")
	t.check(result == O.PREVENTED and game.players[1].get_equipment_card("armor") == original and game.players[0].hp == 3, "I05b4b ordinary AI chooses legal own optional prevention and resolves full Duel")
	await Farming.new().dispose(t, game)

func replacements(t):
	for limited in [false, true]:
		var game = fixture(t)
		var owner = game.players[1]
		var source = game.players[0]
		var leo = game.players[2]
		leo.general_name = "里奥·普利威尔"
		leo.prep_tokens = 1
		source.hand.append(null)
		var card = equip(game)
		game.turn_manager._set_turn_count("harvest", 1 if limited else 0, owner.seat_index)
		var seen: Array = []
		game._prep_replace_override = func(_leo, actor, fixed, _sub, candidates):
			if actor != owner: return -1
			seen.append(candidates.duplicate())
			t.check(fixed == source and candidates.has(CardData.CardSubType.HARVEST) == not limited, "I05b4b PREP uses actual counter user quota, not current PLAY actor's unused quota")
			return CardData.CardSubType.HARVEST if not limited else -1
		var facts: Array = []
		game.card_action_committed.connect(func(a): facts.append(a))
		await game.execute_card_on_target(owner, CardData.CardSubType.DISMANTLE)
		t.check(not seen.is_empty() and leo.prep_tokens == (1 if limited else 0) and owner.get_equipment_card("armor") == card, "I05b4b actual virtual Duel can be replaced while parent selected original remains protected")
		t.check(owner.hand_size() == (0 if limited else 1) and source.hand_size() == 0 and source.hp == (3 if limited else 4), "I05b4b chosen Harvest draws missing HP for wounded owner, full source draws zero; limited case retains Duel")
		t.check(game.turn_manager._get_turn_count("harvest", source.seat_index) == 0 and game.turn_manager._get_turn_count("harvest", owner.seat_index) == 1, "I05b4b replacement quota recorded for David without changing current actor or original source ledger")
		t.check(facts.all(func(a): return a.settlement_completed) and game._pending_card_actions.is_empty() and game.turn_manager.get_play_actor_key() == 0, "I05b4b PREP retains original virtual USE and parent restores unchanged PLAY owner")
		await Farming.new().dispose(t, game)

func continuous_replacements(t):
	for limited in [false, true]:
		var game = fixture(t)
		var source = game.players[0]
		var owner = game.players[1]
		var leo = game.players[2]
		leo.general_name = "里奥·普利威尔"; leo.prep_tokens = 2
		var original = equip(game)
		var weapon = CardBase.create(CardData.CardSubType.LIANNU)
		source.equip_card_to_slot("weapon", weapon)
		source.hand.append(null)
		game.turn_manager._set_turn_count("duel", 2 if limited else 0, owner.seat_index)
		game._prep_steal_pick_override = func(_choices): return 0
		var steps: Array = []
		game._prep_replace_override = func(_leo, actor, fixed, sub, options):
			if actor != owner: return -1
			steps.append(sub)
			if sub == CardData.CardSubType.DUEL and steps.size() == 1: return CardData.CardSubType.SNATCH
			if sub == CardData.CardSubType.SNATCH:
				t.check(fixed == source and options.has(CardData.CardSubType.DUEL) == not limited, "I05b4b continuous replacement rechecks new Duel quota after prior replacement")
				return -1 if limited else CardData.CardSubType.DUEL
			return -1
		var facts: Array = []
		game.card_action_committed.connect(func(a): facts.append(a))
		await game.execute_card_on_target(owner, CardData.CardSubType.DISMANTLE)
		t.check(steps.size() >= 2 and leo.prep_tokens == (1 if limited else 0) and owner.get_equipment_card("armor") == original, "I05b4b virtual counter can be continuously replaced without resubmitting protected original")
		t.check(owner.determined_cards.has(weapon) == limited and source.get_equipment_card("weapon") == (null if limited else weapon) and source.hp == (4 if limited else 3), "I05b4b final Snatch or new Duel alone resolves, never intermediate effects")
		t.check(game.turn_manager._get_turn_count("duel", owner.seat_index) == (2 if limited else 1) and game.turn_manager._get_turn_count("steal", owner.seat_index) == (1 if limited else 0), "I05b4b replaced-back Duel is new limited card; unchanged original extra bypass does not leak")
		t.check(facts.size() == 2 and facts.all(func(a): return a.settlement_completed) and facts[1].sub_type == CardData.CardSubType.DUEL and facts[1].card.card_name == "决斗", "I05b4b continuous replacements retain original virtual card identity and one USE")
		await Farming.new().dispose(t, game)

func borrowed_replacement(t):
	var game = fixture(t)
	var owner = game.players[1]
	var source = game.players[0]
	var leo = game.players[2]
	leo.general_name = "里奥·普利威尔"; leo.prep_tokens = 1
	var original = equip(game)
	var weapon = CardBase.create(CardData.CardSubType.LIANNU)
	source.equip_card_to_slot("weapon", weapon)
	source.hand.append(null)
	game.turn_manager._set_turn_count("borrowed_sword", 2, source.seat_index)
	game._prep_replace_override = func(_leo, actor, fixed, _sub, options):
		if actor != owner: return -1
		t.check(fixed == source and options.has(CardData.CardSubType.BORROWED_SWORD), "I05b4b virtual user can choose legal Borrow despite PLAY actor exhausting own Borrow quota")
		return CardData.CardSubType.BORROWED_SWORD
	game._borrowed_second_target_override = func(options): return options.find(game.players[4])
	var facts: Array = []
	game.card_action_committed.connect(func(a): facts.append(a))
	await game.execute_card_on_target(owner, CardData.CardSubType.DISMANTLE)
	t.check(owner.get_equipment_card("armor") == original and owner.determined_cards.has(weapon) and source.get_equipment_card("weapon") == null, "I05b4b replacement Borrow fully settles empty-hand refusal and transfers same weapon to actual David user")
	t.check(game.turn_manager._get_turn_count("borrowed_sword", owner.seat_index) == 1 and game.turn_manager._get_turn_count("borrowed_sword", source.seat_index) == 2, "I05b4b replacement Borrow validation and commit both use actual card user")
	t.check(facts.size() == 2 and facts.all(func(a): return a.settlement_completed) and leo.prep_tokens == 0 and game._pending_card_actions.is_empty(), "I05b4b replacement Borrow completes same original virtual Duel USE and retained parent")
	await Farming.new().dispose(t, game)

func paid_equipment_effects(t):
	var game = fixture(t)
	var source = game.players[0]
	var owner = game.players[1]
	source.general_name = "麦克斯·欧尼斯特"
	source.hand.assign([null, null])
	var a = CardBase.create(CardData.CardSubType.LIANNU)
	var b = CardBase.create(CardData.CardSubType.QINGGANG_SWORD)
	var c = equip(game)
	var d = CardBase.create(CardData.CardSubType.ZHANQI)
	owner.equip_card_to_slot("weapon", a)
	game.players[2].equip_card_to_slot("weapon", b)
	game.players[2].equip_card_to_slot("armor", d)
	var zones: Array = ["weapon", "armor", "done"]
	game._lanzhonghou_zone_override = func(): return zones.pop_front()
	game._hand_discard_override = func(snapshot, n, _m): return snapshot.defaults(n)
	await game._run_lanzhonghou(owner, game.players[2])
	t.check(owner.get_equipment_card("weapon") == a and owner.get_equipment_card("armor") == c and game.players[2].get_equipment_card("weapon") == b and game.players[2].get_equipment_card("armor") == d, "I05b4b Q12 real counter Duel leaves all original weapon/armor pairs untouched")
	t.check(source.hp == 3 and source.hand_size() == 0 and game._lanzhonghou_used and owner.wrestle_round == game.turn_manager.rounds.round_id, "I05b4b Q12 whole-skill prevention resolves actual Duel, retains both fees and phase use")
	await Farming.new().dispose(t, game)
	game = fixture(t)
	source = game.players[0]; owner = game.players[1]
	source.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.ICE_SWORD))
	source.hand.append(null); owner.hand.assign([null, null])
	game._ice_sword_override = func(): return true
	var facts: Array = []
	game.card_action_committed.connect(func(a): facts.append(a))
	await game.execute_card_on_target(owner, CardData.CardSubType.STRIKE)
	t.check(owner.hand_size() == 2 and owner.hp == 3 and source.hp == 3 and owner.wrestle_round == game.turn_manager.rounds.round_id, "I05b4b actual Ice entire loss prevented, counter Duel resolves, original Ice has already replaced Strike damage")
	t.check(facts.size() == 2 and facts.all(func(a): return a.settlement_completed) and game._pending_card_actions.is_empty(), "I05b4b Ice nested virtual Duel and original physical Strike both complete once")
	await Farming.new().dispose(t, game)

func death(t):
	for victim in ["source", "owner"]:
		var game = fixture(t)
		var source = game.players[0]
		var owner = game.players[1]
		var card = equip(game)
		source.hand.assign([null] if victim == "source" else [null, null])
		if victim == "source": source.hp = 1
		else:
			owner.hp = 1
			game._duel_respond_override = func(): return true
		var facts: Array = []
		game.card_action_committed.connect(func(a): facts.append(a))
		await game.execute_card_on_target(owner, CardData.CardSubType.DISMANTLE)
		t.check((source.is_dead() if victim == "source" else owner.is_dead()) and facts.size() >= 2, "I05b4b real counter Duel can finalize either participant death")
		t.check(facts[0].settlement_completed and facts[1].settlement_completed and game._pending_card_actions.is_empty(), "I05b4b participant death does not abandon established parent prevention or virtual Duel completion")
		t.check(not source.determined_cards.has(card) and game.deck._discard.count(card) == (1 if victim == "owner" else 0) and game._card_loss_pending.is_empty() and game._wrestling_resolving.is_empty(), "I05b4b protected equipment only leaves by later true death cleanup, never pending original move")
		await Farming.new().dispose(t, game)

func sage_during_counter(t):
	var game = fixture(t)
	var owner = game.players[1]
	var source = game.players[0]
	var armor = CardBase.create(CardData.CardSubType.SAGE_PROTECTION)
	owner.equip_card_to_slot("armor", armor)
	owner.sage_activated = true
	owner.hp = 1
	source.hand.assign([null, null])
	game._duel_respond_override = func(): return true
	game._sage_save_override = func(): return true
	var asks: Array = []
	game._wrestling_choice_override = func(_owner, _valid): asks.append(true); return 1
	var facts: Array = []
	game.card_action_committed.connect(func(a): facts.append(a))
	await game.execute_card_on_target(owner, CardData.CardSubType.DISMANTLE)
	t.check(owner.is_alive() and owner.hp == 4 and owner.hand_size() == 4 and owner.get_equipment_card("armor") == null and game.deck._discard.count(armor) == 1, "I05b4b actual counter damage invokes confirmed Sage, clears original armor once and restores general")
	t.check(asks.size() == 1 and owner.wrestle_round == -1 and game._wrestling_ready(owner), "I05b4b Sage cleanup cannot reopen pending reaction, general reset retained after old counter returns")
	t.check(facts.size() == 3 and facts.all(func(a): return a.settlement_completed) and game._pending_card_actions.is_empty() and game._wrestling_resolving.is_empty(), "I05b4b original prevention, extra Duel and actual Strike response complete across Sage reset")
	await Farming.new().dispose(t, game)

func round_and_restore(t):
	var game = fixture(t)
	var owner = game.players[1]
	var source = game.players[0]
	equip(game)
	await game._steal_equip(source, owner, true, "顺手牵羊")
	t.check(not game._wrestling_ready(owner), "I05b4b same-round second external loss cannot reopen skill")
	var initial = game.turn_manager.rounds.round_id
	# Bookkeeping component boundary: normal quotas, not fabricated extra rounds.
	var ledger = game.turn_manager.rounds
	var live: Array[int] = [0, 1, 2, 3, 4]
	while ledger.round_id == initial:
		ledger.finish()
		ledger.begin_next(live)
	t.check(game._wrestling_ready(owner) and owner.wrestle_round == initial, "I05b4b only actual RoundLedger round change renews availability, not phase/turn count")
	owner.wrestle_round = ledger.round_id
	owner.restore_game_start_state()
	t.check(owner.wrestle_round == -1 and game._wrestling_ready(owner) and ledger.round_id == initial + 1, "I05b4b general reset restores skill state without rewinding global round")
	game.reset_game_over_state()
	t.check(game._card_loss_pending.is_empty() and game._wrestling_resolving.is_empty(), "I05b4b technical restart clears only old execution leases")
	await Farming.new().dispose(t, game)

func forced_minus_mule(t):
	var game = fixture(t)
	var source = game.players[0]
	var owner = game.players[1]
	var mule = CardBase.create(CardData.CardSubType.MULE_MINUS)
	source.equip_card_to_slot(Player.MOUNT_SLOTS[0], mule)
	var originals: Array[CardBase] = []
	for slot in Player.MOUNT_SLOTS:
		var card = CardBase.create(CardData.CardSubType.MOUNT_PLUS)
		owner.equip_card_to_slot(slot, card)
		originals.append(card)
	game._minus_mule_target_override = func(): return owner
	var asks: Array = []
	game._wrestling_choice_override = func(_p, _v): asks.append(true); return 1
	var facts: Array = []
	game.card_action_committed.connect(func(a): facts.append(a))
	var done: Array = []
	var hit = func(): done.append(await game._deal_damage_result(game.players[2], source, 1, EffectChain.DamageType.PHYSICAL))
	hit.call_deferred()
	for i in 3: await t.process_frame
	var buttons: Array = []
	for button in game.get_node("UI").find_children("*", "Button", true, false):
		if button.is_visible_in_tree() and button.text.begins_with(Player.EQUIP_SLOT_NAMES[Player.MOUNT_SLOTS[2]] + "："):
			buttons.append(button)
	t.check(buttons.size() == 1 and game._input_seat == source.seat_index and not game._countdown_active, "I05b Q13 actual damage opens mandatory untimed replacement owned by mule transferor")
	if buttons.size() == 1: buttons[0].pressed.emit()
	else: game._game_over = true # Fail the case without leaving an unanswered test window.
	for i in 5: await t.process_frame
	t.check(done.size() == 1 and source.hp == 3 and source.get_equipment_card(Player.MOUNT_SLOTS[0]) == null, "I05b Q13 actual damage and mule movement complete without reversing original damage")
	t.check(owner.get_equipment_card(Player.MOUNT_SLOTS[2]) == mule and game.deck._discard.count(originals[2]) == 1, "I05b Q13 David must receive original minus mule and discard transferor-selected original horse")
	t.check(owner.get_equipment_card(Player.MOUNT_SLOTS[0]) == originals[0] and owner.get_equipment_card(Player.MOUNT_SLOTS[1]) == originals[1] and owner.get_equipment_card(Player.MOUNT_SLOTS[3]) == originals[3], "I05b Q13 other three original mounts stay in their slots")
	t.check(asks.is_empty() and owner.wrestle_round == -1 and facts.is_empty(), "I05b Q13 no Wrestle response, round spend, virtual Duel or manufactured card USE")
	await Farming.new().dispose(t, game)

func stale(t):
	for mode in ["card", "restore", "restart"]:
		var game = fixture(t)
		var owner = game.players[1]
		var card = equip(game)
		game._wrestling_choice_override = func(_p, valid):
			t.check(valid.call(), "I05b4b optional prompt begins with exact live transaction")
			await t.process_frame
			if mode == "card": owner.hand.append(null)
			elif mode == "restore": owner.restore_game_start_state()
			else: game.reset_game_over_state()
			return 1
		var result = await game._steal_equip(game.players[0], owner, true, "顺手牵羊")
		t.check(result == GameManager.CHOICE_INVALID and owner.wrestle_round == -1 and owner.get_equipment_card("armor") == card and game._pending_card_actions.is_empty(), "I05b4b expired confirmation cannot spend quota, declare Duel or move later cards")
		await Farming.new().dispose(t, game)

func find(b, seat, text):
	for c in b.snapshot(seat).get("controls", []):
		if str(c.get("text", "")).begins_with(text) and not c.get("disabled", false): return c.id
	return ""

func bridge_case(t, owner_seat, mode):
	var b = LanGameBridge.new()
	t.root.add_child(b)
	var roster: Array[Dictionary] = []
	for seat in 3: roster.append({"name": "P%d" % seat, "general": "稻草人"})
	t.check(b.start(roster, GameModes.FREE_FOR_ALL, AiActionPacer.Speed.FAST), "I05b4b real native Bridge starts")
	var game = b.game
	game._halt_countdown()
	game._david_rules_enabled = true
	game._wrestling_rules_enabled = true
	game._duel_respond_override = func(): return false
	game._nullify_override = func(): return false
	game._sacrifice_actor_override = func(_p, _t, _a): return false
	game._equip_pick_override = func(): return "armor"
	for p in game.players: p.hand.clear(); p.determined_cards.clear()
	var owner = game.players[owner_seat]
	var source = game.players[1 - owner_seat]
	owner.general_name = Loss.DAVID
	owner.max_hp = 4; owner.hp = 3; owner.capture_game_start_state()
	var card = CardBase.create(CardData.CardSubType.SILVER_LION)
	owner.equip_card_to_slot("armor", card)
	var before_hp = source.hp
	var result: Array = []
	# Precise external-loss boundary fixture. Normal paid parents are covered
	# above; this host/remote input case is not claimed as natural ENet gameplay.
	var play = func(): result.append(await game._steal_equip(source, owner, true, "顺手牵羊"))
	play.call_deferred()
	for i in 3: await t.process_frame
	var token = find(b, owner_seat, "发动摔角")
	t.check(not token.is_empty() and b.input_owner() == owner_seat and not b.submit(1 - owner_seat, token), "I05b4b actual host/remote optional window rejects wrong-seat command")
	if mode == "accept": t.check(b.submit(owner_seat, token), "I05b4b real Bridge confirmation dispatches skill")
	elif mode == "cancel": t.check(b.submit(owner_seat, find(b, owner_seat, "取消")), "I05b4b real Bridge cancellation dispatches optional refusal")
	elif mode == "timeout": game._countdown_on_timeout.call()
	else: owner.restore_game_start_state()
	for i in 5: await t.process_frame
	t.check(result.size() == 1 and (result[0] == GameManager.CHOICE_INVALID) == (mode == "restore"), "I05b4b actual optional window resolves normal cancellation/timeout separately from restore")
	t.check(owner.get_equipment_card("armor") == (null if mode in ["cancel", "timeout"] else card) and source.hp == before_hp - (1 if mode == "accept" else 0), "I05b4b actual input protects original before complete Duel or resumes original transfer")
	t.check(owner.wrestle_round == (game.turn_manager.rounds.round_id if mode == "accept" else -1) and game._card_loss_pending.is_empty() and not b.submit(owner_seat, token), "I05b4b old/repeated window token cannot spend another round quota")
	game._game_over = true
	b.queue_free()
	for i in 4: await t.process_frame
