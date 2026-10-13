extends RefCounted

func fixture(t) -> GameManager:
	var game: GameManager = load("res://Test/h02_integration_cases.gd").new().fixture(t, 6, GameModes.FREE_FOR_ALL)
	game.game_mode = GameModes.AMBITIOUS
	var roles = GameModes.roles(GameModes.AMBITIOUS, 6)
	for i in 6:
		game.players[i].identity = roles[i]
		game.players[i].identity_revealed = roles[i] == "主公"
	game._ambitious_state = AmbitiousIdentityState.new()
	assert(game._ambitious_state.initialize(game.players))
	return game

func dispose(t, game):
	game._game_over = true
	game.queue_free()
	await t.process_frame
	await t.process_frame

func start_death(game, p, done):
	await game._resolve_dying(p, null, "h03")
	done.value = true

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	for answer in [0, 1, -1]:
		var game = fixture(t)
		game._ambitious_declaration_override = func(_p): return answer
		var successor: Player = game.players[5]
		successor.hp = 2
		game.players[0].hp = 0
		await game._resolve_dying(game.players[0], null, "h03")
		t.check(game.players[0].is_dead() and game.players[0].hand_size() == 0, "H03c final lord death clears once")
		t.check(game._dying_contexts.is_empty(), "H03c death transaction fully releases")
		if answer == 0:
			t.check(not game._game_over and successor.identity == "主公" and successor.hp == 3 and successor.max_hp == 6, "H03c actual chain succeeds, base straw5 ->6")
			t.check(game.players[1].identity == "内奸" and game.players[4].identity == "忠臣", "H03c actual conversion")
		else:
			t.check(game._game_over and game._ambitious_state.declaration == AmbitiousIdentityState.Declaration.DECLINED, "H03c refusal/normal timeout completes victory")
		await dispose(t, game)
	var game = fixture(t)
	var before = game.players[2].hand_size()
	game.players[5].hp = 0
	await game._resolve_dying(game.players[5], game.players[2], "h03")
	t.check(game.players[2].hand_size() == before + 3, "H03c killing undeclared ambitious draws three")
	await game._handle_death(game.players[5], game.players[2])
	t.check(game.players[2].hand_size() == before + 3 and not game._game_over, "H03c duplicate death neither rewards twice nor ends early")
	await dispose(t, game)

	for choice in ["声明成为主公", "放弃声明", "timeout", "close"]:
		game = fixture(t)
		game.lan_enabled = true
		var bridge = LanGameBridge.new()
		t.root.add_child(bridge)
		bridge.game = game
		game.players[0].hp = 0
		var done = {"value": false}
		start_death(game, game.players[0], done)
		await t.process_frame
		var owner = bridge.snapshot(5)
		var other = bridge.snapshot(2)
		t.check(not done.value and not game._game_over and owner.owner == 5, "H03c actual declaration pauses final death, remote owner is ambitious")
		t.check(other.controls.is_empty() and not owner.controls.is_empty(), "H03c only owner gets declaration buttons")
		var button = owner.controls.filter(func(x): return x.text == "声明成为主公")[0]
		t.check(not bridge.submit(2, button.id), "H03c non-owner cannot answer")
		if choice == "timeout": game._countdown_on_timeout.call()
		elif choice == "close": game._choice_prompt_stack.back().overlay.queue_free()
		else:
			var selected = owner.controls.filter(func(x): return x.text == choice)[0]
			t.check(bridge.submit(5, selected.id), "H03c real owner button accepted")
		for i in 3: await t.process_frame
		t.check(done.value and game._choice_prompt_stack.is_empty(), "H03c independent window finishes and cleans up")
		t.check(not bridge.submit(5, button.id), "H03c consumed/old token rejected")
		if choice == "close":
			t.check(not game._game_over and game._ambitious_state.declaration == AmbitiousIdentityState.Declaration.UNRESOLVED, "H03c technical close is not refusal")
		elif choice == "声明成为主公":
			t.check(game.players[5].identity == "主公" and not game._game_over, "H03c real remote declaration converts before continuation")
		else:
			t.check(game._game_over and game.players[5].identity == "奸雄", "H03c real refusal/timeout preserves hidden identity")
		bridge.game = null
		bridge.queue_free()
		await dispose(t, game)

	# P3: parent Leo is still DYING when a child lord dies; succession precedes next loss.
	game = fixture(t)
	var p3_roles = ["内奸", "主公", "奸雄", "忠臣", "反贼", "反贼"]
	for i in 6:
		game.players[i].identity = p3_roles[i]
		game.players[i].identity_revealed = p3_roles[i] == "主公"
	game._ambitious_state = AmbitiousIdentityState.new()
	assert(game._ambitious_state.initialize(game.players))
	game.players[0].general_name = "里奥·普利威尔"
	game.players[1].hp = 2
	game.players[2].hp = 4
	var seen: Array[bool] = []
	game._ambitious_declaration_override = func(_p):
		seen.append(game.players[2].hp == 4 and game.players[0].is_dying() and game.yudaxi.is_active())
		return 0
	game.players[0].hp = 0
	await game._resolve_dying(game.players[0], null, "h03")
	t.check(seen == [true], "H03c P3 asks before next child loss while parent active")
	t.check(game.players[0].identity == "忠臣" and game.players[0].hp == 1 and game.players[2].hp == 3, "H03c P3 resumes, parent counts lord death and new lord gets +1 then -2")
	t.check(not game._game_over and game._dying_contexts.is_empty(), "H03c P3 no premature rebel victory")
	await dispose(t, game)
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]
