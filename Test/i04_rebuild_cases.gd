extends RefCounted

func fixture(t, amount := 1):
	var game = load("res://Test/i04_initial_cases.gd").new().fixture(t,5,true,func(_p,_o,_v): return 0)
	game._halt_countdown()
	game._sacrifice_actor_override = func(_p,_target,_amount): return false
	var mountains = game.unit_registry.active_units()
	for index in amount: mountains[index].hp = 1
	if amount == 2:
		game.players[0].equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.FANGTIAN_HALBERD))
		await game.execute_multi_strike(mountains,CardData.CardSubType.STRIKE)
	else: await game.execute_card_on_target(mountains[0],CardData.CardSubType.STRIKE)
	return game

func dispose(t, game):
	game._game_over = true
	game.queue_free()
	await t.process_frame

func run(t):
	var saved = [GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for amount in [1,2]:
		for timeout in [false,true]:
			var game = await fixture(t,amount)
			var owner = game.players[0]
			var survivors = game.unit_registry.active_units().map(func(body): return game.unit_registry.id_for(body))
			var serial = game._card_action_serial
			game._jim_rebuild_choice_override = func(_p,options,_v): return -1 if timeout else options.size()-1
			# Seed the next ordinary START. Real _do_start then performs mandatory
			# rebuilding before JUDGE/DRAW; this is not a whole-round playthrough.
			game.turn_manager.current_phase = TurnManager.Phase.START
			await game._do_start(0)
			t.check(owner.jim_rebuild_pending == 0 and game.unit_registry.active_units().size() == 2, "I04 Q19/20 normal START rebuilds one/two mountains without an activation choice: %s/%s" % [amount,timeout])
			var placements = game._mountain_snapshot().placements().filter(func(p): return not survivors.has(p.id))
			t.check(placements.size() == amount and placements.all(func(p): return p.left == (0 if timeout else 4) and p.right == (1 if timeout else 0)), "I04 Q19 selected positions honored; timeout puts every rebuilt mountain at downstream gap")
			t.check(game.unit_registry.active_units().all(func(body): return body.hp == 5 and body.max_hp == 5), "I04 mandatory rebuild creates fresh 5/5 terrain, not wounded copies")
			t.check(game.turn_manager.current_phase == TurnManager.Phase.PLAY and game._card_action_serial == serial and game._jim_rebuild_pending.is_empty(), "I04 mandatory rebuild resumes START and creates no card USE or leaked lease")
			t.check(await game._maybe_rebuild_mountains(owner,func(): return true) == 0 and game.unit_registry.active_units().size() == 2, "I04 consumed rebuild entitlement cannot generate a third mountain")
			await dispose(t,game)
	# Default means the current living spatial downstream player, not seat+1.
	var game = await fixture(t)
	var owner = game.players[0]
	game.players[1].mark_dead() # geometric boundary fixture, not a played kill
	game.turn_manager.rounds.relocate_before(3,2)
	game._jim_rebuild_choice_override = func(_p,_o,_v): return -1
	game.turn_manager.current_phase = TurnManager.Phase.START
	t.check(await game._maybe_rebuild_mountains(owner,func(): return true) == 1 and game._mountain_snapshot().placements().all(func(p): return p.left == 0 and p.right == 3), "I04 Q19 downstream default follows current spatial order and skips final-dead players")
	await dispose(t,game)
	# Q20 supersedes old optional PLAY permissions and their expiry. An actual
	# standalone PLAY frame is used; no full upstream Max skill is claimed here.
	game = await fixture(t)
	owner = game.players[0]
	game._do_play(0)
	game.turn_manager.current_player_idx = 1
	game.turn_manager.current_phase = TurnManager.Phase.START
	var frame = game.turn_manager.begin_standalone_play(0)
	game._do_play(1)
	t.check(owner.jim_rebuild_pending == 1 and game.unit_registry.active_units().size() == 1, "I04 Q20 neither ordinary nor granted PLAY triggers/consumes rebuilding")
	game.end_play_phase()
	t.check(frame.completed and owner.jim_rebuild_pending == 1, "I04 Q20 completing granted PLAY no longer expires a START rebuild resource")
	await dispose(t,game)
	for fault in ["phase","reset","registry","space","stock","restore","reentry"]:
		game = await fixture(t)
		owner = game.players[0]
		game.turn_manager.current_phase = TurnManager.Phase.START
		var nested: Array = []
		game._jim_rebuild_choice_override = func(p,_options,valid):
			var manager: GameManager = p.get_parent()
			if fault == "phase": manager.turn_manager.current_phase = TurnManager.Phase.DRAW
			if fault == "reset": manager.reset_game_over_state()
			if fault == "registry": manager._reset_unit_registry()
			if fault == "space": manager.turn_manager.rounds.relocate_before(3,1)
			if fault == "stock": p.jim_rebuild_pending += 1
			if fault == "restore": p.restore_game_start_state() # fault injection only
			if fault == "reentry": nested.append(await manager._maybe_rebuild_mountains(p,valid))
			return 0
		var result = await game._maybe_rebuild_mountains(owner,func(): return true)
		t.check(result == (1 if fault == "reentry" else game.CHOICE_INVALID) and game._jim_rebuild_pending.is_empty(), "I04 mandatory selection invalidation/reentry never leaves an actionable lease: "+fault)
		if fault == "reentry": t.check(nested == [game.CHOICE_INVALID] and game.unit_registry.active_units().size() == 2 and owner.jim_rebuild_pending == 0, "I04 nested START cannot duplicate a mandatory rebuild")
		else:
			var expected = 0 if fault in ["reset","registry"] else 1
			t.check(game.unit_registry.active_units().size() == expected and owner.jim_rebuild_pending == (0 if fault == "restore" else (2 if fault == "stock" else 1)), "I04 stale choice cannot create terrain or consume a new resource: "+fault)
		await dispose(t,game)
	await indulgence(t)
	await flipped(t)
	await other_turn_cost(t)
	await lan(t)
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]

