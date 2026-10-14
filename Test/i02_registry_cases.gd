extends RefCounted

func run(t):
	for count in range(2, 11):
		var roster: Array[Player] = []
		for seat in range(count):
			var player = Player.new()
			player.seat_index = seat
			player.identity = ""
			player.hp = 4
			roster.append(player)
		var registry = UnitRegistry.new()
		t.check(registry.initialize(roster), "I02b initializes fixed player roster")
		var dragon = Player.new()
		dragon.identity = ""
		dragon.hp = 3
		var mountain = Player.new()
		mountain.identity = ""
		mountain.hp = 5
		var dragon_id = registry.register(UnitRegistry.Kind.FIRE_DRAGON, dragon, roster[0])
		var mountain_id = registry.register(UnitRegistry.Kind.MOUNTAIN, mountain, roster[0])
		t.check(not dragon_id.is_empty() and dragon_id != mountain_id, "I02b separate unit ID namespace")
		t.check(registry.players() == roster and registry.players().size() == count, "I02b units never enter player rows")
		t.check(registry.controller(dragon_id) == roster[0] and registry.controller(mountain_id) == null, "I02b summoner attachment differs from intelligent control")
		t.check(registry.turn_units() == [dragon], "I02b only intelligent unit has turn eligibility")
		t.check(registry.strike_unit_candidates() == [dragon, mountain] and registry.character_unit_candidates() == [dragon], "I02b target categories distinct, not final legality")
		for query in [registry.zhuangsha_count_participants, registry.science_count_participants, registry.yudaxi_candidates, registry.victory_roster]:
			t.check(query.call() == roster, "I02b explicit count/yudaxi/victory sets exclude units")
		t.check(registry.register(99, dragon, roster[0]).is_empty() and registry.register(UnitRegistry.Kind.FIRE_DRAGON, dragon, roster[0]).is_empty(), "I02b unsupported and duplicate registration rejected")
		t.check(registry.register(UnitRegistry.Kind.FIRE_DRAGON, roster[1], roster[0]).is_empty(), "I02b player cannot become a registered unit")
		var copy = registry.entry(dragon_id)
		copy.removed = true
		var copied_roster = registry.players()
		copied_roster.clear()
		t.check(not registry.entry(dragon_id).removed and registry.players().size() == count, "I02b callers cannot mutate registry through returned containers")
		roster[0].hp = 0
		t.check(registry.detach_final_summoner(roster[0]).is_empty() and registry.active_units().size() == 2, "I02b dying owner does not remove units")
		roster[0].hp = 1
		t.check(registry.active_units().size() == 2, "I02b rescue or successful yudaxi keeps attachments")
		roster[0].hp = 0
		roster[0].mark_dead()
		var events = registry.detach_final_summoner(roster[0])
		t.check(events.size() == 2 and events.all(func(event): return event.reason == UnitRegistry.Removal.SUMMONER_LOST), "I02b final death yields only disappearance events")
		t.check(not dragon.is_dead() and not mountain.is_dead() and registry.active_units().is_empty(), "I02b disappearance does not fabricate normal death")
		t.check(registry.detach_final_summoner(roster[0]).is_empty() and registry.retire_dead(dragon_id).is_empty(), "I02b no duplicate cleanup or later death event")
		t.check(registry.controller(dragon_id) == null and registry.turn_units().is_empty(), "I02b disappeared units lose membership and control")
		registry.reset()
		t.check(registry.initialize(roster) and registry.entry(dragon_id).is_empty(), "I02b reset invalidates old ID")
		var new_id = registry.register(UnitRegistry.Kind.MOUNTAIN, mountain, roster[1])
		t.check(not new_id.is_empty() and new_id != mountain_id, "I02b new match IDs do not reuse old handles")
		mountain.hp = 0
		t.check(registry.retire_dead(new_id).is_empty(), "I02b dying unit is not yet a normal death")
		mountain.mark_dead()
		t.check(registry.retire_dead(new_id).get("reason", -1) == UnitRegistry.Removal.NORMAL_DEATH, "I02b true unit death distinguished from attached disappearance")
		t.check(registry.retire_dead(new_id).is_empty(), "I02b true death notification at most once")
		dragon.free()
		mountain.free()
		for player in roster: player.free()
