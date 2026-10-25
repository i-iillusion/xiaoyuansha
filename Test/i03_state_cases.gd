extends RefCounted

func run(t):
	for count in [2, 5, 10]:
		var roster: Array[Player] = []
		for seat in count:
			var p = Player.new()
			p.identity = ""
			p.seat_index = seat
			p.hp = 3
			roster.append(p)
		roster[0].general_name = "克里斯·西弗"
		var registry = UnitRegistry.new()
		t.check(registry.initialize(roster), "I03 fixed roster initializes")
		var state = FireDragonState.new()
		t.check(state.initialize(registry) and not state.initialize(registry), "I03 state binds once")
		t.check(not state.grant_start_egg(roster[1]), "I03 no egg granted to other generals")
		t.check(state.grant_start_egg(roster[0]) and roster[0].fire_dragon_eggs == 1, "I03 Chris begins with one egg")
		t.check(not state.grant_start_egg(roster[0]), "I03 repeated start callback grants nothing")
		roster[0].capture_game_start_state()
		t.check(not state.can_summon(roster[0]), "I03 no free summon with no hand")
		roster[0].hand.assign([null, null])
		t.check(not state.can_summon(roster[0]), "I03 two cards insufficient")
		# Legitimate concrete resource: an equipment-zone crossbow transferred to
		# hand. Do not fabricate a stolen concrete Flash from an arbitrary hand.
		var resource = CardBase.create(CardData.CardSubType.LIANNU)
		roster[1].equip_card_to_slot("weapon", resource)
		roster[0].determined_cards.append(roster[1].remove_equipment("weapon"))
		t.check(not roster[1].equipment.has("weapon") and roster[0].determined_cards[0] == resource, "I03 transferred concrete equipment keeps its original resource")
		t.check(state.can_summon(roster[0]), "I03 both hand stores count toward three-card cost")
		t.check(state.can_heal(roster[0], roster[0], TurnManager.Phase.PLAY), "I03 own PLAY may pay an egg")
		t.check(not state.can_heal(roster[0], roster[1], TurnManager.Phase.PLAY) and not state.can_heal(roster[0], roster[0], TurnManager.Phase.DRAW), "I03 no another actor or DRAW authorization")
		roster[0].hp = -1
		t.check(state.can_heal(roster[0], roster[1], TurnManager.Phase.WAITING) and not state.can_summon(roster[0]), "I03 dying egg eligibility distinct from summon")
		roster[0].hp = 3
		t.check(state.spend_egg(roster[0]) and not state.spend_egg(roster[0]) and not state.can_summon(roster[0]), "I03 egg cannot underflow or be paid twice")
		roster[0].restore_game_start_state()
		t.check(roster[0].fire_dragon_eggs == 1 and roster[0].hand_size() == 3 and roster[0].determined_cards[0] == resource, "I03 general reset restores initial egg but preserves physical hand")
		var dragon = FireDragonState.create_body()
		t.check(dragon.hp == 3 and dragon.max_hp == 3 and dragon.hand_size() == 0 and dragon.identity == "" and dragon.seat_index == -1, "I03 dragon starts three HP, zero cards, no player identity")
		var id = registry.register(UnitRegistry.Kind.FIRE_DRAGON, dragon, roster[0])
		t.check(state.attach(id) and not state.attach(id), "I03 dragon attaches once")
		t.check(state.stealth_allows_target(id, dragon) and not state.is_revealed_to(id, dragon), "I03 Q6 self targeting is permitted without recording a USE or revelation")
		t.check(roster.all(func(p): return not state.stealth_allows_target(id, p)), "I03 self exemption never permits another character to target hidden dragon")
		t.check(state.has_dragon(roster[0]) and not state.can_summon(roster[0]), "I03 registered living dragon prevents another summon")
		t.check(state.draw_count(id) == 1 and dragon.hand_size() == 0 and roster[0].hand_size() == 3, "I03 own DRAW basis is one, never owner cards")
		for source in roster:
			t.check(not state.is_revealed_to(id, source), "I03 initial stealth independently for each character")
		var target_list: Array[Player] = [roster[1]]
		t.check(state.record_use(id, 10, target_list), "I03 established unit USE reveals specified target")
		t.check(state.is_revealed_to(id, roster[1]) and not state.is_revealed_to(id, roster[0]), "I03 revelation to B never reveals to A")
		dragon.hp = 1
		t.check(state.stealth_allows_target(id, dragon) and state.stealth_allows_target(id, roster[1]) and not state.stealth_allows_target(id, roster[0]), "I03 Q6 wounded dragon self Peach passes stealth gate while owner still cannot target it")
		dragon.hp = 3
		var outsider = Player.new()
		outsider.hp = 3
		var bad_targets: Array[Player] = [roster[0], outsider]
		t.check(not state.record_use(id, 11, bad_targets) and not state.is_revealed_to(id, roster[0]), "I03 invalid batch has no partial revelation")
		t.check(not state.stealth_allows_target(id, outsider) and not state.stealth_allows_target(id, null), "I03 self exemption cannot authorize outsider or null source")
		outsider.free()
		var self_targets: Array[Player] = [dragon]
		t.check(state.record_use(id, 11, self_targets) and state.is_revealed_to(id, dragon) and not state.is_revealed_to(id, roster[0]), "I03 actual self USE records only self, never globally reveals")
		var all_targets: Array[Player] = roster.duplicate()
		t.check(not state.record_use(id, 10, all_targets) and not state.is_revealed_to(id, roster[0]), "I03 replayed USE does not reveal new targets")
		t.check(state.record_use(id, 12, all_targets) and roster.all(func(p): return state.is_revealed_to(id, p)), "I03 AOE USE reveals all designated characters")
		t.check(state.begin_turn(id, 100) and state.turn_count(id) == 1 and roster[0].fire_dragon_eggs == 1, "I03 first own START no egg")
		t.check(not state.begin_turn(id, 100) and not state.begin_turn(id, 99), "I03 replayed or older START ignored")
		t.check(state.note_skipped_turn(id, 105) and state.turn_count(id) == 1 and roster[0].fire_dragon_eggs == 1, "I03 Q7 flipped second opportunity postpones egg without counting START")
		t.check(not state.note_skipped_turn(id, 105) and not state.begin_turn(id, 105), "I03 skipped receipt cannot repeat or be replayed as a real START")
		t.check(state.note_skipped_turn(id, 106) and state.turn_count(id) == 1 and roster[0].fire_dragon_eggs == 1, "I03 later skipped opportunity still cannot run deferred START")
		t.check(state.begin_turn(id, 110) and roster[0].fire_dragon_eggs == 2 and state.turn_count(id) == 2, "I03 second own START gives one egg")
		t.check(state.note_skipped_turn(id, 115) and state.turn_count(id) == 2 and roster[0].fire_dragon_eggs == 2, "I03 skipping after egg never duplicates award or advances START")
		t.check(state.begin_turn(id, 120) and roster[0].fire_dragon_eggs == 2, "I03 third own START does not repeat egg")
		roster[0].hp = 0
		t.check(state.draw_count(id) == 1 and state.is_revealed_to(id, roster[1]), "I03 dying summoner still retains dragon state")
		roster[0].hp = 3
		roster[0].mark_dead()
		registry.detach_final_summoner(roster[0])
		t.check(not state.begin_turn(id, 130) and not state.record_use(id, 13, all_targets) and state.draw_count(id) == 0, "I03 final summoner loss rejects old actions and START")
		t.check(not state.is_revealed_to(id, roster[1]) and not state.spend_egg(roster[0]), "I03 detached objects have no live relation or spend permission")
		t.check(not state.note_skipped_turn(id, 130), "I03 detached dragon rejects skipped opportunity receipts")
		t.check(not state.stealth_allows_target(id, dragon), "I03 self exemption cannot revive detached unit permission")
		state.reset()
		t.check(state.turn_count(id) == 0 and not state.attach(id) and not state.begin_turn(id, 140), "I03 reset invalidates all state handles")
		t.check(not state.stealth_allows_target(id, dragon), "I03 reset rejects old self target handles")
		t.check(not state.note_skipped_turn(id, 140), "I03 reset rejects old skipped opportunity receipts")
		dragon.free()
		for p in roster: p.free()
	await _replacement_cases(t)

