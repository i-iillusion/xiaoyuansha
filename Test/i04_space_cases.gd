extends RefCounted

func pure(t):
	for count in range(2,11):
		var state = MountainSpace.new()
		var seats: Array[int] = []
		seats.assign(range(count))
		t.check(state.initialize(seats), "I04b persistent space initializes supported roster")
		t.check(not state.initialize(seats), "I04b cannot overwrite a live spatial ledger")
		t.check(state.place("a",0,1,seats) and state.place("b",0,1,seats), "I04b same-gap double placement")
		t.check(not state.place("c",0,1,seats), "I04b global two-mountain cap")
		var view = state.snapshot(seats)
		t.check(view.player_distance(0,1) == count-1, "I04b mountain marker is not a distance step")
		var before = state.markers()
		t.check(not state.move("a",1,1,seats) and state.markers() == before, "I04b invalid movement leaves state atomic")
		var copy = state.markers()
		copy.clear()
		t.check(state.markers() == before, "I04b exported marker list cannot alias state")
		t.check(state.remove("a") and not state.remove("a") and state.ids() == ["b"], "I04b removal is idempotent without a second gameplay event")
		t.check(view.placements().size() == 2, "I04b old query snapshot does not mutate with live state")
		state.reset()
		t.check(state.markers().is_empty() and state.ids().is_empty() and state.snapshot(seats) == null, "I04b reset invalidates old positions")
		t.check(state.initialize(seats) and state.snapshot(seats).placements().is_empty(), "I04b clean restart retains no stale mountains")
	var state = MountainSpace.new()
	var seats: Array[int] = [0,1,2,3,4,5]
	state.initialize(seats)
	state.place("a",1,2,seats)
	state.place("b",3,4,seats)
	t.check(state.relocate_before(4,1), "I04 Q3 spatial relocation primitive")
	var view = state.snapshot(seats)
	t.check(view.order() == [0,4,1,2,3,5], "I04 Q3 immutable player IDs retain changed spatial order")
	t.check(view.placements() == [{"id":"a","left":1,"right":2},{"id":"b","left":3,"right":5}], "I04 Q3 mountain b stays D/F rather than following E")
	var live: Array[int] = [0,1,3,4,5]
	t.check(state.snapshot(live).placements()[0] == {"id":"a","left":1,"right":3}, "I04b final-dead boundary player projected out without moving the mountain")
	t.check(state.snapshot(seats).placements()[0].right == 2, "I04b projection never erases a retained player marker")
	t.check(state.snapshot([0]) == null and state.snapshot([0,99]) == null and state.snapshot([0,0]) == null, "I04b invalid/terminal projection never becomes an unblocked query")
	var before = state.markers()
	t.check(not state.relocate_before(0,0) and not state.relocate_before(99,1) and state.markers() == before, "I04b malformed relocation is atomic")
	t.check(state.move("a",5,0,seats) and state.snapshot(seats).placements()[0] == {"id":"a","left":5,"right":0}, "I04b authorized gap movement wraps around the circle")

