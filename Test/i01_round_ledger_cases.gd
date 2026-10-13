extends RefCounted

func run(t):
	for count in range(2, 11):
		var ids: Array[int] = []
		for seat in count: ids.append(seat)
		var ledger = RoundLedger.new()
		t.check(ledger.initialize(ids) and not ledger.initialize(ids), "I01b unique fixed roster initializes once")
		for seat in count:
			t.check(ledger.begin_next(ids) == seat and ledger.round_id == 1, "I01b ordinary order stays in first round")
			t.check(ledger.begin_next(ids) == -1, "I01b active turn cannot be silently replaced")
			var remaining = ledger.pending_seats()
			t.check(ledger.begin_extra((seat + 1) % count), "I01b authorized extra frame starts")
			t.check(ledger.begin_extra(seat), "I01b nested extra frame starts")
			t.check(ledger.finish().kind == RoundLedger.Kind.EXTRA and ledger.current().kind == RoundLedger.Kind.EXTRA, "I01b nested interruption unwinds its own frame")
			t.check(ledger.finish().kind == RoundLedger.Kind.EXTRA and ledger.current().seat == seat and ledger.pending_seats() == remaining, "I01b extra turns resume ordinary without consuming its quota")
			t.check(ledger.finish().seat == seat, "I01b normal or facedown skip completes exactly one ordinary quota")
			t.check(ledger.fixed_seats() == ids, "I01b no renumbering while executing")
		t.check(ledger.begin_next(ids) == 0 and ledger.round_id == 2, "I01b R1 final facedown skip permits next round")
		ledger.finish()
		var copy = ledger.space_order()
		copy.clear()
		t.check(ledger.space_order() == ids, "I01b external value snapshots cannot edit spatial order")

	var live: Array[int] = [0, 1, 2, 3, 4]
	var ledger = RoundLedger.new()
	ledger.initialize(live)
	for i in 3:
		ledger.begin_next(live)
		ledger.finish()
	live.erase(0)
	t.check(ledger.begin_next(live) == 3 and ledger.round_id == 1, "I01b R2 head death does not restart incomplete round")
	ledger.finish()
	t.check(ledger.begin_next(live) == 4, "I01b R2 remaining last player still acts")
	ledger.finish()
	t.check(ledger.begin_next(live) == 1 and ledger.round_head == 1 and ledger.round_id == 2 and ledger.fixed_seats() == [0,1,2,3,4], "I01b R2 new head retains permanent opening seat")
	ledger.finish()

	live = [0, 1, 2, 3, 4]
	ledger = RoundLedger.new()
	ledger.initialize(live)
	ledger.begin_next(live)
	ledger.finish()
	t.check(ledger.relocate_before(4, 1) and ledger.space_order() == [0,4,1,2,3], "I01b R4/R5 authorized relocation changes space not identity")
	for seat in [4,1,2,3]:
		t.check(ledger.begin_next(live) == seat and ledger.round_id == 1, "I01b relocated order uses each pending ordinary quota once")
		ledger.finish()
	t.check(ledger.begin_next(live) == 0 and ledger.round_id == 2 and ledger.space_order() == [0,4,1,2,3], "I01b R5 new round preserves spatial placement")
	ledger.finish()
	t.check(ledger.begin_next(live) == 4, "I01b R5 successor follows permanent spatial placement")
	ledger.finish()
	t.check(not ledger.relocate_before(4,4) and not ledger.relocate_before(9,1), "I01b invalid placements reject without mutation")

	ledger = RoundLedger.new()
	ledger.initialize(live)
	ledger.begin_next(live)
	ledger.finish()
	live.erase(4)
	for seat in [1,2,3]:
		t.check(ledger.begin_next(live) == seat, "I01b dead unprocessed player is removed from ordinary quota")
		ledger.finish()
	t.check(ledger.begin_next(live) == 0 and ledger.round_id == 2, "I01b final-seat death cannot strand round")
	t.check(ledger.begin_next([]) == -1 and not ledger.begin_extra(99), "I01b invalid request cannot create extra/empty turn")
	var invalid: Array[int] = [0,0]
	t.check(not RoundLedger.new().initialize(invalid), "I01b duplicate permanent IDs rejected")
