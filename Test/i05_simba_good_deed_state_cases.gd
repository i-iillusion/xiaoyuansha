extends RefCounted

func run(t):
	var owner = Player.new()
	var target = Player.new()
	owner.max_hp = 5
	owner.hp = 5
	target.max_hp = 4
	target.hp = 4
	owner.capture_game_start_state()
	target.capture_game_start_state()
	var signals_seen: Array = []
	target.hp_changed.connect(func(hp): signals_seen.append([hp, target.good_deed_marks]))
	t.check(target.receive_good_deed() and target.hp == 5 and target.max_hp == 4 and target.good_deed_marks == 1, "I05d extra HP exceeds cap without increasing maximum")
	t.check(signals_seen == [[5, 1]], "I05d HP observers see committed matching good-deed mark")
	t.check(target.receive_good_deed() and target.hp == 6 and target.good_deed_marks == 2, "I05d grants stack both actual HP and marks")
	target.heal(2)
	t.check(target.hp == 6, "I05d ordinary capped heal does not remove existing extra HP")
	owner.hp = 0
	target.hp = 1
	t.check(owner.reclaim_good_deeds_from(target) == 2, "I05d reclaim uses all original marks")
	t.check(owner.hp == 2 and owner.is_alive() and target.hp == -1 and target.is_dying() and target.good_deed_marks == 0, "I05d Q5b owner already recovered when target needs dying resolution")
	t.check(owner.reclaim_good_deeds_from(target) == 0 and owner.hp == 2 and target.hp == -1, "I05d same consumed marks cannot pay or heal twice")
	owner.hp = -2
	target.hp = 4
	target.good_deed_marks = 1
	t.check(owner.reclaim_good_deeds_from(target) == 1 and owner.hp == -1 and owner.is_dying(), "I05d first recovery can leave negative HP")
	var second = Player.new()
	second.hp = 4
	second.good_deed_marks = 2
	t.check(owner.reclaim_good_deeds_from(second) == 2 and owner.hp == 1 and owner.is_alive(), "I05d Q5c successive full reclaims may rescue the owner")
	owner.hp = 4
	target.good_deed_marks = 3
	t.check(owner.reclaim_good_deeds_from(target) == 3 and owner.hp == 5 and owner.max_hp == 5 and target.hp == 0, "I05d reclaim recovery is ordinary capped healing, target pays full X")
	target.restore_game_start_state()
	t.check(target.hp == 4 and target.good_deed_marks == 0, "I05d held marks reset with holder general state")
	target.receive_good_deed()
	owner.restore_game_start_state()
	t.check(target.good_deed_marks == 1 and target.hp == 5, "I05d giver reset does not reset another general's marks or HP")
	owner.simba_good_deeds_enabled = true
	owner.restore_game_start_state()
	t.check(owner.simba_good_deeds_enabled and owner.good_deed_marks == 0, "I05d server capability is separate from resettable mark state")
	for removed in [false, true]:
		target.hp = 1
		target.good_deed_marks = 2
		target.reset_death_state()
		target.unit_disappeared = removed
		if not removed: target.mark_dead()
		t.check(not target.receive_good_deed() and owner.reclaim_good_deeds_from(target) == 0 and target.hp == 1 and target.good_deed_marks == 2, "I05d final dead/disappeared bodies cannot gain HP or provide marks")
	target.unit_disappeared = false
	target.reset_death_state()
	owner.mark_dead()
	t.check(owner.reclaim_good_deeds_from(target) == 0 and owner.is_dead(), "I05d reclaim cannot revive a finally dead owner")
	t.check(owner.hand.is_empty() and owner.determined_cards.is_empty() and target.hand.is_empty(), "I05d marks and HP commits never create or pay cards")
	for body in [owner, target, second]: body.free()
	unit_view(t)

func unit_view(t):
	var owner = Player.new()
	owner.seat_index = 0; owner.hp = 5
	var other = Player.new()
	other.seat_index = 1; other.hp = 5
	var body = Player.new()
	body.identity = ""; body.gender = "none"; body.hp = 3; body.max_hp = 3
	var registry = UnitRegistry.new()
	var roster: Array[Player] = [owner, other]
	t.check(registry.initialize(roster) and not registry.register(UnitRegistry.Kind.FIRE_DRAGON, body, owner).is_empty(), "I05d intelligent unit has real independent registered body")
	var before = UnitObservation.capture(registry, owner)
	t.check(UnitObservation.valid(before, 2, 0) and not before[0].has("good_deed_marks"), "I05d zero-mark unit wire shape remains unchanged before opening")
	body.receive_good_deed()
	var after = UnitObservation.capture(registry, owner)
	t.check(UnitObservation.valid(after, 2, 0) and after[0].good_deed_marks == 1 and after[0].hp == 4 and owner.hp == 5 and owner.good_deed_marks == 0, "I05d extra HP and marks belong to unit, not controller; typed value packet retains them")
	var bad = after.duplicate(true)
	bad[0].good_deed_marks = "1"
	t.check(not UnitObservation.valid(bad, 2, 0), "I05d unit mark packet rejects untyped values")
	bad = after.duplicate(true); bad[0]["unknown_deed"] = 1
	t.check(not UnitObservation.valid(bad, 2, 0), "I05d optional mark extension does not accept arbitrary unit fields")
	for p in [owner, other, body]: p.free()
