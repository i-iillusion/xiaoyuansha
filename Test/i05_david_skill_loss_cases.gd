extends RefCounted
const External = preload("res://Test/i05_david_external_loss_cases.gd")
const Farming = preload("res://Test/i05_david_farming_cases.gd")
const Core = preload("res://Test/i05_david_wrestling_core_cases.gd")

func fixture(t):
	var game = External.new().fixture(t)
	for p in game.players:
		if p != game.players[1]: p.max_hp = 4; p.hp = 4
	game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
	game._set_input_player(game.players[0])
	return game

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	for accept in [false, true]:
		for concrete in [false, true]:
			await zhuangbi(t, accept, concrete)
			await campus(t, accept, concrete)
			await medicine(t, accept, concrete)
	await exclusions(t)
	await lord_penalty(t)
	await denominator(t)
	await counter_resources(t)
	await medicine_source_death(t)
	for kind in ["zhuangbi", "campus", "medicine"]:
		for mode in ["accept", "cancel", "timeout", "restore"]: await bridge_case(t, kind, mode)
	await bridge_case(t, "medicine", "source_death")
	GameManager.selected_players = saved[0]; GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]; GameManager.random_general = saved[3]; GameManager.random_identity = saved[4]

func resource(owner, concrete):
	var card = CardBase.create(CardData.CardSubType.DODGE) if concrete else null
	if concrete: owner.determined_cards.append(card)
	else: owner.hand.append(null)
	return card

func setup_skill(game, kind):
	var source = game.players[0]
	game._paixiong_override = func(): return false
	source.general_name = "史蒂芬·彼特先斯" if kind == "zhuangbi" else "杰基·斯特朗" if kind == "campus" else "克里斯·西弗"
	source.awoken = kind == "zhuangbi"
	if kind == "zhuangbi":
		# Already-awakened Stephen: real base 3, then max-1 and a completed
		# immunity choice. Do not leave a half-entered human awakening pending.
		source.awoken = false
		source.max_hp = 3; source.hp = 3; source.capture_game_start_state()
		source.max_hp = 2; source.hp = 2; source.awoken = true
		source.awaken_effects_applied = true; source.awake_choice = 3
	source.hand.assign([null, null] if kind != "medicine" else [])
	game.players[2].hand.append(null)
	game._zhuangbi_again_override = func(): return false
	game._rps_override = func(p): return GameManager.RPS_ROCK if p == source else GameManager.RPS_SCISSORS
	game._medicine_choice_override = func(_p, _options): return [game.players[1], game.players[2]]
	if kind == "medicine": game.turn_manager.current_phase = TurnManager.Phase.DRAW

func execute(game, kind):
	if kind == "zhuangbi":
		var targets: Array[Player] = [game.players[1], game.players[2]]
		await game._execute_zhuangbi(targets)
	elif kind == "campus": await game._execute_campus_dominator(game.players[0], game.players[1])
	else: return await game._draw_phase_cards(game.players[0])
	return true

func zhuangbi(t, accept, concrete):
	var game = fixture(t)
	setup_skill(game, "zhuangbi")
	var source = game.players[0]; var owner = game.players[1]; var other = game.players[2]
	var original = resource(owner, concrete)
	var asks: Array = []; var punches: Array = []
	game._wrestling_choice_override = func(p, valid):
		asks.append(p)
		t.check(valid.call() and source.hand_size() == 1 and owner.hand_size() == 1, "I05 Q17 after source fee, before David card leaves")
		return 1 if accept else 0
	game._rps_override = func(p): punches.append(p); return GameManager.RPS_ROCK if p == source else GameManager.RPS_SCISSORS
	await execute(game, "zhuangbi")
	t.check(asks == [owner] and source.hand_size() == 1 and other.hand_size() == 0, "I05 Q17 source fee stays paid and other target pays")
	t.check(owner.hand_size() == (1 if accept else 0) and punches.has(owner) == not accept, "I05 Q17 only David exits fee and RPS on confirmed Wrestle")
	t.check(other.hp == 3 and owner.hp == (3 if accept else 2) and source.hp == (1 if accept else 2), "I05 Q17 remaining opponent can succeed, counter hurts real awakened Stephen source only")
	if concrete: t.check(game.deck._discard.count(original) == (0 if accept else 1), "I05 Q17 exact determined original preserved or discarded once")
	t.check(owner.wrestle_round == (game.turn_manager.rounds.round_id if accept else -1) and game._zhuangbi_execution_owner == -1 and game._card_loss_pending.is_empty(), "I05 Q17 quota and original execution released")
	await Farming.new().dispose(t, game)

