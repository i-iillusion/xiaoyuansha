extends RefCounted

func run(t):
	for count in [2, 5, 10]:
		var roster: Array[Player] = []
		for seat in count:
			var p = Player.new()
			p.seat_index = seat
			p.identity = ""
			p.hp = 3
			roster.append(p)
		var registry = UnitRegistry.new()
		registry.initialize(roster)
		var dragon = FireDragonState.create_body()
		var id = registry.register(UnitRegistry.Kind.FIRE_DRAGON, dragon, roster[0])
		var mountain = Player.new()
		mountain.identity = ""
		mountain.hp = 5
		var mountain_id = registry.register(UnitRegistry.Kind.MOUNTAIN, mountain, roster[0])
		for p in roster:
			t.check(ActorIdentity.key_for(roster, registry, p) == p.seat_index and ActorIdentity.resolve_live(roster, registry, p.seat_index) == p, "I03 fixed actor key retains permanent seat")
		t.check(ActorIdentity.key_for(roster, registry, dragon) == id and ActorIdentity.resolve_live(roster, registry, id) == dragon, "I03 intelligent actor resolves independent string ID")
		t.check(ActorIdentity.controller(roster, registry, dragon) == roster[0] and dragon.seat_index == -1 and dragon.identity == "", "I03 controller is not dragon's seat or identity")
		t.check(ActorIdentity.position_body(roster, registry, dragon) == roster[0] and ActorIdentity.position_body(roster, registry, roster[1]) == roster[1], "I03 base position anchor maps dragon without adding a seat")
		t.check(ActorIdentity.key_for(roster, registry, mountain) == null and ActorIdentity.resolve_live(roster, registry, mountain_id) == null and ActorIdentity.controller(roster, registry, mountain) == null, "I03 mountain cannot acquire actor/controller through membership")
		for key in [-1, count, true, 0.0, "0", "unit:unknown", null]:
			t.check(ActorIdentity.resolve_live(roster, registry, key) == null, "I03 malformed actor key cannot alias a player or unit")
		var outsider = Player.new()
		outsider.seat_index = 0
		t.check(ActorIdentity.key_for(roster, registry, outsider) == null and ActorIdentity.controller(roster, registry, outsider) == null, "I03 copied seat field does not authorize outsider")
		outsider.free()
		dragon.hp = 0
		t.check(ActorIdentity.resolve_live(roster, registry, id) == dragon, "I03 dying intelligent actor remains member for ordinary rescue")
		dragon.mark_dead()
		t.check(ActorIdentity.key_for(roster, registry, dragon) == id and ActorIdentity.resolve_live(roster, registry, id) == null, "I03 retained identity does not authorize final-dead body")
		registry.retire_dead(id)
		t.check(ActorIdentity.controller(roster, registry, dragon) == null and ActorIdentity.position_body(roster, registry, dragon) == null, "I03 retired dragon has no active input or position mapping")
		var replacement = FireDragonState.create_body()
		var next_id = registry.register(UnitRegistry.Kind.FIRE_DRAGON, replacement, roster[0])
		t.check(next_id != id and ActorIdentity.resolve_live(roster, registry, id) == null and ActorIdentity.resolve_live(roster, registry, next_id) == replacement, "I03 resummon cannot reuse old actor key")
		roster[0].hp = 0
		t.check(ActorIdentity.controller(roster, registry, replacement) == roster[0], "I03 controller dying is not final disappearance")
		roster[0].mark_dead()
		registry.detach_final_summoner(roster[0])
		t.check(ActorIdentity.resolve_live(roster, registry, next_id) == null and ActorIdentity.controller(roster, registry, replacement) == null, "I03 final summoner loss invalidates unit authority")
		registry.reset()
		registry.initialize(roster)
		t.check(ActorIdentity.key_for(roster, registry, replacement) == null and ActorIdentity.resolve_live(roster, registry, next_id) == null, "I03 registry epoch rejects old unit references and keys")
		t.check(roster.size() == count and roster.back().seat_index == count - 1, "I03 mapping never mutates permanent roster or seats")
		dragon.free()
		replacement.free()
		mountain.free()
		for p in roster: p.free()
	await input_mapping(t)

func input_mapping(t):
	var game = GameManager.new()
	var first = Player.new()
	first.identity = ""
	first.seat_index = 0
	first.hp = 3
	game.players.append(first)
	var owner = Player.new()
	owner.identity = ""
	owner.seat_index = 1
	owner.hp = 3
	game.players.append(owner)
	game.unit_registry.initialize(game.players)
	game.lan_enabled = true
	var dragon = FireDragonState.create_body()
	var id = game.unit_registry.register(UnitRegistry.Kind.FIRE_DRAGON, dragon, owner)
	t.check(game._is_human(dragon), "I03 actual human query resolves dragon's controller")
	game._set_input_player(dragon)
	t.check(game._input_seat == 1, "I03 actual input bank stays at fixed controller seat")
	dragon.mark_dead()
	game.unit_registry.retire_dead(id)
	game._input_seat = 0
	game._set_input_player(dragon)
	t.check(not game._is_human(dragon) and game._input_seat == 0, "I03 actual input rejects retired unit controller")
	game.free()
	dragon.free()
	owner.free()
	first.free()
