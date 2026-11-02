extends RefCounted

func fixture(t):
	var game = load("res://Test/h02_integration_cases.gd").new().fixture(t,5,GameModes.FREE_FOR_ALL)
	game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
	game._mountain_rules_enabled = true
	load("res://Test/i04_burning_interception_cases.gd").new().prepare(game)
	game.players[4].general_name = "吉姆·芒顿"
	game.players[4].max_hp = 6
	game.players[4].hp = 6
	return game

func mountains(game, same_gap := false):
	var first = game._spawn_mountain_at(game.players[4],0,1)
	var second = game._spawn_mountain_at(game.players[4],game.unit_registry.id_for(first),1) if same_gap else game._spawn_mountain_at(game.players[4],2,3)
	return [first,second]

func finish(game):
	game.turn_manager.current_phase = TurnManager.Phase.END
	await game.turn_manager.next_turn()

func dispose(t,game):
	game._game_over = true
	game.queue_free()
	await t.process_frame

func run(t):
	var saved = [GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	await passage(t)
	await dragon(t)
	await timeweave(t)
	await stale(t)
	await lan(t)
	await lan_sunny(t)
	await lan_dead_nominee(t)
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]

func passage(t):
	var game = fixture(t)
	var pair = mountains(game)
	var original = load("res://Test/i04_burning_interception_cases.gd").new().put_fire(pair[0])
	var before = game.turn_manager.turn_id
	game.turn_manager.use_card("duel")
	var during: Array = []
	game._nullify_override = func():
		during.append([game.turn_manager.turn_id,game.turn_manager._get_turn_count("duel",0),game.turn_manager.current_unit_id])
		return false
	await finish(game)
	t.check(during == [[before,1,""]] and pair[0].hp == 3 and game.players[0].hp == 4 and game.players[1].hp == 4, "I04 Q35 actual ordinary END judges its next mountain before B START without resetting A quotas")
	t.check(game.turn_manager.current_player_idx == 1 and game.turn_manager.current_phase == TurnManager.Phase.START and game.turn_manager.turn_id == before+1 and game.deck._discard.count(original) == 1, "I04 terrain passage then enters exactly one ordinary B turn")
	var terrain_phases = game.action_history.entries.filter(func(e): return e.kind == "phase" and e.details.get("actor_unit","") == game.unit_registry.id_for(pair[0]))
	t.check(terrain_phases.size() == 1 and terrain_phases[0].phase == TurnManager.Phase.JUDGE and terrain_phases[0].actor == -1 and ActorIdentity.key_for(game.players,game.unit_registry,pair[0]) == null, "I04 natural terrain judgment logs its phase without an acting player or input key")
	await finish(game) # B -> C; no mountain in this interval.
	t.check(game.turn_manager.current_player_idx == 2 and pair[0].hp == 3, "I04 passed mountain is not judged again before an unrelated next player")
	# Q36 mechanical boundary fixture: after its first judgment, Move Mountain
	# puts the same carrier in a later, not-yet-passed gap of this same round.
	pair[0].hp = 1
	var id = game.unit_registry.id_for(pair[0])
	var live: Array[int] = [0,1,2,3,4]
	t.check(game.mountain_space.move(id,2,game.unit_registry.id_for(pair[1]),live), "I04 Q36 fixture moves judged terrain to C/other-mountain gap")
	load("res://Test/i04_burning_interception_cases.gd").new().put_fire(pair[0])
	await finish(game)
	t.check(pair[0].is_dead() and game.players[4].max_hp == 5 and game.players[4].jim_rebuild_pending == 1 and game.turn_manager.rounds.round_id == 1, "I04 Q36 moved terrain judges again in the same round and pays its real death cost once")
	t.check(game.turn_manager.current_player_idx == 3 and game._mountain_judgment_contexts.is_empty(), "I04 after moved terrain death its remaining spatial interval finishes and D starts")
	await dispose(t,game)
	game = fixture(t)
	pair = mountains(game)
	load("res://Test/i04_burning_interception_cases.gd").new().put_fire(pair[0])
	game.turn_manager.current_phase = TurnManager.Phase.START
	var standalone = game.turn_manager.begin_standalone_play(2)
	t.check(game.turn_manager.complete_standalone_phase(standalone) and pair[0].hp == 5 and game.turn_manager.ordinary_origin == null, "I04 standalone PLAY completion cannot dispatch a mountain passage")
	await finish(game)
	t.check(pair[0].hp == 3 and game.turn_manager.current_player_idx == 1, "I04 only the later completed whole turn passes the mountain")
	await dispose(t,game)
	game = fixture(t)
	pair = mountains(game)
	load("res://Test/i04_burning_interception_cases.gd").new().put_fire(pair[0])
	game.turn_manager.use_card("duel")
	var parent_turn = game.turn_manager.turn_id
	t.check(game.turn_manager.begin_extra_turn(2), "I04 extra-turn primitive suspends ordinary A fixture")
	await finish(game)
	t.check(pair[0].hp == 5 and game.turn_manager.current_player_idx == 0 and game.turn_manager.turn_id == parent_turn and game.turn_manager._get_turn_count("duel",0) == 1 and game.turn_manager.ordinary_origin == null, "I04 completed extra turn restores A without ordinary spatial passage or lost quotas")
	await finish(game)
	t.check(pair[0].hp == 3 and game.turn_manager.current_player_idx == 1, "I04 only restored A's later END passes the mountain")
	await dispose(t,game)
	game = fixture(t)
	pair = mountains(game)
	var lightning = CardBase.create(CardData.CardSubType.LIGHTNING)
	pair[0].judgment_cards.append(lightning)
	await finish(game)
	t.check(pair[0].hp == 1 and game.deck._discard.count(lightning) == 1 and game.turn_manager.current_player_idx == 1, "I04 natural spatial passage resolves mountain Lightning through the shared judgment pipeline")
	await dispose(t,game)

