extends RefCounted

func pure(t):
	for count in range(2,11):
		var state = MountainSpace.new()
		var seats: Array[int] = []
		seats.assign(range(count))
		state.initialize(seats)
		t.check(state.placement_sequences(2,seats).size() == count*(count+1), "I04 Q24 pair planning includes both sides of the first planned mountain")
		state.place("a",0,1,seats)
		t.check(not state.legal_gap(0,1,seats) and state.gaps(seats).has([0,"a"]) and state.gaps(seats).has(["a",1]), "I04 Q24 occupied player interval is replaced by two real boundaries")
		var before = state.markers()
		t.check(not state.place("b",0,1,seats) and state.markers() == before, "I04 Q24 stale unsplit placement is rejected atomically")
		t.check(not state.move("a",0,"a",seats) and not state.move("a","a",1,seats) and not state.move("a",0,1,seats) and state.markers() == before, "I04 Q25 neither own side nor merged original player gap can move a mountain in place")
		state.place("b",0,"a",seats)
		t.check(state.markers().slice(0,4) == [0,"b","a",1], "I04 Q24 selecting left boundary preserves explicit mountain order")
		t.check(state.move("a",0,"b",seats) and state.markers().slice(0,4) == [0,"a","b",1], "I04 Q25 crossing the other mountain changes physical position without extra player distance")
		t.check(state.snapshot(seats).player_distance(0,1) == count-1, "I04 M5 refined gaps preserve adjudicated same-player-interval distance")
		var projected: Array[int] = [0,1]
		t.check(state.gaps(projected).size() == 4 and state.gaps([0]).is_empty() and state.gaps([0,99]).is_empty(), "I04 real boundaries omit dead fixed seats and reject terminal or foreign circles")

func dispose(t,game):
	game._game_over = true
	game.queue_free()
	await t.process_frame

func fixture(t):
	var game = load("res://Test/i04_hushan_cases.gd").new().fixture(t)
	game._jim_mountain_destination_override = func(_p,_body,_options,_valid): return 0
	return game

func run(t):
	pure(t)
	var saved = [GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	# Both sides are selected through the real locked initial summon, not a
	# direct registration fixture. These scenarios deliberately share distances.
	for side in [0,1]:
		var game = load("res://Test/i04_initial_cases.gd").new().fixture(t,5,true,func(_p,_o,_v): return side)
		var ids = game.mountain_space.ids()
		var expected = [0,ids[1],ids[0],1] if side == 0 else [0,ids[0],ids[1],1]
		t.check(game.mountain_space.markers().slice(0,4) == expected, "I04 Q24 real first summon honors either side of its first new mountain")
		await dispose(t,game)
	var game = fixture(t)
	var owner = game.players[0]
	var target = game.unit_registry.active_units()[0]
	var id = game.unit_registry.id_for(target)
	var before = game.mountain_space.markers()
	var hand = owner.hand_size()
	var serial = game._card_action_serial
	t.check(await game._activate_yishan(owner) == 1 and game.mountain_space.markers() != before, "I04 Yishan pays and changes a real boundary")
	t.check(game.unit_registry.id_for(target) == id and target.hp == 2 and target.max_hp == 5 and game.unit_registry.active_units().size() == 2, "I04 Yishan preserves original registered body and health instead of respawning terrain")
	t.check(owner.hand_size() == hand-1 and game._card_action_serial == serial and game.turn_manager.phase_skill_used("yishan",0), "I04 Yishan consumes exactly one hand card and its PLAY quota without card USE")
	t.check(await game._activate_yishan(owner) == 0 and owner.hand_size() == hand-1, "I04 Yishan cannot repeat in the same PLAY")
	t.check(await game._activate_hushan(owner) == 1 and target.hp == 5, "I04 Hushan and Yishan have independent quotas")
	game.turn_manager.current_player_idx = 1
	game.turn_manager.current_phase = TurnManager.Phase.START
	var frame = game.turn_manager.begin_standalone_play(0)
	game._do_play(1)
	t.check(await game._activate_yishan(owner) == 1, "I04 Yishan is once per actual PLAY including granted PLAY")
	game.end_play_phase()
	t.check(frame.completed and game._jim_mountain_skill_pending.is_empty(), "I04 Yishan releases the skill lease before the granted stage finishes")
	await dispose(t,game)
	for fault in ["cancel_target","cancel_gap","invalid_gap","decline_fee","phase","space","reset","restore","free","reentry"]:
		game = fixture(t)
		owner = game.players[0]
		target = game.unit_registry.active_units()[0]
		before = game.mountain_space.markers()
		hand = owner.hand_size()
		var nested: Array = []
		if fault == "cancel_target": game._jim_mountain_target_override = func(_p,_ts,_v): return -1
		game._jim_mountain_destination_override = func(p,body,options,_v):
			if fault == "free": body.queue_free(); await t.process_frame; return 0
			if fault == "cancel_gap": return -1
			if fault == "invalid_gap": return options.size()
			if fault == "reentry": nested.append(await p.get_parent()._activate_yishan(p))
			return 0
		game._hand_discard_override = func(snapshot,count,_m):
			var manager: GameManager = snapshot.owner.get_parent()
			if fault == "decline_fee": return []
			if fault == "phase": manager.turn_manager.current_phase = TurnManager.Phase.DRAW
			if fault == "space": manager.turn_manager.rounds.relocate_before(3,1)
			if fault == "reset": manager.reset_game_over_state()
			if fault == "restore": manager._do_sage_save(snapshot.owner) # invalidation injection only
			return snapshot.defaults(count)
		var result = await game._activate_yishan(owner)
		var cancel = fault in ["cancel_target","cancel_gap","decline_fee"]
		t.check(result == (0 if cancel else (1 if fault == "reentry" else game.CHOICE_INVALID)) and game._jim_mountain_skill_pending.is_empty(), "I04 Yishan cancellation/invalidation/reentry releases its own lease: "+fault)
		if fault == "reentry": t.check(nested == [0] and owner.hand_size() == hand-1, "I04 Yishan reentry cannot double-charge or double-move")
		elif fault == "restore": t.check(owner.hand_size() == 4 and game.mountain_space.ids().is_empty(), "I04 Yishan cannot move a disappeared original body after Sage restoration")
		else: t.check(owner.hand_size() == hand and not game.turn_manager.phase_skill_used("yishan",0), "I04 Yishan stale or cancelled selection cannot charge or use quota: "+fault)
		if cancel or fault in ["invalid_gap","phase","free"]: t.check(game.mountain_space.markers() == before, "I04 Yishan cannot silently relocate terrain on an uncommitted choice: "+fault)
		await dispose(t,game)
	# Real normal death followed by normal START, retaining the surviving mountain.
	game = await load("res://Test/i04_rebuild_cases.gd").new().fixture(t)
	owner = game.players[0]
	var survivor = game.mountain_space.ids()[0]
	game._jim_rebuild_choice_override = func(_p,_o,_v): return -1
	game.turn_manager.current_phase = TurnManager.Phase.START
	await game._do_start(0)
	var ring = game.mountain_space.markers()
	var owner_index = ring.find(0)
	t.check(ring[(owner_index+1)%ring.size()] != survivor and ring[(owner_index+2)%ring.size()] == survivor, "I04 Q26 actual rebuild timeout places new mountain immediately after Jim before the survivor")
	await dispose(t,game)
	await lan(t)
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]