func other_turn_cost(t):
	var game = load("res://Test/i04_initial_cases.gd").new().fixture(t,5,true,func(_p,_o,_v): return 0)
	game._halt_countdown()
	game._sacrifice_actor_override = func(_p,_target,_amount): return false
	var owner = game.players[0]
	var attacker = game.players[1]
	var mountain = game.unit_registry.active_units()[0]
	mountain.hp = 1
	# Seed B's PLAY, preserving real paid Strike/death processing thereafter.
	game.turn_manager.current_player_idx = 1
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	var hp = attacker.hp
	await game.execute_card_on_target(mountain,CardData.CardSubType.STRIKE)
	t.check(owner.hp == 5 and owner.max_hp == 5 and owner.jim_rebuild_pending == 1 and attacker.hp == hp, "I04 Q21 B's paid mountain kill charges Jim immediately, not the current actor")
	t.check(game.turn_manager.current_player_idx == 1 and game.turn_manager.current_phase == TurnManager.Phase.PLAY and game.unit_registry.active_units().size() == 1, "I04 Q21 mountain death never inserts Jim's START or rebuilds during B's PLAY")
	await dispose(t,game)

func flipped(t):
	var game = await fixture(t)
	var owner = game.players[0]
	t.check(owner.hp == 5 and owner.max_hp == 5 and owner.jim_rebuild_pending == 1, "I04 Q21 mountain death pays immediately before any next START")
	var asked: Array = []
	game._jim_rebuild_choice_override = func(_p,_o,_v): asked.append(true); return -1
	# Isolate the real skip-to-END boundary, avoiding automatic next-player AI.
	# The following normal START is seeded, not a claim of whole-round play.
	game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
	game.turn_manager.current_phase = TurnManager.Phase.START
	owner.facedown = true
	await game._do_start(0)
	t.check(not owner.facedown and game.turn_manager.current_phase == TurnManager.Phase.END and asked.is_empty(), "I04 Q22 flipped turn skips without opening a rebuild window")
	t.check(owner.jim_rebuild_pending == 1 and game.unit_registry.active_units().size() == 1 and owner.hp == 5 and owner.max_hp == 5, "I04 Q22 skipped turn retains the resource and never charges death cost again")
	game.turn_manager.phase_changed.connect(game._on_phase_changed)
	game.turn_manager.current_phase = TurnManager.Phase.START
	await game._do_start(0)
	t.check(asked.size() == 1 and owner.jim_rebuild_pending == 0 and game.unit_registry.active_units().size() == 2 and game.turn_manager.current_phase == TurnManager.Phase.PLAY, "I04 Q22 following normal START performs the retained mandatory rebuild once")
	t.check(owner.hp == 5 and owner.max_hp == 5, "I04 Q21 rebuilding itself never repays the mountain death cost")
	await dispose(t,game)