func campus(t, accept, concrete):
	var game = fixture(t); setup_skill(game, "campus")
	var owner = game.players[1]; var source = game.players[0]
	var original = resource(owner, concrete)
	var punches: Array = []; var asks: Array = []
	game._rps_override = func(p): punches.append(p); return GameManager.RPS_ROCK if p == source else GameManager.RPS_SCISSORS
	game._wrestling_choice_override = func(p, valid): asks.append(p); t.check(valid.call(), "I05 Q18 valid original cost boundary"); return 1 if accept else 0
	await execute(game, "campus")
	t.check(asks == [owner] and punches.is_empty() == accept and source.hand_size() == 1, "I05 Q18 prevented Campus does not run original RPS or refund source")
	t.check(owner.hand_size() == (1 if accept else 0) and owner.hp == 2 and source.hp == 4, "I05 Q18 Jack counter retains Bawang response rules; original effect stopped")
	if concrete: t.check(game.deck._discard.count(original) == (0 if accept else 1), "I05 Q18 protected exact original unchanged")
	t.check(game._campus_execution_owner == -1 and game._card_loss_pending.is_empty(), "I05 Q18 no orphan execution locks")
	await Farming.new().dispose(t, game)

func medicine(t, accept, concrete):
	var game = fixture(t); setup_skill(game, "medicine")
	var source = game.players[0]; var owner = game.players[1]; var other = game.players[2]
	var original = resource(owner, concrete)
	var asks: Array = []
	game._wrestling_choice_override = func(p, valid): asks.append(p); t.check(valid.call() and owner.hand_size() == 1, "I05 Q19 before original transfer"); return 1 if accept else 0
	var completed = await execute(game, "medicine")
	t.check(completed and asks == [owner] and source.hand_size() == (1 if accept else 2) and other.hand_size() == 0, "I05 Q19 other target still transfers and normal draw stays replaced")
	t.check(owner.hand_size() == (1 if accept else 0) and source.hp == (3 if accept else 4), "I05 Q19 only David protected; counter targets Chris")
	if concrete: t.check(owner.determined_cards.has(original) == accept and source.hand.has(original) == not accept and game.deck._discard.count(original) == 0, "I05 Q19 exact concrete transfer remains concrete, no physical discard")
	t.check(game._medicine_pending.is_empty() and game._card_loss_pending.is_empty(), "I05 Q19 leases released")
	await Farming.new().dispose(t, game)

func exclusions(t):
	for armor in [false, true]:
		var game = fixture(t)
		var source = game.players[0]; var owner = game.players[1]
		var slot = "armor" if armor else "weapon"
		var curse = CardBase.create(CardData.CardSubType.CALAMITY_ROBE if armor else CardData.CardSubType.CALAMITY_SWORD)
		var original = CardBase.create(CardData.CardSubType.SILVER_LION if armor else CardData.CardSubType.LIANNU)
		source.equip_card_to_slot(slot, curse); owner.equip_card_to_slot(slot, original)
		game._calamity_target_override = func(): return owner
		game._calamity_robe_target_override = func(): return owner
		var asks: Array = []
		game._wrestling_choice_override = func(p, _v): asks.append(p); return 1
		if armor: await game._try_calamity_robe_transfer(source)
		else: await game._try_calamity_transfer(source)
		t.check(asks.is_empty() and owner.wrestle_round == -1 and source.get_equipment_card(slot) == null and owner.get_equipment_card(slot) == curse, "I05 Q16 forced calamity replacement never offers Wrestle")
		t.check(game.deck._discard.count(original) == 1 and owner.hp == (4 if armor else 3), "I05 Q16 original discarded once with normal Lion heal")
		await Farming.new().dispose(t, game)
	for pay in [false, true]:
		var game = fixture(t)
		var source = game.players[0]; var target = game.players[1]
		source.general_name = "大卫·法米尔"; target.general_name = "史蒂芬·彼特先斯"
		source.hand.append(null); game._paixiong_override = func(): return true
		game._hand_discard_override = func(snapshot, count, _m): return snapshot.defaults(count) if pay else []
		var asks: Array = []
		game._wrestling_choice_override = func(p, _v): asks.append(p); return 1
		var result = await game._try_paixiong_block(target, source)
		t.check(asks.is_empty() and source.wrestle_round == -1 and source.hand_size() == (0 if pay else 1), "I05 Q20 chosen optional cost really paid, never Wrestle")
		t.check(result == (GameManager.PaixiongOutcome.PAID if pay else GameManager.PaixiongOutcome.PREVENTED), "I05 Q20 paid cost lets full damage continue; decline prevents it")
		await Farming.new().dispose(t, game)

