extends RefCounted
const Core = preload("res://Test/i05_david_wrestling_core_cases.gd")
const Farming = preload("res://Test/i05_david_farming_cases.gd")
const DAVID = "大卫·法米尔"

func fixture(t):
	var game = Core.new().fixture(t)
	game._borrowed_second_target_override = func(options): return options.find(game.players[2])
	game._chixiong_activate_override = func(): return true
	game._chixiong_target_override = func(): return true
	game._hand_discard_override = func(snapshot, count, _mandatory): return snapshot.defaults(count)
	game._gou_lian_slot_override = func(): return Player.MOUNT_SLOTS[0]
	return game

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	await borrowed(t)
	await chixiong(t)
	await claw(t)
	await q15_original_timeline(t)
	await clashes(t)
	for kind in ["borrowed", "chixiong", "claw"]:
		for mode in ["accept", "cancel", "timeout", "restore"]: await bridge_case(t, kind, mode)
	GameManager.selected_players = saved[0]; GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]; GameManager.random_general = saved[3]; GameManager.random_identity = saved[4]

func borrowed(t):
	for mode in ["accept", "cancel", "flag", "source_death", "owner_death", "stale"]:
		for concrete in [false, true]:
			var game = fixture(t)
			var source = game.players[0]
			var owner = game.players[1]
			var weapon = CardBase.create(CardData.CardSubType.LIANNU)
			owner.equip_card_to_slot("weapon", weapon)
			var parent = CardBase.create(CardData.CardSubType.BORROWED_SWORD) if concrete else null
			if concrete: source.determined_cards.append(parent); game._pending_determined_card = parent
			else: source.hand.append(null)
			if mode == "source_death": source.hp = 1
			elif mode == "owner_death":
				owner.hp = 1
				source.hand.append(null)
				game._duel_respond_override = func(): return true
			elif mode == "flag": source.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.ZHANQI))
			var asks: Array = []
			game._wrestling_choice_override = func(p, valid):
				asks.append(p)
				t.check(p == owner and valid.call() and owner.get_equipment_card("weapon") == weapon and source.hand_size() == (1 if mode == "owner_death" else 0), "I05b external Borrow asks after parent payment and refusal, before weapon leaves")
				if mode == "stale": owner.awakening_revision += 1
				return 0 if mode == "cancel" else 1
			var facts: Array = []
			game.card_action_committed.connect(func(a): facts.append(a))
			await game.execute_card_on_target(owner, CardData.CardSubType.BORROWED_SWORD)
			t.check(asks == [owner] and facts[0].settlement_completed == (mode != "stale") and game.turn_manager._get_turn_count("borrowed_sword", 0) == 1, "I05b external Borrow retains paid parent and quota, distinguishes invalidation")
			t.check(owner.get_equipment_card("weapon") == (null if mode in ["cancel", "owner_death"] else weapon) and source.determined_cards.has(weapon) == (mode == "cancel"), "I05b external Borrow prevention never transfers protected original weapon")
			t.check(game.deck._discard.count(weapon) == (1 if mode == "owner_death" else 0) and game._pending_card_actions.is_empty(), "I05b external Borrow only later final death discards protected weapon, no dangling parent")
			t.check((source.is_dead() if mode == "source_death" else owner.is_dead() if mode == "owner_death" else source.is_alive() and owner.is_alive()), "I05b external Borrow counter can finalize either body without replaying transfer")
			if concrete: t.check(facts[0].card == parent and game.deck._discard.count(parent) == 1, "I05b external Borrow keeps exact concrete parent once")
			t.check(facts.size() == (1 if mode in ["cancel", "flag", "stale"] else 3 if mode == "owner_death" else 2), "I05b external Borrow has only real parent, authorized virtual Duel and actual response facts")
			await Farming.new().dispose(t, game)

