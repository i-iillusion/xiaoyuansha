extends RefCounted

const GLOBALS = [CardData.CardSubType.PEACH_GARDEN,CardData.CardSubType.HARVEST,CardData.CardSubType.DISARM]

# Reuse only the unchanged board in native matrix cases. Restore all state
# touched by the preceding case; each payment/effect/counter still runs in full.
# LAN cases below keep independent bridges and real selectors/tweens.
func reset_fixture(game):
	for p in game.players:
		for slot in p.get_equip_slots(): p.remove_equipment(slot)
		p.chained = false
	game._clear_pending_determined_card()
	game.turn_manager._reset_turn_counts()
	game._card_action_serial = 0
	game.action_history.reset("i04-global-native-matrix")
	game.deck._discard.clear()

func configure(game, sub, concrete := false):
	game._halt_countdown()
	game._nullify_override = func(): return false
	game._ai_response_override = func(_view,_kind,_options): return -1
	for p in game.players:
		p.hand.clear(); p.determined_cards.clear(); p.hp = p.max_hp-1
	var original = CardBase.create(sub) if concrete else null
	if concrete:
		game.players[0].determined_cards.append(original)
		game._pending_determined_card = original
	else: game.players[0].hand.append(null)
	if sub == CardData.CardSubType.DISARM:
		game.players[0].equip_card_to_slot("armor",CardBase.create(CardData.CardSubType.BAGUA_ZHEN))
		game.players[1].equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.LIANNU))
		game.players[2].equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.ZHUGE_LIANNU))
	return original

func play(game,sub):
	match sub:
		CardData.CardSubType.PEACH_GARDEN: await game._play_peach_garden()
		CardData.CardSubType.HARVEST: await game._play_harvest()
		CardData.CardSubType.DISARM: await game._play_disarm()
		CardData.CardSubType.IRON_CHAIN:
			var pair: Array[Player] = [game.players[0],game.players[1]]
			await game._execute_iron_chain(pair)

func check_effect(t,game,sub):
	var a = game.players[0]
	var b = game.players[1]
	var c = game.players[2]
	match sub:
		CardData.CardSubType.PEACH_GARDEN:
			t.check(a.hp == a.max_hp and b.hp == b.max_hp and c.hp == c.max_hp-1, "I04 Peach Garden heals self and same region only")
		CardData.CardSubType.HARVEST:
			t.check(a.hand_size() == 1 and b.hand_size() == 1 and c.hand_size() == 0, "I04 Harvest draws ordinary blank hands in own region only")
		CardData.CardSubType.DISARM:
			t.check(a.get_equip_slots().is_empty() and b.get_equip_slots().is_empty() and c.get_weapon() == CardData.CardSubType.ZHUGE_LIANNU, "I04 Disarm preserves equipment beyond the mountains")
			t.check(a.hand_size() == 1 and b.hand_size() == 1 and c.hand_size() == 0, "I04 Disarm only draws for equipment actually removed in own region")
	t.check(game.players.slice(3).all(func(p): return p.hp == p.max_hp-1 and p.hand_size() == 0), "I04 far region receives no global heal or draw")
	t.check(game._pending_card_actions.is_empty() and game._card_action_serial == 1, "I04 global effect pays one physical use and completes its parent card")
	var declared = game.action_history.entries.filter(func(entry): return entry.kind == "targets")
	t.check(not declared.is_empty() and declared.back().targets.size() == 5, "I04 effective global region does not shrink its original five-character declaration")

func dispose(t,game):
	game._game_over = true
	game.queue_free()
	await t.process_frame