func lan(t):
	var bridge = LanGameBridge.new()
	bridge._enable_mountain_rules_for_tests = true
	t.root.add_child(bridge)
	var roster: Array[Dictionary] = []
	for seat in 5: roster.append({"name":"P%d"%seat,"general":"吉姆·芒顿" if seat == 0 else "稻草人"})
	t.check(bridge.start(roster,GameModes.FREE_FOR_ALL,AiActionPacer.Speed.FAST), "I04 Yishan real human adapter starts")
	bridge.submit(0,bridge.snapshot(0).controls[0].id)
	var game = bridge.game
	game._halt_countdown()
	var hand = game.players[0].hand_size()
	var before = game.mountain_space.markers()
	game._open_player_detail(game.players[0])
	var token = find(bridge.snapshot(0),"【移山】")
	t.check(token != "" and not bridge.submit(1,token) and bridge.submit(0,token), "I04 Yishan gated menu validates actor ownership")
	var target_token = find(bridge.snapshot(0),"山1")
	t.check(target_token != "" and bridge.submit(0,target_token), "I04 Yishan opaque target chooses original registered mountain")
	var destinations = bridge.snapshot(0)
	t.check(bridge.snapshot(1).controls.is_empty() and destinations.controls.all(func(c): return "山1" not in c.text), "I04 Q25 private destination window excludes both own boundaries")
	var gap_token = find(destinations,"玩家1→山2")
	t.check(gap_token != "" and bridge.submit(0,gap_token), "I04 Q24 actual destination command distinguishes the other mountain's side")
	var card_token = find(bridge.snapshot(0),"任意牌")
	t.check(card_token != "" and bridge.submit(0,card_token), "I04 Yishan selects a genuine arbitrary hand card through LAN")
	var confirm = find(bridge.snapshot(0),"确认弃牌")
	t.check(confirm != "" and not bridge.submit(1,confirm) and bridge.submit(0,confirm), "I04 Yishan fee confirmation rejects foreign actor")
	t.check(game.players[0].hand_size() == hand-1 and game.mountain_space.markers() != before and game.turn_manager.phase_skill_used("yishan",0), "I04 Yishan real menu/target/gap/card commands commit one move and one fee")
	t.check(not bridge.submit(0,target_token) and not bridge.submit(0,gap_token) and not bridge.submit(0,confirm), "I04 Yishan consumed input tokens cannot replay")
	game._game_over = true
	bridge.queue_free()
	await t.process_frame

func find(view,needle: String) -> String:
	for control in view.controls:
		if needle in control.text and not control.disabled: return control.id
	return ""