func chixiong(t):
	for mode in ["accept", "cancel", "draw", "source_death", "weapon_taken", "stale"]:
		var game = fixture(t)
		var source = game.players[0]
		var owner = game.players[1]
		source.gender = "female"; owner.gender = "male"
		source.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.CHIXIONG_SHUANGGU))
		source.hand.append(null)
		var original = CardBase.create(CardData.CardSubType.DODGE)
		owner.determined_cards.append(original)
		if mode == "source_death": source.hp = 1
		if mode == "draw": game._chixiong_target_override = func(): return false
		var asks: Array = []
		game._wrestling_choice_override = func(p, valid):
			asks.append(p)
			t.check(valid.call() and owner.determined_cards.has(original), "I05b external Chixiong chosen original is still in hand at reaction")
			if mode == "stale": owner.awakening_revision += 1
			return 0 if mode == "cancel" else 1
		if mode == "weapon_taken":
			var leo = game.players[2]
			leo.general_name = "里奥·普利威尔"; leo.prep_tokens = 1
			game._prep_replace_override = func(_leo, actor, _fixed, _sub, _options): return CardData.CardSubType.SNATCH if actor == owner else -1
			game._prep_steal_pick_override = func(_options): return 0
		var facts: Array = []
		game.card_action_committed.connect(func(a): facts.append(a))
		await game.execute_card_on_target(owner, CardData.CardSubType.STRIKE)
		t.check(asks.size() == (0 if mode == "draw" else 1) and owner.hp == (3 if mode == "stale" else 2), "I05b external Chixiong prevents only weapon loss effect, original Strike still resolves including source death")
		t.check(owner.determined_cards.has(original) == (mode != "cancel") and game.deck._discard.count(original) == (1 if mode == "cancel" else 0), "I05b external Chixiong original hand card discarded only on normal chosen loss")
		t.check(source.hand_size() == (1 if mode == "draw" else 0) and facts[0].settlement_completed == (mode != "stale"), "I05b external Chixiong prevention never invokes fallback draw, parent cost remains paid")
		t.check(source.is_dead() == (mode == "source_death") and game._pending_card_actions.is_empty(), "I05b external Chixiong source death leaves original Strike as retained-source settlement")
		if mode == "weapon_taken": t.check(source.get_weapon() == -1 and owner.hand_size() == 2 and game.players[2].prep_tokens == 0, "I05b external Chixiong counter replacement can take original sword without invalidating paid Strike")
		await Farming.new().dispose(t, game)

func claw(t):
	for mode in ["accept", "cancel", "source_death", "stale"]:
		var game = fixture(t)
		var source = game.players[0]
		var owner = game.players[1]
		source.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.GOU_LIAN_CLAW))
		source.hand.append(null)
		var horse = CardBase.create(CardData.CardSubType.MOUNT_MINUS)
		owner.equip_card_to_slot(Player.MOUNT_SLOTS[0], horse)
		if mode == "source_death": source.hp = 1
		var asks: Array = []
		game._wrestling_choice_override = func(p, valid):
			asks.append(p)
			t.check(valid.call() and owner.hp == 2 and owner.get_equipment_card(Player.MOUNT_SLOTS[0]) == horse, "I05b external Claw reaction follows committed damage and selected original mount")
			if mode == "stale": owner.awakening_revision += 1
			return 0 if mode == "cancel" else 1
		var facts: Array = []
		game.card_action_committed.connect(func(a): facts.append(a))
		await game.execute_card_on_target(owner, CardData.CardSubType.STRIKE)
		t.check(asks == [owner] and owner.hp == 2 and owner.get_equipment_card(Player.MOUNT_SLOTS[0]) == (null if mode == "cancel" else horse), "I05b external Claw prevention keeps mount without reversing original damage")
		t.check(source.determined_cards.has(horse) == (mode == "cancel") and not game.deck._discard.has(horse) and source.is_dead() == (mode == "source_death"), "I05b external Claw counter source death never moves or duplicates original mount")
		t.check(facts[0].settlement_completed == (mode != "stale") and game._pending_card_actions.is_empty(), "I05b external Claw resumes paid parent or records genuine technical invalidation")
		await Farming.new().dispose(t, game)