func run(t):
	var saved = [GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	var game = load("res://Test/i04_declaration_cases.gd").new().fixture(t)
	for sub in GLOBALS:
		for concrete in [false,true]:
			reset_fixture(game)
			var original = configure(game,sub,concrete)
			t.check(game._pending_card_actions.is_empty() and game._card_action_serial == 0 and game.turn_manager.current_phase == TurnManager.Phase.PLAY and game.players[0].hand_size() == 1 and game.players[1].hand_size() == 0, "I04 native matrix resets original payment and phase preconditions for every case")
			await play(game,sub)
			check_effect(t,game,sub)
			if concrete: t.check(game.deck._discard.count(original) == 1, "I04 concrete global payment preserves and discards its original instance once")
	await dispose(t,game)
	# Technical await-boundary injection, not an upstream authorized movement skill.
	for sub in GLOBALS + [CardData.CardSubType.IRON_CHAIN]:
		game = load("res://Test/i04_declaration_cases.gd").new().fixture(t)
		configure(game,sub)
		var calls: Array = [0,false]
		game._nullify_override = func():
			calls[0] += 1
			if calls[0] == 2: calls[1] = game.mountain_space.relocate_before(1,2)
			return false
		await play(game,sub)
		t.check(calls[1] and not game._mountain_effect_reaches(game.players[0],game.players[1]), "I04 injected B movement crosses wall during B's counter window")
		var b = game.players[1]
		match sub:
			CardData.CardSubType.PEACH_GARDEN: t.check(b.hp == b.max_hp-1, "I04 Peach Garden rechecks region after counter await")
			CardData.CardSubType.HARVEST: t.check(b.hand_size() == 0, "I04 Harvest rechecks region after counter await")
			CardData.CardSubType.DISARM: t.check(b.get_weapon() == CardData.CardSubType.LIANNU and b.hand_size() == 0, "I04 Disarm rechecks region before loss and replacement draw")
			CardData.CardSubType.IRON_CHAIN: t.check(game.players[0].chained and not b.chained, "I04 paid two-target Iron Chain retains first effect but blocks newly separated second effect")
		t.check(game._pending_card_actions.is_empty() and game._card_action_serial == 1, "I04 post-payment barrier finishes original card without refund or duplicate use")
		await dispose(t,game)
	await retired_target(t)
	await lan(t)
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]

func retired_target(t):
	var game = load("res://Test/i04_declaration_cases.gd").new().fixture(t)
	for sub in GLOBALS + [CardData.CardSubType.IRON_CHAIN]:
		reset_fixture(game)
		configure(game,sub)
		# Membership fault injection only: not an upstream summon/death scenario.
		# Retain sentinel state on the tombstone to detect any late mutation.
		var dragon = FireDragonState.create_body()
		var id = game._register_unit_body(UnitRegistry.Kind.FIRE_DRAGON,dragon,game.players[1])
		var seen: Array[Player] = [game.players[0]]
		t.check(game.fire_dragon_state.attach(id) and game.fire_dragon_state.record_use(id,1,seen), "I04 retired-target fixture starts with a valid revealed empty dragon")
		dragon.hp = 2
		var weapon = CardBase.create(CardData.CardSubType.QINGLONG_BLADE)
		dragon.equip_card_to_slot("weapon",weapon)
		var calls: Array = [0,false]
		game._nullify_override = func():
			calls[0] += 1
			if calls[0] == (2 if sub == CardData.CardSubType.IRON_CHAIN else 3):
				game.unit_registry._retire(id,UnitRegistry.Removal.SUMMONER_LOST)
				dragon.unit_disappeared = true
				calls[1] = true
			return false
		if sub == CardData.CardSubType.IRON_CHAIN:
			var pair: Array[Player] = [game.players[0],dragon]
			await game._execute_iron_chain(pair)
		else: await play(game,sub)
		t.check(calls[1] and not game._has_character_body(dragon) and dragon.is_alive(), "I04 a disappeared retained body is invalid even with positive HP after response await")
		t.check(dragon.hp == 2 and dragon.hand_size() == 0 and not dragon.chained and dragon.get_equipment_card("weapon") == weapon, "I04 late global/Iron continuation cannot heal, draw, chain or strip a removed target")
		t.check(game._pending_card_actions.is_empty() and game._card_action_serial == 1, "I04 skipping removed target completes the original payment exactly once")
	await dispose(t,game)

func lan(t):
	var helper = load("res://Test/i04_aoe_region_cases.gd").new()
	for sub in GLOBALS:
		var bridge = helper.bridge_fixture(t)
		helper.click(t,bridge,0,"山甲 玩家2→玩家3；山乙 玩家5→玩家1")
		var game = bridge.game
		configure(game,sub)
		helper.click(t,bridge,0,"出牌")
		helper.click(t,bridge,0,"锦囊牌")
		helper.click(t,bridge,0,"普通锦囊")
		var token = helper.click(t,bridge,0,CardData.get_type_name(sub))
		await t.create_timer(0.15).timeout
		for i in 3: await t.process_frame
		check_effect(t,game,sub)
		t.check(not bridge.submit(0,token) and bridge.input_owner() == 0 and game.turn_manager.current_phase == TurnManager.Phase.PLAY, "I04 actual global LAN command completes in original PLAY and rejects token replay")
		var end = load("res://Test/i04_movement_cases.gd").new().find(bridge.snapshot(0),"结束出牌")
		t.check(end != "" and not bridge.submit(4,end) and bridge.snapshot(4).controls.is_empty(), "I04 last empty-hand counter responder cannot own the caller's PLAY controls")
		game._game_over = true
		bridge.queue_free()
		await t.process_frame