func dragon(t):
	var game = fixture(t)
	var pair = mountains(game)
	load("res://Test/i04_burning_interception_cases.gd").new().put_fire(pair[0])
	var body = FireDragonState.create_body()
	var id = game._register_unit_body(UnitRegistry.Kind.FIRE_DRAGON,body,game.players[0])
	t.check(game.fire_dragon_state.attach(id), "I04 mixed passage attaches actual dragon turn fixture")
	await finish(game)
	t.check(game.turn_manager.current_unit_id == id and pair[0].hp == 5, "I04 owner END first admits attached dragon, not the following mountain")
	await finish(game)
	t.check(pair[0].hp == 3 and game.turn_manager.current_unit_id == "" and game.turn_manager.current_player_idx == 1 and game.turn_manager.ordinary_origin == id, "I04 completed dragon tail then passes the mountain once before B")
	await dispose(t,game)

func timeweave(t):
	for accept in [true,false]:
		var game = fixture(t)
		var pair = mountains(game)
		var fire = load("res://Test/i04_burning_interception_cases.gd").new().put_fire(pair[0])
		game.players[3].general_name = "桑尼·泰姆"
		game._timeweave_candidates_override = func(): return [game.players[3]]
		var offers: Array = []
		game._timeweave_choice_override = func(_p,nominee): offers.append(nominee); return 0 if accept else -1
		await finish(game)
		if accept:
			t.check(game.turn_manager.current_player_idx == 3 and pair[0].hp == 5 and not game.deck._discard.has(fire), "I04 Q40 Sunny enters before terrain starts, not after its judgment")
			t.check(game.mountain_space.markers() == [0,3,game.unit_registry.id_for(pair[0]),1,2,game.unit_registry.id_for(pair[1]),4] and game.turn_manager.rounds.space_order() == [0,3,1,2,4], "I04 Q40 actual relocation places D before mountain while fixed projection stays synchronized")
			await finish(game)
			t.check(pair[0].hp == 3 and game.players[3].hp == 4 and game.players[1].hp == 4 and game.players[0].hp == 5 and game.turn_manager.current_player_idx == 1, "I04 Q40 D complete turn precedes mountain fire selecting D/B, then B START")
		else:
			t.check(pair[0].hp == 3 and game.players[0].hp == 4 and game.players[3].hp == 5 and game.turn_manager.current_player_idx == 1 and offers == [1], "I04 declined insertion judges A/B; cannot ask opposite-region D inside the mountain judgment")
		await dispose(t,game)
	var game = fixture(t)
	var pair = mountains(game)
	load("res://Test/i04_burning_interception_cases.gd").new().put_fire(pair[0])
	game.players[2].general_name = "桑尼·泰姆"
	game._timeweave_candidates_override = func(): return [game.players[2]]
	var health_at_offer: Array = []
	game._timeweave_choice_override = func(_p,_n): health_at_offer.append(pair[0].hp); return 0
	await finish(game)
	t.check(health_at_offer == [3] and game.turn_manager.current_player_idx == 2 and game.mountain_space.markers()[1] == game.unit_registry.id_for(pair[0]), "I04 Sunny in B's region can insert only after the boundary mountain has finished")
	await dispose(t,game)
	game = fixture(t)
	mountains(game)
	game.players[3].general_name = "桑尼·泰姆"
	game._timeweave_candidates_override = func(): return [game.players[3]]
	game._timeweave_choice_override = func(_p,_n): return -1
	game.turn_manager.rounds.relocate_before(3,1)
	var starts: Array = []
	for i in 5:
		await finish(game)
		starts.append(game.turn_manager.current_player_idx)
	t.check(starts == [1,2,4,3,0] and game.turn_manager.rounds.round_id == 2, "I04 own-position deferral eventually forces last Sunny; next round still starts at fixed live head A")
	await dispose(t,game)
	game = fixture(t)
	mountains(game,true)
	game.players[1].general_name = "桑尼·泰姆"
	game._timeweave_candidates_override = func(): return [game.players[1]]
	var optional_offers: Array = []
	game._timeweave_choice_override = func(_p,n): optional_offers.append(n); return -1
	var delayed_starts: Array = []
	for i in 3:
		await finish(game)
		delayed_starts.append(game.turn_manager.current_player_idx)
	var offered_before_last = optional_offers.size()
	await finish(game)
	t.check(delayed_starts == [2,3,4] and game.turn_manager.current_player_idx == 1, "I04 same-gap last Sunny still reaches its forced ordinary turn after the intervening mountain positions")
	t.check(optional_offers.size() == offered_before_last and not game.turn_manager._ordinary_selecting, "I04 last Sunny cannot reopen an optional endless insertion window before a mountain")
	await dispose(t,game)