func q15_original_timeline(t):
	var game = fixture(t)
	var owner = game.players[0]; var other = game.players[1]
	owner.general_name = DAVID; owner.capture_game_start_state()
	other.general_name = "稻草人"; other.hp = 4
	owner.hand.assign([null, null]); other.hand.assign([null])
	var horse = CardBase.create(CardData.CardSubType.MOUNT_PLUS)
	owner.equip_card_to_slot(Player.MOUNT_SLOTS[0], horse)
	other.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.GOU_LIAN_CLAW))
	var responses: Array = []
	game._duel_respond_override = func(): responses.append(true); return responses.size() == 1
	var facts: Array = []
	game.card_action_committed.connect(func(a): facts.append(a))
	await game.execute_card_on_target(other, CardData.CardSubType.DUEL)
	t.check(owner.hp == 3 and other.hp == 3 and owner.get_equipment_card(Player.MOUNT_SLOTS[0]) == horse and owner.wrestle_round == game.turn_manager.rounds.round_id, "I05b Q15 original first Duel loses to Claw, real Wrestle keeps mount and counter damages opponent")
	t.check(game.turn_manager.duel_count_this_turn == 1 and owner.hand_size() == 1 and game.can_declare_trick(owner, CardData.CardSubType.DUEL), "I05b Q15 returns to actual own PLAY with second normal Duel still legal")
	await game.execute_card_on_target(other, CardData.CardSubType.DUEL)
	t.check(game.turn_manager.duel_count_this_turn == 2 and owner.hand_size() == 0 and other.hp == 2 and owner.farm_hand_actions == 2 and owner.farm_empty_fields == 1, "I05b Q15 actual second normal Duel pays second hand card and farms exactly once")
	t.check(facts.size() == 4 and facts.all(func(a): return a.settlement_completed) and facts.filter(func(a): return a.is_virtual).size() == 1, "I05b Q15 original complete legal timeline has one virtual extra and two paid normal Duels")
	await Farming.new().dispose(t, game)

func clashes(t):
	for sword in [CardData.CardSubType.ICE_SWORD, CardData.CardSubType.QINGGANG_SWORD]:
		for owner_seat in [0, 1]:
			var game = fixture(t)
			for p in game.players: p.general_name = "稻草人"
			var owner = game.players[owner_seat]; owner.general_name = DAVID; owner.capture_game_start_state()
			var source = game.players[0]; var target = game.players[1]
			var weapon = CardBase.create(sword)
			var armor = CardBase.create(CardData.CardSubType.LIEHUO_SHIELD if sword == CardData.CardSubType.ICE_SWORD else CardData.CardSubType.QINGGANG_SHIELD)
			source.equip_card_to_slot("weapon", weapon); target.equip_card_to_slot("armor", armor)
			source.hand.append(null); target.hand.append(null)
			var asks: Array = []
			game._wrestling_choice_override = func(_p, _v): asks.append(true); return 1
			var facts: Array = []
			game.card_action_committed.connect(func(a): facts.append(a))
			await game.execute_card_on_target(target, CardData.CardSubType.STRIKE)
			t.check(source.get_equipment_card("weapon") == null and target.get_equipment_card("armor") == null and game.deck._discard.count(weapon) == 1 and game.deck._discard.count(armor) == 1, "I05b Q14 both original sword and shield discard exactly once in either David direction")
			t.check(asks.is_empty() and owner.wrestle_round == -1 and facts.size() == 1 and not facts[0].is_virtual, "I05b Q14 equipment clash priority forbids Wrestle, round spend and extra Duel USE")
			t.check(target.hp == 2 and target.hand_size() == 1 and facts[0].settlement_completed, "I05b Q14 original Strike continues after clash, removed Ice never discards target hand")
			await Farming.new().dispose(t, game)

