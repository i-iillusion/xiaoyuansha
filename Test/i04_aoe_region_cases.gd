extends RefCounted

func dispose(t, game):
	game._game_over = true
	game.queue_free()
	await t.process_frame

func configure_board(game, nested := false):
	game._halt_countdown()
	game._nullify_override = func(): return false
	game._rescue_choice_override = func(_r,_d,_o): return -1
	game._sacrifice_actor_override = func(_p,_target,_n): return false
	for p in game.players:
		p.hand.clear(); p.determined_cards.clear(); p.hp = 4
	game.players[2].hand.append(null)
	if nested:
		game.players[2].hp = 2
		game.players[3].general_name = "里奥·普利威尔"
		game.players[3].hp = 1

func pure(t):
	var space = MountainSpace.new()
	var seats: Array[int] = [0,1,2,3,4]
	space.initialize(seats)
	space.place("a",1,2,seats)
	space.place("b",4,0,seats)
	var live: Array[int] = [0,1,3,4]
	var before = space.markers()
	t.check(space.same_region_from_anchor(2,4,live) and not space.same_region_from_anchor(2,0,live), "I04 Q31 dead source's retained marker preserves its region")
	t.check(space.snapshot(live).order() == live and space.markers() == before, "I04 Q31 origin query cannot revive a dead actor or mutate the circle")
	t.check(not space.same_region_from_anchor(99,4,live) and not space.same_region_from_anchor(2,2,live), "I04 Q31 malformed source/dead destination cannot gain effect permission")

func run(t):
	var saved = [GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	pure(t)
	for arrows in [false,true]:
		var game = load("res://Test/i04_declaration_cases.gd").new().fixture(t)
		configure_board(game)
		# Native effect fixture; the human adapter below advances real round turns.
		game.turn_manager.current_player_idx = 2
		var original_scope = game._prep_group_scope(game.players[2],CardData.CardSubType.BARBARIAN_INVASION)
		await game._play_aoe(CardData.CardSubType.DODGE if arrows else CardData.CardSubType.STRIKE,"万箭齐发" if arrows else "南蛮入侵","闪" if arrows else "杀")
		t.check(game.players[0].hp == 4 and game.players[1].hp == 4 and game.players[3].hp == 3 and game.players[4].hp == 3, "I04 M2 paid damage AOE affects its own region only: arrows=%s" % arrows)
		t.check(original_scope.size() == 4 and original_scope.has(game.players[0]) and game.players[2].hand_size() == 0 and game._pending_card_actions.is_empty(), "I04 AOE barrier preserves original Prep declaration and completes one payment")
		await dispose(t,game)
	await lan_source_death(t)
	await lan_existing_judgment(t)
	await handoff_guards(t)
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]

func handoff_guards(t):
	# Fault-injection fixture for deferred completion ownership, not a death rule.
	var game = load("res://Test/i04_declaration_cases.gd").new().fixture(t)
	game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
	var source = game.players[0]
	var action = game._record_card_action(source,CardBase.create(CardData.CardSubType.BARBARIAN_INVASION))
	source.hp = 0
	source.mark_dead()
	var revision = game.turn_manager.get_context_revision()
	var generation = game._dying_lifecycle_generation
	game._advance_completed_card_play(revision-1,generation)
	game._advance_completed_card_play(revision,generation-1)
	t.check(game.turn_manager.current_phase == TurnManager.Phase.PLAY, "I04 stale context/lifecycle completion cannot end a later PLAY")
	game._advance_completed_card_play(revision,generation)
	t.check(game.turn_manager.current_phase == TurnManager.Phase.PLAY, "I04 deceased user's PLAY waits while original parent card is still pending")
	game._complete_card_actions([action])
	for i in 3: await t.process_frame
	t.check(game.turn_manager.current_phase == TurnManager.Phase.DISCARD and game._pending_card_actions.is_empty(), "I04 genuine last card completion requests exactly the next phase")
	game._advance_completed_card_play(revision,generation)
	t.check(game.turn_manager.current_phase == TurnManager.Phase.DISCARD, "I04 duplicate completion cannot skip another phase")
	await dispose(t,game)

func bridge_fixture(t, jim := 0):
	var bridge = LanGameBridge.new()
	bridge._enable_mountain_rules_for_tests = true
	t.root.add_child(bridge)
	var roster: Array[Dictionary] = []
	for seat in 5: roster.append({"name":"P%d"%seat,"general":"吉姆·芒顿" if seat == jim else ("里奥·普利威尔" if jim == 0 and seat == 3 else "稻草人")})
	t.check(bridge.start(roster,GameModes.FREE_FOR_ALL,AiActionPacer.Speed.FAST), "I04 AOE/judgment all-human adapter starts")
	return bridge

func click(t, bridge, seat, text):
	var token = load("res://Test/i04_movement_cases.gd").new().find(bridge.snapshot(seat),text)
	t.check(token != "" and bridge.submit(seat,token), "I04 actual human command: %s / %d" % [text,seat])
	return token