func stale(t):
	for mode in ["phase","reset"]:
		var game = fixture(t)
		var pair = mountains(game)
		var fire = load("res://Test/i04_burning_interception_cases.gd").new().put_fire(pair[0])
		var starts: Array = []
		game.turn_manager.phase_changed.connect(func(_old,phase,seat):
			if phase == TurnManager.Phase.START: starts.append(seat))
		game._nullify_override = func():
			if mode == "phase": game.turn_manager.current_phase = TurnManager.Phase.WAITING
			else: game.reset_game_over_state()
			return false
		await finish(game)
		t.check(starts.is_empty() and not game.deck._discard.has(fire) and game._mountain_judgment_contexts.is_empty() and not game.turn_manager._ordinary_selecting, "I04 stale terrain passage cannot enter the queued ordinary turn: "+mode)
		await dispose(t,game)

func lan(t):
	var bridge = load("res://Test/i04_aoe_region_cases.gd").new().bridge_fixture(t,4)
	var game = bridge.game
	# Same lawful boundary as Q41, using real whole-turn END and the real
	# human rescue commands. Placement/initial cards remain explicit fixtures.
	var center = load("res://Test/i04_terrain_rescue_cases.gd").new().configure(game)
	game._rescue_choice_override = Callable()
	load("res://Test/i04_aoe_region_cases.gd").new().click(t,bridge,0,"结束出牌")
	for i in 3: await t.process_frame
	var token = load("res://Test/i04_movement_cases.gd").new().find(bridge.snapshot(2),"使用【桃】")
	t.check(token != "" and bridge.input_owner() == 2 and game.turn_manager._ordinary_selecting and center.hp == 3, "I04 natural A END reaches terrain fire and Q41 real C rescue before B START")
	var turn = game.turn_manager.turn_id
	game._on_turn_ended(0) # Fault injection: duplicate old END while awaiting C.
	t.check(not bridge.submit(0,token) and bridge.submit(2,token), "I04 natural terrain rescue rejects other owner and accepts C once")
	for i in 3: await t.process_frame
	var own_token = load("res://Test/i04_movement_cases.gd").new().find(bridge.snapshot(0),"使用【桃】")
	t.check(own_token != "" and not bridge.submit(2,token) and game.players[0].hand_size() == 1 and game.players[2].hand_size() == 0, "I04 after terrain fire B's newly spread fire uses ordinary B rescue order, reaching A last")
	t.check(bridge.submit(0,own_token), "I04 real A rescue completes B's own judgment")
	for i in 3: await t.process_frame
	t.check(game.turn_manager.current_player_idx == 1 and game.turn_manager.current_phase == TurnManager.Phase.PLAY and game.turn_manager.turn_id == turn+1 and game.players[1].hp == 1, "I04 automatic passage enters exactly one B turn, judging its spread card before normal PLAY")
	t.check(bridge.input_owner() == 1 and bridge.acting_unit() == "" and game._mountain_judgment_contexts.is_empty() and not game.turn_manager._ordinary_selecting and not bridge.submit(0,own_token), "I04 settled natural passage restores B input without terrain actor or replay authority")
	game._game_over = true
	bridge.queue_free()
	await t.process_frame