func bridge_case(t, kind, mode):
	var bridge = LanGameBridge.new(); t.root.add_child(bridge)
	var roster: Array[Dictionary] = []
	for seat in 5: roster.append({"name": "P%d" % seat, "general": "稻草人", "bot": false})
	t.check(bridge.start(roster, GameModes.FREE_FOR_ALL, AiActionPacer.Speed.FAST), "I05 skills actual Bridge starts")
	var game = bridge.game
	game._halt_countdown(); game._david_rules_enabled = true; game._wrestling_rules_enabled = true
	for p in game.players:
		p.general_name = "稻草人"; p.hand.clear(); p.determined_cards.clear(); p.max_hp = 4; p.hp = 4
	game.players[1].general_name = "大卫·法米尔"; game.players[1].capture_game_start_state()
	game._nullify_override = func(): return false
	game._duel_respond_override = func(): return false
	game._rescue_choice_override = func(_r, _d, _o): return -1
	game._sacrifice_actor_override = func(_p, _t, _a): return false
	game._hand_discard_override = func(snapshot, count, _m): return snapshot.defaults(count)
	setup_skill(game, kind)
	if mode == "source_death": game.players[0].hp = 1
	var original = resource(game.players[1], true)
	var done: Array = []
	var act = func(): await execute(game, kind); done.append(true)
	act.call_deferred()
	for i in 3: await t.process_frame
	var helper = Core.new(); var token = helper.find(bridge, 1, "发动摔角")
	t.check(not token.is_empty() and bridge.input_owner() == 1 and not bridge.submit(0, token), "I05 skills actual remote Wrestle rejects wrong controller")
	if mode in ["accept", "source_death"]: t.check(bridge.submit(1, token), "I05 skills real Bridge confirms")
	elif mode == "cancel": t.check(bridge.submit(1, helper.find(bridge, 1, "取消")), "I05 skills real Bridge declines")
	elif mode == "timeout": game._countdown_on_timeout.call()
	else: game.players[1].restore_game_start_state()
	for i in 5: await t.process_frame
	t.check(done.size() == 1 and game.players[1].determined_cards.has(original) == (mode in ["accept", "source_death", "restore"]), "I05 skills Bridge cancel/timeout/reset preserve correct original")
	t.check(game.players[1].wrestle_round == (game.turn_manager.rounds.round_id if mode in ["accept", "source_death"] else -1) and not bridge.submit(1, token), "I05 skills confirmed quota only, old remote token rejected")
	if mode == "source_death":
		t.check(game.players[0].is_dead() and not game._game_over and game.players[0].hand_size() == 0 and game.players[2].hand_size() == 1, "I05 Q22 remote confirmed counter finalizes Chris, later recipient keeps original and no normal draw")
	t.check(game._card_loss_pending.is_empty() and game._medicine_pending.is_empty() and game._campus_execution_owner == -1 and game._zhuangbi_execution_owner == -1, "I05 skills original and response leases fully released")
	game._game_over = true; bridge.queue_free()
	for i in 4: await t.process_frame

func lord_penalty(t):
	var game = load("res://Test/h02_integration_cases.gd").new().fixture(t, 5, GameModes.CLASSIC)
	game._david_rules_enabled = true; game._wrestling_rules_enabled = true
	game._nullify_override = func(): return false
	game._dodge_override = func(): return false
	game._sacrifice_actor_override = func(_p, _t, _a): return false
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game._set_input_player(game.players[0])
	var source = game.players[0]; var victim = game.players[1]
	source.general_name = "大卫·法米尔"; source.hand.assign([null, null])
	var weapon = CardBase.create(CardData.CardSubType.LIANNU)
	source.equip_card_to_slot("weapon", weapon)
	victim.hp = 1; victim.hand.clear(); victim.determined_cards.clear()
	var asks: Array = []
	game._wrestling_choice_override = func(p, _v): asks.append(p); return 1
	await game.execute_card_on_target(victim, CardData.CardSubType.STRIKE)
	t.check(source.identity == "主公" and victim.identity == "忠臣" and victim.is_dead() and victim.identity_revealed, "I05 Q21 natural five-player lord kills loyalist, final identity revealed")
	t.check(asks.is_empty() and source.wrestle_round == -1 and source.hand_size() == 0 and source.get_weapon() == -1 and game.deck._discard.count(weapon) == 1, "I05 Q21 identity penalty clears real remaining hand and equipment without Wrestle")
	await Farming.new().dispose(t, game)