func lan_source_death(t):
	var bridge = bridge_fixture(t)
	click(t,bridge,0,"山甲 玩家2→玩家3；山乙 玩家5→玩家1")
	var game = bridge.game
	# Real round ledger, no synthetic current_player_idx for the handoff proof.
	for seat in 2:
		game.players[seat].hand.clear()
		click(t,bridge,seat,"结束出牌")
		for i in 3: await t.process_frame
	t.check(game.turn_manager.current_player_idx == 2 and game.turn_manager.current_phase == TurnManager.Phase.PLAY, "I04 Q31 real round progression reaches C before paid AOE")
	configure_board(game,true)
	var events: Array = []
	game.players[4].hp_changed.connect(func(hp): events.append([hp,game.players[2].is_dead(),game.mountain_space.ids().size()]))
	game.action_history.changed.connect(func():
		var entry = game.action_history.entries.back()
		if entry.kind == "phase" and entry.actor == 2 and entry.phase == TurnManager.Phase.DISCARD: events.append(["handoff",game.players[4].hp]))
	click(t,bridge,2,"出牌")
	click(t,bridge,2,"锦囊牌")
	click(t,bridge,2,"普通锦囊")
	var paid = click(t,bridge,2,"南蛮入侵")
	await t.create_timer(0.15).timeout # actual CardSelector confirmation tween
	for i in 5: await t.process_frame
	t.check(game.players[2].is_dead() and game.players[0].hp == 2 and game.players[1].hp == 2 and game.players[4].hp == 1, "I04 Q31 nested Yudaxi kills original source; remaining AOE hits E but never A/B")
	t.check(events == [[2,false,2],[1,true,2],["handoff",1]], "I04 Q31 full remaining damage precedes deceased C's turn handoff; both walls survive")
	t.check(game.yudaxi.results.size() == 1 and game.yudaxi.results[0].deaths == 1 and game.players[3].hp == 1 and game.players[3].hand_size() == 2, "I04 Q31 Leo revives with one card then Choutai draws one for his actual next normal turn")
	t.check(game._pending_card_actions.is_empty() and game._dying_contexts.is_empty() and not game._game_over and not bridge.submit(2,paid), "I04 Q31 parent/nested frames release and paid AOE token cannot replay")
	var damage_events = game.action_history.entries.filter(func(event): return event.kind == "damage")
	t.check(damage_events.size() == 2 and damage_events[1].text.begins_with("无来源 对"), "I04 Q31 remaining E damage has no damage source despite retained geometry origin")
	t.check(game.turn_manager.current_player_idx == 3 and game.turn_manager.current_phase == TurnManager.Phase.PLAY and bridge.input_owner() == 3, "I04 Q31 completed card automatically yields to living Leo with no dead-player input")
	game._game_over = true
	bridge.queue_free()
	await t.process_frame

func lan_existing_judgment(t):
	var bridge = bridge_fixture(t,4)
	var game = bridge.game
	game._nullify_override = func(): return false
	game._target_confirm_override = func(): return 1
	game._enter_targeting_mode(CardData.CardSubType.INDULGENCE)
	var token: String = bridge.snapshot(0).targets.get("4","")
	t.check(token != "" and bridge.submit(0,token), "I04 Q30 real B target command places Indulgence before Jim's first START")
	var original = game.players[4].judgment_cards[0]
	t.check(original.source_seat == 0 and game.mountain_space.ids().is_empty(), "I04 Q30 original card entered legally before any mountain existed")
	for seat in 4:
		game.players[seat].hand.clear()
		click(t,bridge,seat,"结束出牌")
		for i in 3: await t.process_frame
	t.check(game.turn_manager.current_player_idx == 4 and not game._jim_opening_pending.is_empty(), "I04 Q30 fifth seat reaches genuine first START with a pending locked mountain placement")
	# Isolate Jim on both flanks using the real mandatory placement window.
	click(t,bridge,4,"山甲 玩家4→玩家5；山乙 玩家5→玩家1")
	for i in 5: await t.process_frame
	t.check(game.mountain_space.ids().size() == 2 and not game._mountain_effect_reaches(game.players[0],game.players[4]), "I04 Q30 later mountain placement isolates judgment holder from original source")
	t.check(game.players[4].judgment_cards.is_empty() and game.deck._discard.count(original) == 1, "I04 Q30 preexisting original judgment resolves and discards exactly once across new walls")
	var phases = game.action_history.entries.filter(func(entry): return entry.kind == "phase" and entry.actor == 4)
	t.check(not phases.any(func(entry): return entry.phase == TurnManager.Phase.PLAY) and phases.any(func(entry): return entry.phase == TurnManager.Phase.DISCARD) and not game.turn_manager.skip_play_phase, "I04 Q30 actual judgment skips Jim's PLAY once and consumes its modifier before normal discard")
	t.check(game.turn_manager.current_player_idx == 0 and game.turn_manager.current_phase == TurnManager.Phase.PLAY, "I04 Q30 Jim's six-card hand needs no discard at six maximum HP; normal round reaches B")
	game._game_over = true
	bridge.queue_free()
	await t.process_frame