func lan_sunny(t):
	var helper = load("res://Test/i04_aoe_region_cases.gd").new()
	var bridge = helper.bridge_fixture(t,4)
	var game = bridge.game
	load("res://Test/i04_burning_interception_cases.gd").new().prepare(game)
	var pair = mountains(game)
	load("res://Test/i04_burning_interception_cases.gd").new().put_fire(pair[0])
	# Sunny remains metadata-only. This explicit candidate fixture tests the
	# existing insertion interface, not release of the complete I05 general.
	game.players[3].general_name = "桑尼·泰姆"
	game._timeweave_candidates_override = func(): return [game.players[3]]
	helper.click(t,bridge,0,"结束出牌")
	for i in 3: await t.process_frame
	var token = load("res://Test/i04_movement_cases.gd").new().find(bridge.snapshot(3),"现在行动")
	t.check(token != "" and bridge.input_owner() == 3 and pair[0].hp == 5 and not bridge.submit(1,token), "I04 Q40 actual remote insertion window precedes mountain judgment and belongs only to Sunny")
	t.check(bridge.submit(3,token), "I04 Q40 Sunny's actual human insertion command accepted")
	for i in 3: await t.process_frame
	t.check(game.turn_manager.current_player_idx == 3 and game.turn_manager.current_phase == TurnManager.Phase.PLAY and pair[0].hp == 5 and bridge.snapshot(0).space == [0,3,1,2,4], "I04 Q40 moved Sunny receives full normal turn while mountain is still unjudged")
	helper.click(t,bridge,3,"结束出牌")
	for i in 3: await t.process_frame
	t.check(game.turn_manager.current_player_idx == 1 and game.turn_manager.current_phase == TurnManager.Phase.PLAY and game.players[0].hp == 5 and game.players[3].hp == 4 and game.players[1].hp == 3 and pair[0].hp == 1, "I04 Q40 real D END judges mountain with D/B neighbors; B then judges its spread fire before PLAY")
	t.check(bridge.input_owner() == 1 and not bridge.submit(3,token) and game._timeweave_spatial_relocation.is_empty(), "I04 insertion context retires and does not retain remote input or replay authority")
	game._game_over = true
	bridge.queue_free()
	await t.process_frame

func lan_dead_nominee(t):
	var helper = load("res://Test/i04_aoe_region_cases.gd").new()
	var bridge = helper.bridge_fixture(t,4)
	var game = bridge.game
	load("res://Test/i04_terrain_rescue_cases.gd").new().configure(game)
	game.players[0].hand.clear()
	game.players[2].hand.clear()
	var before_turn = game.turn_manager.turn_id
	var dead_starts: Array = []
	game.turn_manager.phase_changed.connect(func(_old,phase,seat):
		if phase == TurnManager.Phase.START and seat == 1: dead_starts.append(seat))
	helper.click(t,bridge,0,"结束出牌")
	for i in 3: await t.process_frame
	t.check(game.players[1].is_dead() and game.turn_manager.current_player_idx == 2 and game.turn_manager.current_phase == TurnManager.Phase.PLAY, "I04 a nominee killed during natural terrain fire is skipped, and C reaches normal PLAY")
	t.check(dead_starts.is_empty() and game.turn_manager.turn_id == before_turn+1, "I04 dead queued nominee receives no START or fresh turn ID/counters")
	t.check(game._mountain_judgment_contexts.is_empty() and not game.turn_manager._ordinary_selecting and bridge.input_owner() == 2, "I04 dead-nominee reentry completes its continuation without a stale passage lock")
	game._game_over = true
	bridge.queue_free()
	await t.process_frame
