extends RefCounted

func roster(count: int) -> Array[Player]:
	var result: Array[Player] = []
	for role in GameModes.roles(GameModes.AMBITIOUS, count):
		var p = Player.new()
		p.identity = role
		p.identity_revealed = role == "主公"
		p.player_name = "P%d" % result.size()
		p.seat_index = result.size()
		p.hp = 4
		p.capture_game_start_state()
		result.append(p)
	return result

func die(p: Player):
	p.hp = 0
	p.mark_dead()

func free_roster(players: Array[Player]):
	for p in players: p.free()

func run(t):
	for count in [6, 8, 10]:
		var players := roster(count)
		var state = AmbitiousIdentityState.new()
		t.check(state.initialize(players) and state.valid(), "H03b trusted %d-player opening" % count)
		t.check(not state.initialize(players), "H03b no second initialization")
		var successor: Player = players.back()
		successor.hp = 2
		var concrete = CardBase.create(CardData.CardSubType.PEACH)
		successor.hand.append(null)
		successor.determined_cards.append(concrete)
		t.check(state.evaluate().is_empty() and state.candidate() == null, "H03b no premature victory or declaration")
		t.check(not state.declare() and not state.decline() and successor.hp == 2, "H03b lord alive cannot succeed")
		die(players[0])
		t.check(state.candidate() == successor and state.evaluate().is_empty(), "H03b lord dead waits for declaration before rebels")
		var observed: Array[bool] = []
		successor.hp_changed.connect(func(_hp):
			observed.append(state.valid() and state.declaration == AmbitiousIdentityState.Declaration.ACCEPTED
				and players[1].identity == "内奸" and successor.identity_revealed))
		t.check(state.declare(), "H03b declaration commits")
		t.check(successor.hp == 3 and successor.max_hp == 5 and successor.identity_max_hp_bonus == 1, "H03-Q1 2/4 becomes 3/5")
		t.check(successor.hand == [null] and successor.determined_cards == [concrete], "H03b succession neither clears nor recreates arbitrary/concrete hand cards")
		t.check(observed == [true], "H03b hp observer never sees partial conversion")
		t.check(not GameModes.valid_opening(GameModes.AMBITIOUS, count, players.map(func(p): return p.identity)) and state.valid(), "H03b transformed state is not constrained by opening counts")
		t.check(state.evaluate().is_empty(), "H03b dead old lord does not end living successor's game")
		for p in players:
			var own = PlayerObservation.capture(players, p, 0, 0)
			for row in own.players:
				var subject: Player = players[row.seat]
				var expected = subject.identity if subject == p or subject == successor or subject == players[0] else ""
				t.check(row.identity == expected, "H03-Q2 converted identity visible only to owner, new lord public")
		var before := successor.hp
		t.check(not state.declare() and not state.decline() and successor.hp == before, "H03b repeated answer cannot heal twice")
		for p in players:
			if p.identity in ["反贼", "内奸"] and not p.is_dead(): die(p)
		t.check(state.evaluate().get("winner") == "主公", "H03b successor wins when transformed enemies dead")
		free_roster(players)

	for count in [6, 8, 10]:
		var players := roster(count)
		var state = AmbitiousIdentityState.new()
		state.initialize(players)
		die(players[0])
		t.check(state.decline() and state.evaluate().get("winner") == "反贼", "H03b refusal yields rebel victory")
		t.check(not state.declare() and not state.decline() and players.back().identity == "奸雄", "H03b refusal cannot be revoked")
		free_roster(players)

	var players := roster(6)
	var state = AmbitiousIdentityState.new()
	state.initialize(players)
	die(players.back())
	t.check(state.candidate() == null and state.evaluate().is_empty(), "H03b ambitious dies first, no declaration")
	for p in players:
		if p.identity in ["反贼", "内奸"]: die(p)
	t.check(state.evaluate().get("winner") == "主公", "H03b dead ambitious restores standard lord victory")
	free_roster(players)

	players = roster(6)
	state = AmbitiousIdentityState.new()
	state.initialize(players)
	for p in players:
		if p.identity != "内奸": die(p)
	t.check(state.evaluate().get("winner") == "内奸", "H03b unique surviving traitor wins")
	free_roster(players)

	players = roster(6)
	state = AmbitiousIdentityState.new()
	state.initialize(players)
	die(players[1]) # dead loyalist does not change allegiance
	players[4].hp = 0 # P3 parent Leo: DYING is not final death
	die(players[0])
	t.check(state.declare() and players[1].identity == "忠臣" and players[4].identity == "忠臣", "H03b changes non-dead traitor, not dead loyalist")
	t.check(state.evaluate().is_empty(), "H03b unresolved dying parent defers victory")
	players[4].hp = 1
	var saved_role = players.back().identity
	players.back().restore_game_start_state()
	t.check(players.back().identity == saved_role and players.back().identity_revealed and players.back().max_hp == 5, "H03b model reset retains new identity and independent bonus")
	players[2].identity = "忠臣"
	t.check(not state.valid() and state.evaluate().is_empty(), "H03b unauthorized role mutation rejected")
	free_roster(players)

	players = roster(6)
	players[3].free()
	players[3] = players[2] # duplicate rebels retain a valid-looking role distribution
	t.check(not AmbitiousIdentityState.new().initialize(players), "H03b duplicate/invalid opening rejected")
	# Free each unique Node once.
	var unique: Array[Player] = []
	for p in players:
		if not unique.has(p): unique.append(p)
	free_roster(unique)
	players = roster(6)
	players[0].hp = 0
	t.check(not AmbitiousIdentityState.new().initialize(players), "H03b cannot register mid-dying opening")
	players[0].hp = 4
	state = AmbitiousIdentityState.new()
	t.check(state.initialize(players), "H03b valid opening after rejected initialization")
	die(players[0])
	t.check(state.declare() and players.back().hp == 5, "H03-Q1 full-health successor gains one hp, not only maximum")
	for p in players: die(p)
	t.check(state.evaluate().is_empty(), "H03b no invented identity total-annihilation result")
	free_roster(players)
	var empty: Array[Player] = []
	t.check(not AmbitiousIdentityState.new().initialize(empty), "H03b empty opening rejected")
	players = roster(6)
	players[1].identity = "unknown"
	t.check(not AmbitiousIdentityState.new().initialize(players), "H03b unknown role rejected")
	players[1].identity = "忠臣"
	var missing = players.pop_back()
	t.check(not AmbitiousIdentityState.new().initialize(players), "H03b unsupported five-player ambitious rejected")
	players.append(null)
	t.check(not AmbitiousIdentityState.new().initialize(players), "H03b null player rejected")
	players.pop_back()
	missing.free()
	free_roster(players)
	t.check(AmbitiousIdentityState.new().evaluate().is_empty(), "H03b uninitialized state never judges")
