extends RefCounted

func player() -> Player:
	var p = Player.new()
	p.general_name = "萨利·赛克斯"; p.gender = "female"; p.max_hp = 3; p.hp = 3
	p.capture_game_start_state()
	return p

func run(t):
	for enabled in [false,true]:
		var p = player(); p.sally_smoking_enabled = enabled
		t.check(SallySmokingState.can_smoke(p) == enabled, "I05e4a metadata never independently enables smoking")
		t.check(SallySmokingState.note_payment(p) == enabled and p.sally_smoke_uses == int(enabled) and p.hp == 3, "I05e4a counter transition is gated and never pays HP")
		p.hp = 0
		t.check(not SallySmokingState.establish_after_rescue(p) and p.gender == "female" and not p.sally_smoke_active, "I05e4a still-dying body cannot receive premature smoking state")
		p.hp = 2
		t.check(SallySmokingState.establish_after_rescue(p) == enabled, "I05e4a state establishment requires live authorized body")
		t.check(p.gender == ("male" if enabled else "female") and p.sally_smoke_uses == int(enabled), "I05e4a establishment does not invent a post-rescue payment or counter")
		p.restore_game_start_state()
		t.check(p.gender == "female" and p.hp == 3 and p.sally_smoke_uses == 0 and not p.sally_smoke_active and p.sally_smoking_enabled == enabled, "I05e4a Sage resets general state while retaining server capability")
		p.free()
	for skipped in [false,true]:
		var p = player(); p.sally_smoking_enabled = true
		t.check(SallySmokingState.start_turn(p,10,false) and SallySmokingState.can_smoke(p), "I05e4a normal initial START is separate from activation")
		t.check(SallySmokingState.cost(p) == 1 and SallySmokingState.note_payment(p), "I05e4a first proposed fee is one")
		t.check(SallySmokingState.establish_after_rescue(p) and not SallySmokingState.can_smoke(p), "I05e4a male body cannot immediately smoke again")
		t.check(not SallySmokingState.protects_hp(p,false) and SallySmokingState.protects_hp(p,true), "I05e4a protection query uses actual own-turn distinction")
		t.check(SallySmokingState.end_turn(p,10,false) and p.gender == "male" and p.sally_smoke_active, "I05e4a activation turn END keeps male state and pending protection")
		t.check(SallySmokingState.start_turn(p,11,skipped), "I05e4a next turn receipt accepted once")
		t.check(not SallySmokingState.start_turn(p,11,false) and not SallySmokingState.start_turn(p,10,false), "I05e4a duplicate/stale START cannot upgrade a skipped turn")
		if skipped:
			t.check(p.gender == "male" and p.sally_smoke_active and p.sally_smoke_pending_boost and not SallySmokingState.doubles_response(p,11), "I05e4a flipped skip defers protection expiry and boost")
			t.check(SallySmokingState.end_turn(p,11,true) and p.gender == "male", "I05e4a skipped END does not feminize")
			t.check(SallySmokingState.start_turn(p,12,false), "I05e4a next normal turn activates deferred effects")
		var boosted = 12 if skipped else 11
		t.check(not p.sally_smoke_active and SallySmokingState.doubles_response(p,boosted) and not SallySmokingState.doubles_response(p,boosted+1), "I05e4a boost is tied to one actual turn, not a phase")
		t.check(not SallySmokingState.end_turn(p,boosted+1,false), "I05e4a unrelated END cannot consume gender deadline")
		t.check(SallySmokingState.end_turn(p,boosted,false) and p.gender == "female" and not SallySmokingState.doubles_response(p,boosted), "I05e4a boosted END restores female and expires boost")
		t.check(not SallySmokingState.end_turn(p,boosted,false) and SallySmokingState.cost(p) == 2, "I05e4a duplicate END rejected and successive fee escalates")
		p.free()
	await operation(t)

func operation(t):
	for count in [0,1,2,3,4]:
		for surgery in [false,true]:
			var p = player(); p.sally_smoking_enabled = true; p.sally_surgery_enabled = surgery
			p.sally_smoke_uses = count
			var allowed = surgery and count >= 3
			t.check(SallySmokingState.can_operate(p) == allowed and SallySmokingState.note_operation_paid(p) == allowed, "I05e4a three-smoking surgery threshold has an independent capability")
			t.check(SallySmokingState.cost(p) == count+1 and p.hp == 3 and p.hand_size() == 0, "I05e4a state helper neither pays surgery card nor waives current fee early")
			t.check(SallySmokingState.start_turn(p,20,false) and SallySmokingState.cost(p) == count+1, "I05e4a smoking START helper cannot authorize the separate operation boundary")
			t.check(SallySmokingState.establish_operation(p) == allowed, "I05e4a caller-authorized future operation boundary commits only a paid pending operation")
			t.check(SallySmokingState.cost(p) == (0 if allowed else count+1), "I05e4a paid operation's future zero fee query")
			p.restore_game_start_state()
			t.check(not p.sally_surgery_active and not p.sally_surgery_pending and p.sally_smoke_uses == 0 and SallySmokingState.cost(p) == 1, "I05e4a opening snapshot clears surgery/pending/counters")
			p.mark_dead()
			t.check(not SallySmokingState.can_smoke(p) and not SallySmokingState.can_operate(p) and not SallySmokingState.start_turn(p,30,false), "I05e4a dead body cannot receive state transitions")
			p.free()
