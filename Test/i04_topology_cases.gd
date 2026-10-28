extends RefCounted

func mountain(id: String, left: int, right: int) -> Dictionary:
	return {"id": id, "left": left, "right": right}

func gather_without_other_units(topology: MountainTopology) -> Dictionary:
	return topology.gather_for_players()

func run(t):
	var topology = MountainTopology.new()
	var order: Array = [0,1,2,3,4,5]
	var mounts: Array = [mountain("甲",1,2), mountain("乙",3,4)]
	t.check(topology.configure(order, mounts), "I04 M1 two distinct legal player gaps accepted")
	for a in order:
		for b in order:
			var together = ([2,3].has(a) == [2,3].has(b))
			t.check(topology.same_region(a,b) == together, "I04 M2 ABEF/CD bidirectional partition %s->%s" % [a,b])
			t.check((topology.player_distance(a,b) == MountainTopology.UNREACHABLE) == not together, "I04 S1 cross-region is unreachable, never ordinary finite range")
	t.check(topology.player_distance(1,5) == 2 and topology.player_distance(2,3) == 1, "I04 M2 same-region routes retain ordinary steps")
	t.check(topology.mountain_distance(1,"甲") == 1 and topology.mountain_distance(2,"甲") == 1 and topology.mountain_distance(1,"乙") == 4, "I04 M6 exact B/ C to mountain distances 1/1/4")
	t.check(gather_without_other_units(topology).heal == [2,3] and gather_without_other_units(topology).lose == [0,1,4,5], "I04 M4 unequal sides select smaller heal and larger HP-loss membership")
	# Snapshot has no HP field: merely injuring a mountain cannot open its gap.
	var before = topology.player_distance(1,2)
	t.check(before == MountainTopology.UNREACHABLE and topology.placements() == mounts, "I04 M3 presence-only snapshot retains both blocking mountains; actual HP lifecycle is a later integration case")
	t.check(topology.configure(order, [mounts[0]]) and topology.player_distance(1,2) == 5, "I04 M3 one remaining B/C mountain makes six-player B->C five")
	t.check(gather_without_other_units(topology) == {"heal":[],"lose":[]}, "I04 M4 one mountain cannot gather")
	var five: Array = [0,1,2,3,4]
	t.check(topology.configure(five,[mountain("甲",0,1)]), "I04 S1 five-player one-mountain setup accepted")
	for pair in [[4,1],[3,2],[2,3],[1,4]]:
		t.check(topology.player_distance(0,pair[0]) == pair[1], "I04 S1 A->E/D/C/B exact unblocked route")
	var single: Array = []
	for a in five:
		for b in five: single.append(topology.player_distance(a,b))
	t.check(topology.configure(five,[mountain("甲",0,1),mountain("乙",0,1)]), "I04 M1 same-gap distinct mountains accepted without overlap ban from mines")
	var cursor := 0
	for a in five:
		for b in five:
			t.check(topology.player_distance(a,b) == single[cursor], "I04 M5 same-gap double mountains equal single-mountain distance for every pair")
			cursor += 1
	t.check(gather_without_other_units(topology).heal.is_empty() and gather_without_other_units(topology).lose == five, "I04 M4 empty side only permits populated-side HP loss")
	t.check(topology.configure(order,[mountain("甲",1,2),mountain("乙",4,5)]) and gather_without_other_units(topology) == {"heal":[],"lose":[]}, "I04 M4 equal three-player sides forbid both gather choices")
	t.check(topology.gather_options([3,4]).heal == [2,3,4] and topology.gather_options([3,4]).lose == [0,1,5], "I04 external participant counts are explicit inputs, not an invented summon-count policy")
	t.check(topology.gather_for_players() == {"heal":[],"lose":[]}, "I04 Q5 public Gather query ignores a fire dragon behind B: fixed players remain 3 versus 3")
	t.check(topology.order() == order and topology.sides() == [[2,3,4],[0,1,5]], "I04 Q5 fire dragon never adds a spatial vertex or changes either player's side")
	t.check(topology.configure(five,[mountain("甲",1,2),mountain("乙",4,0)]), "I04 Q6 smaller AB versus larger CDE setup")
	t.check(not topology.same_region(0,2) and topology.gather_for_players().lose == [2,3,4], "I04 Q6 Gather supplies CDE across partition without granting ordinary cross-region reachability")
	for invalid_counts in [null, [], [3], [3,4,5], [2,3], [3,"4"], [3,4.0]]:
		t.check(topology.gather_options(invalid_counts) == {"heal":[],"lose":[]}, "I04 missing/invalid role counts never default silently to player-only counts")
	# Two-player circles have two different directed gaps between the same pair.
	t.check(topology.configure([0,1],[mountain("甲",0,1)]) and topology.player_distance(0,1) == 1, "I04 two-player single blocked arc leaves the other arc")
	t.check(topology.configure([0,1],[mountain("甲",0,1),mountain("乙",1,0)]) and not topology.same_region(0,1), "I04 two-player distinct gaps enclose separate one-player regions")
	t.check(gather_without_other_units(topology) == {"heal":[],"lose":[]}, "I04 two equal one-player sides forbid gather")
	# Current spatial IDs, not immutable numeric ordering or screen pixels.
	t.check(topology.configure([0,4,1,2,3],[mountain("甲",0,4)]) and topology.player_distance(0,4) == 4, "I04 explicit spatial snapshot preserves permanent IDs without sorting them")
	var saved_order = topology.order()
	var saved_mounts = topology.placements()
	for bad in [null, {"center":true}, [mountain("x",0,1)], [mountain("x",0,4),mountain("x",1,2)], [mountain("x",0,4),mountain("y",0,4),mountain("z",1,2)], [{"id":"x","left":0,"right":4,"hp":4}], [mountain("x",4,0)]]:
		t.check(not topology.configure(saved_order,bad) and topology.order() == saved_order and topology.placements() == saved_mounts, "I04 rejects invalid/center/duplicate/over-cap/nonadjacent placement atomically")
	for bad in [[],[0],[0,0],[0,"1"],[-1,0],range(11)]:
		t.check(not topology.configure(bad,[]) and topology.order() == saved_order, "I04 malformed or unsupported snapshot cannot partially overwrite current geometry")
	var external = topology.placements()
	external[0].left = 99
	var external_order = topology.order()
	external_order.reverse()
	t.check(topology.placements() == saved_mounts and topology.order() == saved_order, "I04 exported values cannot mutate topology")
	var source: Array = [0,1,2,3,4]
	var positions: Array = [mountain("甲",0,1)]
	t.check(topology.configure(source,positions), "I04 isolated input-copy fixture accepted")
	source.reverse()
	positions[0].right = 99
	t.check(topology.player_distance(0,1) == 4 and topology.mountain_distance(0,"unknown") == MountainTopology.UNREACHABLE and topology.player_distance(99,1) == MountainTopology.UNREACHABLE, "I04 input copies and unknown IDs never alias valid geometry")
	for count in range(2,11):
		var seats: Array = range(count)
		t.check(topology.configure(seats,[]), "I04 supported count blank snapshot: " + str(count))
		for a in seats:
			for b in seats:
				var gap = absi(a-b)
				t.check(topology.player_distance(a,b) == mini(gap,count-gap), "I04 no-mountain distance matches ordinary circle at every supported count")