func indulgence(t):
	var game = await fixture(t)
	var owner = game.players[0]
	var card = CardBase.create(CardData.CardSubType.INDULGENCE)
	owner.judgment_cards.append(card)
	game._jim_rebuild_choice_override = func(_p,_o,_v): return -1
	game._nullify_override = func(): return false
	var gate = ChoicePromptAnswer.new()
	game._hand_discard_override = func(_s,_c,_m): await gate.answered; return [0]
	var phases: Array = []
	game.turn_manager.phase_changed.connect(func(_old,new,_seat): phases.append(new))
	game.turn_manager.current_phase = TurnManager.Phase.START
	await game._do_start(0)
	for step in 10:
		if game.turn_manager.current_phase == TurnManager.Phase.DISCARD: break
		await t.process_frame
	t.check(owner.jim_rebuild_pending == 0 and game.unit_registry.active_units().size() == 2, "I04 Q20 mandatory rebuilding commits before actual Indulgence judgment")
	t.check(game.turn_manager.current_phase == TurnManager.Phase.DISCARD and not phases.has(TurnManager.Phase.PLAY), "I04 Q20 actual Indulgence skips PLAY without cancelling START rebuilding")
	t.check(owner.judgment_cards.is_empty() and game.deck._discard.has(card), "I04 Q20 original delayed card completes judgment normally")
	game._game_over = true
	gate.submit(0)
	await t.process_frame
	game.queue_free()
	await t.process_frame

func lan(t):
	for timeout in [false,true]:
		var bridge = LanGameBridge.new()
		bridge._enable_mountain_rules_for_tests = true
		t.root.add_child(bridge)
		var roster: Array[Dictionary] = []
		for seat in 5: roster.append({"name":"P%d"%seat,"general":"吉姆·芒顿" if seat == 0 else "稻草人"})
		t.check(bridge.start(roster,GameModes.FREE_FOR_ALL,AiActionPacer.Speed.FAST), "I04 Q19 mandatory rebuild adapter starts")
		var initial = bridge.snapshot(0)
		bridge.submit(0,initial.controls[0].id)
		var game = bridge.game
		game._halt_countdown()
		game._sacrifice_actor_override = func(_p,_target,_amount): return false
		var mountain = game.unit_registry.active_units()[0]
		mountain.hp = 1
		await game.execute_card_on_target(mountain,CardData.CardSubType.STRIKE)
		game.turn_manager.current_phase = TurnManager.Phase.START
		game._do_start(0)
		var view = bridge.snapshot(0)
		t.check(view.controls.size() == 5 and view.controls.all(func(c): return "取消" not in c.text) and bridge.snapshot(1).controls.is_empty(), "I04 Q19 real mandatory START window has only position choices, private to controller")
		var stale = view.controls.back().id
		t.check(not bridge.submit(1,stale), "I04 Q19 other players cannot choose the rebuild position")
		if timeout: game._countdown_on_timeout.call()
		else: t.check(bridge.submit(0,stale), "I04 Q19 real opaque position command commits mandatory rebuilding")
		t.check(owner_pending(game) == 0 and game.unit_registry.active_units().size() == 2 and game.turn_manager.current_phase == TurnManager.Phase.PLAY, "I04 Q19 real click/timeout continues normal START exactly once")
		if timeout: t.check(game._mountain_snapshot().placements().all(func(p): return p.left == 0 and p.right == 1), "I04 Q19 real countdown uses downstream rather than initial left/right default")
		t.check(not bridge.submit(0,stale), "I04 Q19 consumed position token cannot replay in PLAY")
		game._game_over = true
		bridge.queue_free()
		await t.process_frame

func owner_pending(game) -> int:
	return game.players[0].jim_rebuild_pending
