extends RefCounted

func fixture(t):
	var game = load("res://Test/h02_integration_cases.gd").new().fixture(t, 5, GameModes.CLASSIC)
	game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
	game._nullify_override = func(): return false
	game._corruption_rules_enabled = false
	for p in game.players: p.hand.clear(); p.determined_cards.clear()
	game.turn_manager.next_turn()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game.turn_manager.play_actor_idx = 1
	game.players[0].general_name = "麦克斯·欧尼斯特"
	game.players[0].max_hp = 5; game.players[0].hp = 5
	var owner = game.players[1]
	owner.general_name = "辛巴·古德曼"
	owner.simba_good_deeds_enabled = true
	owner.simba_emergency_enabled = true
	owner.simba_tuanfei_enabled = true
	owner.simba_wanci_enabled = true
	owner.simba_lord_skill_enabled = true
	game.players[0].simba_tuanfei_enabled = false
	game.game_mode = GameManager.MODE_CLASSIC_IDENTITY
	var identities = ["主公", "忠臣", "反贼", "反贼", "内奸"]
	for i in 5:
		game.players[i].identity = identities[i]
		game.players[i].identity_revealed = i == 0
		game.players[i].capture_game_start_state()
	game.players[0].hp = 2
	game.lan_enabled = false
	game._simba_deed_choice_override = Callable()
	game._simba_emergency_choice_override = Callable()
	return game

func dispose(t, game):
	await load("res://Test/i05_peter_peach_cases.gd").new().dispose(t, game)

func values_only(value) -> bool:
	if typeof(value) in [TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL]: return false
	if typeof(value) == TYPE_ARRAY:
		for child in value:
			if not values_only(child): return false
	if typeof(value) == TYPE_DICTIONARY:
		for key in value:
			if not values_only(key) or not values_only(value[key]): return false
	return true

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	await active(t)
	await responses(t)
	await stale(t)
	await gifted(t)
	await paced(t)
	await unit_targets(t)
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]

func active(t):
	var game = fixture(t)
	var owner = game.players[1]
	var target = game.players[0]
	var actions: Array = []
	game.card_action_committed.connect(func(a): actions.append(a))
	for i in 3:
		var view = game._ai_observation(owner)
		var choices = game._ai_play_candidates(view)
		var deeds = choices.filter(func(c): return c.get("skill", "") == "good_deed")
		t.check(deeds.size() == 1 and values_only(view) and values_only(deeds), "I05d AI active skill uses pure-value legal candidates even with no hand cards")
		await game._execute_ai_action(deeds[0])
		t.check(owner.hp == 4 - i and target.hp == 3 + i and target.good_deed_marks == i + 1, "I05d AI uses common Good Deed entry with actual HP cost and mark")
	t.check(game._ai_play_candidates(game._ai_observation(owner)).all(func(c): return c.get("skill", "") != "good_deed"), "I05d conservative AI stops when visible ally is no longer injured, without adding a rule limit")
	t.check(owner.hand.is_empty() and actions.is_empty(), "I05d active AI never invents card payments or card-action facts")
	game.lan_enabled = true
	game.turn_manager.current_player_idx = 1; game.turn_manager.play_actor_idx = 1
	game.players[2].hp = 3
	game._simba_deed_choice_override = func(_p, candidates, _r, _v): return candidates.find(game.players[2])
	t.check(await game._perform_good_deed(owner) == 1 and game.players[2].hp == 4, "I05d human common entry remains legal where optional AI policy would decline")
	await dispose(t, game)