func bridge_case(t, kind, mode):
	var b = LanGameBridge.new(); t.root.add_child(b)
	var roster: Array[Dictionary] = []
	for seat in 3: roster.append({"name": "P%d" % seat, "general": "稻草人"})
	t.check(b.start(roster, GameModes.FREE_FOR_ALL, AiActionPacer.Speed.FAST), "I05b external native Bridge starts")
	var game = b.game; game._halt_countdown()
	for p in game.players: p.hand.clear(); p.determined_cards.clear()
	game._david_rules_enabled = true; game._wrestling_rules_enabled = true
	game._nullify_override = func(): return false
	game._duel_respond_override = func(): return false
	game._dodge_override = func(): return false
	game._sacrifice_actor_override = func(_p, _t, _a): return false
	game._chixiong_activate_override = func(): return true
	game._chixiong_target_override = func(): return true
	game._hand_discard_override = func(snapshot, n, _m): return snapshot.defaults(n)
	game._gou_lian_slot_override = func(): return Player.MOUNT_SLOTS[0]
	game._borrowed_second_target_override = func(options): return options.find(game.players[2])
	var source = game.players[0]; var owner = game.players[1]
	owner.general_name = DAVID; owner.max_hp = 4; owner.hp = 3; owner.capture_game_start_state()
	source.max_hp = 4; source.hp = 4; source.hand.append(null)
	var resource: CardBase
	if kind == "borrowed": resource = CardBase.create(CardData.CardSubType.LIANNU); owner.equip_card_to_slot("weapon", resource)
	elif kind == "chixiong":
		resource = CardBase.create(CardData.CardSubType.DODGE); owner.determined_cards.append(resource)
		source.gender = "female"; owner.gender = "male"
		source.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.CHIXIONG_SHUANGGU))
	else:
		resource = CardBase.create(CardData.CardSubType.MOUNT_MINUS); owner.equip_card_to_slot(Player.MOUNT_SLOTS[0], resource)
		source.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.GOU_LIAN_CLAW))
	var done: Array = []
	var act = func(): await game.execute_card_on_target(owner, CardData.CardSubType.BORROWED_SWORD if kind == "borrowed" else CardData.CardSubType.STRIKE); done.append(true)
	act.call_deferred()
	for i in 3: await t.process_frame
	var helper = Core.new()
	var token = helper.find(b, 1, "发动摔角")
	t.check(not token.is_empty() and b.input_owner() == 1 and not b.submit(0, token), "I05b external paid parent offers real remote reaction and rejects wrong controller")
	if mode == "accept": t.check(b.submit(1, token), "I05b external actual Bridge confirms prevention")
	elif mode == "cancel": t.check(b.submit(1, helper.find(b, 1, "取消")), "I05b external actual Bridge declines optional prevention")
	elif mode == "timeout": game._countdown_on_timeout.call()
	else: owner.restore_game_start_state()
	for i in 5: await t.process_frame
	var retained = owner.determined_cards.has(resource) if kind == "chixiong" else owner.get_equipment_card("weapon" if kind == "borrowed" else Player.MOUNT_SLOTS[0]) == resource
	t.check(done.size() == 1 and retained == (mode in ["accept", "restore"]), "I05b external native confirmation, cancellation, timeout and reset control original resource only")
	t.check(owner.wrestle_round == (game.turn_manager.rounds.round_id if mode == "accept" else -1) and source.hp == (3 if mode == "accept" else 4), "I05b external native response spends quota and damages real effect source only after confirmation")
	t.check(game._pending_card_actions.is_empty() and game._card_loss_pending.is_empty() and not b.submit(1, token), "I05b external native parent settles or invalidates once, releases leases and rejects old token")
	game._game_over = true; b.queue_free()
	for i in 4: await t.process_frame