func run(t):
	pure(t)
	var saved = [GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	var game = load("res://Test/h02_integration_cases.gd").new().fixture(t,6,GameModes.FREE_FOR_ALL)
	var owner = game.players[0]
	var first = game._spawn_mountain_at(owner,1,2)
	var second = game._spawn_mountain_at(owner,3,4)
	t.check(first != null and second != null and first.hp == 5 and first.max_hp == 5, "I04b internal registration creates 5/5 mountain bodies")
	t.check(first.gender == "none" and second.gender == "none", "I04 Q7 registered mountains have no gender, not Player's default male")
	var sword_user = game.players[1]
	sword_user.equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.CHIXIONG_SHUANGGU))
	var hand_before = sword_user.hand_size()
	for sex in ["male","female"]:
		sword_user.gender = sex
		t.check(not sword_user.is_opposite_gender_to(first) and not first.is_opposite_gender_to(sword_user), "I04 Q7 mountain is not opposite-sex to either gender")
		t.check(await game._prepare_strike_target(sword_user,first,false) and sword_user.hand_size() == hand_before and first.hand_size() == 0, "I04 Q7 target-preparation hook never activates dual-sword discard/draw on a mountain; not full strike gameplay")
	t.check(game.players.size() == 6 and first.seat_index == -1 and first.identity == "" and game.unit_registry.controller(game.unit_registry.id_for(first)) == null, "I04b ordinary mountain never becomes a fixed player or controlled actor")
	t.check(game._spawn_mountain_at(owner,0,1) == null and game.mountain_space.ids().size() == 2, "I04b third body rejection never leaves an orphan marker")
	t.check(game.ordinary_seat_distance(game.players[1],game.players[2]) == LivingTable.UNREACHABLE, "I04b production base-distance query uses the two-region snapshot")
	t.check(game.ordinary_seat_distance(game.players[1],first) == 1 and game.ordinary_seat_distance(game.players[2],first) == 1 and game.ordinary_seat_distance(game.players[1],second) == 4, "I04b production M6 distances 1/1/4")
	game.players[1].mount_minus = 4
	t.check(game.players[1].attack_distance_to(game.players[2]) == LivingTable.UNREACHABLE, "I04b horses preserve unreachable, not a finite cross-partition range")
	first.hp = 1
	t.check(game.ordinary_seat_distance(game.players[1],game.players[2]) == LivingTable.UNREACHABLE, "I04b wounded registered mountain still blocks")
	game.turn_manager.rounds.relocate_before(4,1)
	t.check(game.mountain_space.player_order() == game.turn_manager.rounds.space_order(), "I04b real RoundLedger signal mirrors player relocation exactly once")
	t.check(game._mountain_snapshot().placements()[1].left == 3 and game._mountain_snapshot().placements()[1].right == 5, "I04b production Q3 stays D/F")
	var dragon = FireDragonState.create_body()
	var dragon_id = game._register_unit_body(UnitRegistry.Kind.FIRE_DRAGON,dragon,owner)
	game.fire_dragon_state.attach(dragon_id)
	t.check(game.ordinary_seat_distance(dragon,game.players[2]) == game.ordinary_seat_distance(owner,game.players[2]), "I04b fire dragon inherits owner's blocked base anchor, never adds a vertex")
	t.check(game.ordinary_seat_distance(dragon,first) == game.ordinary_seat_distance(owner,first), "I04b fire dragon to mountain shares only owner's base anchor")
	first.hp = 0
	t.check(not game._retire_final_unit(first) and game.mountain_space.ids().size() == 2, "I04b dying is not a committed mountain death")
	first.mark_dead()
	t.check(game._retire_final_unit(first) and game.mountain_space.ids().size() == 1, "I04b final-death dispatch removes only its matching marker")
	t.check(game.ordinary_seat_distance(owner,game.players[2]) < LivingTable.UNREACHABLE, "I04b one remaining mountain allows the other route")
	var old_id = game.unit_registry.id_for(second)
	owner.mark_dead()
	game._remove_summoner_units(owner)
	t.check(game.mountain_space.ids().is_empty() and second.unit_disappeared and not second.is_dead(), "I04b owner final-death disappearance clears markers without mountain death")
	game.reset_game_over_state()
	t.check(game.mountain_space.markers().is_empty() and game.unit_registry.entry(old_id).is_empty(), "I04b technical reset clears registry and spatial handles together")
	var replacement = game._spawn_mountain_at(game.players[1],1,2)
	t.check(replacement != null and game.unit_registry.id_for(replacement) != old_id, "I04b same ledger restart creates only fresh positioned unit handles")
	t.check(game.turn_manager.rounds.get_signal_connection_list("space_relocated").size() == 1, "I04b same-ledger reset does not accumulate callback connections")
	var impostor = Player.new()
	impostor.seat_index = 1
	t.check(game.ordinary_seat_distance(impostor,replacement) == LivingTable.UNREACHABLE, "I04b copied seat cannot impersonate a spatial actor")
	impostor.free()
	var stale_ledger = game.turn_manager.rounds
	var new_ledger = RoundLedger.new()
	new_ledger.initialize(game.mountain_space.player_order())
	game.turn_manager.rounds = new_ledger
	t.check(game._ensure_mountain_space(), "I04b replacement authoritative ledger can bind identical current space")
	var before = game.mountain_space.markers()
	stale_ledger.relocate_before(5,1)
	t.check(game.mountain_space.markers() == before, "I04b stale ledger cannot relocate current match markers")
	new_ledger.relocate_before(5,1)
	t.check(game.mountain_space.player_order() == new_ledger.space_order(), "I04b current ledger still relocates after a stale notification")
	game.queue_free()
	await t.process_frame
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]