func _replacement_cases(t):
	var owner = Player.new()
	owner.identity = ""
	owner.general_name = "克里斯·西弗"
	owner.hp = 3
	owner.hand.assign([null, null, null])
	var registry = UnitRegistry.new()
	var roster: Array[Player] = [owner]
	registry.initialize(roster)
	var state = FireDragonState.new()
	state.initialize(registry)
	state.grant_start_egg(owner)
	var mountain = Player.new()
	mountain.identity = ""
	mountain.hp = 5
	var mountain_id = registry.register(UnitRegistry.Kind.MOUNTAIN, mountain, owner)
	t.check(not state.attach(mountain_id), "I03 mountain cannot gain dragon turn, draw or stealth state")
	var dragon = FireDragonState.create_body()
	var id = registry.register(UnitRegistry.Kind.FIRE_DRAGON, dragon, owner)
	dragon.hand.append(null)
	t.check(not state.attach(id), "I03 reject nonempty initial dragon hand without changing it")
	dragon.hand.clear()
	t.check(state.attach(id), "I03 valid initial body can attach after failed precheck")
	state.begin_turn(id, 1)
	dragon.hp = 0
	t.check(not state.begin_turn(id, 2) and state.draw_count(id) == 0 and state.has_dragon(owner), "I03 dying body cannot START or draw but still occupies dragon limit")
	dragon.hp = 1
	t.check(state.begin_turn(id, 2) and owner.fire_dragon_eggs == 2, "I03 rescued body keeps first turn receipt and earns second-turn egg")
	dragon.hp = 0
	dragon.mark_dead()
	registry.retire_dead(id)
	t.check(not state.begin_turn(id, 3) and not state.has_dragon(owner) and state.can_summon(owner), "I03 normal final dragon death releases cap, rejects old receipts")
	var next_dragon = FireDragonState.create_body()
	var next_id = registry.register(UnitRegistry.Kind.FIRE_DRAGON, next_dragon, owner)
	t.check(next_id != id and state.attach(next_id), "I03 replacement dragon starts a fresh ID and state")
	var targets: Array[Player] = [owner]
	t.check(not state.is_revealed_to(next_id, owner) and state.record_use(next_id, 1, targets), "I03 action receipt and revelation independent for replacement dragon")
	t.check(state.begin_turn(next_id, 1) and owner.fire_dragon_eggs == 2, "I03 replacement first START no egg")
	t.check(state.begin_turn(next_id, 2) and owner.fire_dragon_eggs == 3, "I03 each replacement second START awards only its own egg")
	registry.reset()
	t.check(not state.record_use(next_id, 2, targets) and not state.begin_turn(next_id, 3), "I03 registry reset also invalidates state receipts")
	registry.initialize(roster)
	t.check(not state.spend_egg(owner) and not state.grant_start_egg(owner) and not state.can_summon(owner), "I03 old state cannot spend resources even if owner object reused in new registry epoch")
	state.reset()
	t.check(state.initialize(registry) and state.grant_start_egg(owner) and owner.fire_dragon_eggs == 1, "I03 new match can initialize once again")
	owner.free()
	mountain.free()
	dragon.free()
	next_dragon.free()