func responses(t):
	var game = fixture(t)
	var owner = game.players[1]
	var target = game.players[0]
	target.hp = 1
	var result = await game._deal_damage_result(game.players[2], target, 1, EffectChain.DamageType.PHYSICAL)
	t.check(not result.invalidated and target.hp == 1 and target.good_deed_marks == 1 and owner.hp == 4 and game._choice_prompt_stack.is_empty(), "I05d AI Emergency rescues visible ally through actual damage common entry")
	await game._deal_damage_result(game.players[2], owner, 1, EffectChain.DamageType.PHYSICAL)
	t.check(owner.hp == 3 and owner.good_deed_marks == 1, "I05d AI own Emergency keeps original damage loss, net cost/grant zero")
	owner.hp = 1
	t.check(await game._choose_ai_response(owner, "simba_emergency", [0], {"target": 0}) == -1, "I05d conservative AI declines lethal help to others as strategy only")
	await dispose(t, game)
	game = fixture(t); owner = game.players[1]
	owner.simba_emergency_enabled = false
	owner.hp = 0
	game.players[2].good_deed_marks = 2
	t.check(await game._resolve_dying(owner, null, "test") == 0 and owner.hp == 2 and game.players[2].hp == 3 and game.players[2].good_deed_marks == 0, "I05d AI reclaims all legal enemy markers before ordinary rescue using common flow")
	await dispose(t, game)
	for kind in ["simba_emergency", "simba_reclaim"]:
		game = fixture(t); owner = game.players[1]
		var seen: Array = []
		game._ai_response_override = func(view, actual, options):
			t.check(values_only(view) and values_only(options) and view.players.filter(func(p): return p.seat == 2)[0].identity == "", "I05d Simba response chooser sees value-only snapshots and no hidden enemy identity")
			seen.append(actual)
			return GameManager.CHOICE_INVALID
		if kind == "simba_emergency":
			var outcome = await game._deal_damage_result(game.players[2], game.players[0], 1, EffectChain.DamageType.PHYSICAL)
			t.check(outcome.invalidated and owner.hp == 5 and game.players[0].good_deed_marks == 0, "I05d AI technical Emergency failure is not normalized to ordinary decline")
		else:
			owner.hp = 0; game.players[2].good_deed_marks = 2
			t.check(await game._resolve_dying(owner, null, "test") == GameManager.CHOICE_INVALID and owner.is_dying() and game.players[2].good_deed_marks == 2, "I05d AI technical reclaim failure does not proceed to false death or consume markers")
		t.check(seen == [kind], "I05d correct Simba response kind reaches injected value policy")
		await dispose(t, game)

func stale(t):
	for mode in ["owner_hp", "owner_reset", "target_hp", "target_reset", "target_marks", "capability", "lifecycle", "phase"]:
		var game = fixture(t)
		var owner = game.players[1]
		var target = game.players[0]
		var deeds = game._ai_play_candidates(game._ai_observation(owner)).filter(func(c): return c.get("skill", "") == "good_deed")
		t.check(deeds.size() == 1, "I05d legal initial AI skill candidate before simulated presentation wait")
		match mode:
			"owner_hp": owner.hp = 4
			"owner_reset": owner.restore_game_start_state()
			"target_hp": target.hp = 3
			"target_reset": target.restore_game_start_state()
			"target_marks": target.good_deed_marks = 1
			"capability": owner.simba_good_deeds_enabled = false
			"lifecycle": game._dying_lifecycle_generation += 1
			"phase": game.turn_manager._context_revision += 1
		var hp = owner.hp
		var target_hp = target.hp
		var marks = target.good_deed_marks
		await game._execute_ai_action(deeds[0])
		t.check(owner.hp == hp and target.hp == target_hp and target.good_deed_marks == marks, "I05d stale AI Good Deed action cannot pay after wait: " + mode)
		await dispose(t, game)

func gifted(t):
	var game = fixture(t)
	var owner = game.players[1]
	var tm = game.turn_manager
	tm.current_player_idx = 0
	tm.current_phase = TurnManager.Phase.START
	var frame = tm.begin_standalone_phase(1, TurnManager.Phase.PLAY)
	var choices = game._ai_play_candidates(game._ai_observation(owner)).filter(func(c): return c.get("skill", "") == "good_deed")
	t.check(not frame.is_empty() and choices.size() == 1, "I05d AI has same legal Good Deed entry in authorized gifted PLAY frame")
	await game._execute_ai_action(choices[0])
	t.check(owner.hp == 4 and game.players[0].hp == 3 and tm.complete_standalone_phase(frame), "I05d gifted AI skill commits and returns original source frame")
	await dispose(t, game)