func denominator(t):
	# One win among three original opponents fails unless David exits.
	for accept in [false, true]:
		var game = fixture(t); setup_skill(game, "zhuangbi")
		var source = game.players[0]; var owner = game.players[1]
		resource(owner, false); game.players[3].hand.append(null)
		game._wrestling_choice_override = func(_p, _v): return 1 if accept else 0
		game._rps_override = func(p): return GameManager.RPS_ROCK if p == source else GameManager.RPS_SCISSORS if p == game.players[2] else GameManager.RPS_PAPER
		var targets: Array[Player] = [owner, game.players[2], game.players[3]]
		await game._execute_zhuangbi(targets)
		t.check(game.players[2].hp == (3 if accept else 4), "I05 Q17 real success denominator excludes Wrestle recipient: one of two succeeds, one of three fails")
		t.check(owner.hand_size() == (1 if accept else 0) and game.players[3].hand_size() == 0 and source.hand_size() == 1, "I05 Q17 source fee and both other fees retained across changed denominator")
		await Farming.new().dispose(t, game)

func counter_resources(t):
	var game = fixture(t); setup_skill(game, "zhuangbi")
	var source = game.players[0]; var owner = game.players[1]
	var original = CardBase.create(CardData.CardSubType.STRIKE)
	owner.determined_cards.append(original)
	game._duel_respond_override = func(): return true
	await execute(game, "zhuangbi")
	t.check(owner.hand_size() == 0 and game.deck._discard.count(original) == 1 and source.hand_size() == 0, "I05 Q17 protected original may be legitimately used as counter Duel response; never restored or discarded twice")
	t.check(game.players[2].hp == 3 and source.hp == 1 and source.max_hp == 2 and source.awake_choice == 3 and owner.wrestle_round == game.turn_manager.rounds.round_id, "I05 Q17 changed counter resources do not revoke committed prevention or remaining opponent; completed awakening does not repeat")
	await Farming.new().dispose(t, game)

	game = fixture(t); setup_skill(game, "medicine")
	source = game.players[0]; owner = game.players[1]
	resource(owner, false)
	var other = game.players[2]; var leo = game.players[3]
	other.hp = 3; leo.general_name = "里奥·普利威尔"; leo.prep_tokens = 1
	game._prep_replace_override = func(_leo, actor, _fixed, _sub, _options): return CardData.CardSubType.HARVEST if actor == owner else -1
	var completed = await execute(game, "medicine")
	t.check(completed and other.hand_size() == 1 and source.hand_size() == 1 and owner.hand_size() == 2, "I05 Q19 counter Harvest changes later hand legitimately; original medicine still takes one current card without normal draw")
	t.check(leo.prep_tokens == 0 and game._medicine_pending.is_empty() and game._card_loss_pending.is_empty(), "I05 Q19 completed counter replacement releases original parent")
	await Farming.new().dispose(t, game)

func medicine_source_death(t):
	for count in [1, 2]:
		for concrete in [false, true]:
			var game = fixture(t); setup_skill(game, "medicine")
			var source = game.players[0]; var owner = game.players[1]; var other = game.players[2]
			source.hp = 1; source.fire_dragon_eggs = 0
			var protected = resource(owner, concrete)
			other.hand.clear()
			var untouched = resource(other, concrete)
			game._medicine_choice_override = func(_p, _options): return [owner] if count == 1 else [owner, other]
			var completed = await game._draw_phase_cards(source)
			t.check(completed and source.is_dead() and not game._game_over, "I05 Q22 source final death ends committed medicine normally, not technical invalidation")
			t.check(source.hand_size() == 0 and owner.hand_size() == 1 and other.hand_size() == 1, "I05 Q22 no later theft or replacement ordinary draw after final source death")
			if concrete:
				t.check(owner.determined_cards.has(protected) and other.determined_cards.has(untouched) and game.deck._discard.count(protected) == 0 and game.deck._discard.count(untouched) == 0, "I05 Q22 original concrete resources stay with both surviving recipients")
			t.check(owner.wrestle_round == game.turn_manager.rounds.round_id and game._medicine_pending.is_empty() and game._card_loss_pending.is_empty() and game._wrestling_resolving.is_empty(), "I05 Q22 prevention remains committed and all parent/counter leases close")
			await Farming.new().dispose(t, game)