func paced(t):
	for mode in ["normal", "restore", "target", "space", "end"]:
		var game = fixture(t)
		var owner = game.players[1]
		var target = game.players[0]
		var calls: Array = []
		game.ai_pacer.speed = AiActionPacer.Speed.STANDARD
		game.ai_pacer.wait_override = func(seconds):
			calls.append(seconds)
			if calls.size() == 1:
				match mode:
					"restore": owner.restore_game_start_state()
					"target": target.hp = target.max_hp
					"space":
						game.players[4].general_name = "吉姆·芒顿"
						game.players[4].max_hp = 6; game.players[4].hp = 6
						game._spawn_mountain_at(game.players[4], 0, 1)
						game._spawn_mountain_at(game.players[4], 3, 4)
					"end": game._game_over = true
			await t.process_frame
		game.ai_driver.chooser = func(_view, options):
			if owner.hp < 5: return -1
			for i in options.size():
				if options[i].get("skill", "") == "good_deed": return i
			return -1
		var before = owner.awakening_revision
		await game._run_ai_play(owner)
		for i in 3: await t.process_frame
		var paid = mode in ["normal", "restore"]
		t.check(owner.hp == (4 if paid else 5) and target.good_deed_marks == (1 if paid else 0), "I05d actual AI presentation gate never pays stale skill: " + mode)
		t.check(calls == ([0.6, 0.6] if mode == "restore" else [0.6]), "I05d restored candidate requires a fresh normal pace instead of executing old decision: " + mode)
		t.check(owner.awakening_revision == before + (1 if mode == "restore" else 0) and game._simba_deed_pending.is_empty() and game._ai_running_revisions.is_empty(), "I05d AI restoration/wait leaves no stalled skill or AI lease: " + mode)
		t.check(game.turn_manager.current_phase == (TurnManager.Phase.PLAY if mode == "end" else TurnManager.Phase.DISCARD), "I05d actual AI ends valid phase once, never advances after terminal wait: " + mode)
		await dispose(t, game)

func unit_targets(t):
	var game = fixture(t)
	var owner = game.players[1]
	var chris = game.players[0]
	chris.general_name = "克里斯·西弗"; chris.max_hp = 4; chris.hp = 4; chris.capture_game_start_state()
	var dragon = load("res://Test/i03_summon_cases.gd").new().seed_dragon(game, chris)
	var id = game.unit_registry.id_for(dragon)
	dragon.hp = 2; dragon.hand.append(null)
	t.check(game._ai_play_candidates(game._ai_observation(owner)).all(func(c): return c.get("skill", "") != "good_deed"), "I05d AI cannot propose healing allied unit it cannot legally see")
	var audience: Array[Player] = [owner]
	t.check(game.fire_dragon_state.record_use(id, 1, audience), "I05d registered dragon now has an authorized revealing-use fact for AI actor")
	var view = game._ai_observation(owner)
	var row = view.units.filter(func(u): return u.id == id)[0]
	t.check(row.own_cards.is_empty() and values_only(view), "I05d allied controller identity does not expose dragon hand instances to Simba AI")
	var options = game._ai_play_candidates(view).filter(func(c): return c.get("skill", "") == "good_deed")
	t.check(options.size() == 1, "I05d pure-value strategy supports legal unit IDs without coercing them to player seats")
	await game._execute_ai_action(options[0])
	t.check(owner.hp == 4 and dragon.hp == 3 and dragon.good_deed_marks == 1 and chris.hp == 4 and chris.good_deed_marks == 0, "I05d AI grants legal actual dragon body through common Good Deed entry, not controller")
	await dispose(t, game)
