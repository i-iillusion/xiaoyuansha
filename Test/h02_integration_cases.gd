extends RefCounted

func frames(t, count := 3):
	for i in count: await t.process_frame

func prepare(count, mode):
	GameManager.selected_players = count
	GameManager.selected_mode = mode
	GameManager.selected_general = "稻草人"
	GameManager.random_general = false
	GameManager.random_identity = false

func fixture(t, count, mode) -> GameManager:
	prepare(count, mode)
	var game = load("res://Scenes/Game.tscn").instantiate()
	game.auto_start = false
	t.root.add_child(game)
	game.start_game()
	game._halt_countdown()
	game._rescue_choice_override = func(_r, _d, _o): return -1
	game._sacrifice_override = func(): return false
	return game

func pure(t):
	# Test-only client strategy must not loop on a low-HP but out-of-range seat.
	var public_players: Array = []
	var public_targets = {}
	for seat in 10:
		public_players.append({"seat": seat, "hp": 1 if seat == 4 else (2 if seat == 9 else 5), "dead": false})
		public_targets[str(seat)] = "target-%d" % seat
	var visible = {"actor": 0, "players": public_players, "targets": public_targets, "targeting": true, "notice": "选择【决斗】目标", "controls": [], "revision": 1}
	var driver = load("res://Test/lan_autoplayer.gd").new()
	t.check(driver.choose(visible) == "target-9", "H02d public client concentrates on in-range neighbor, not distant lowest HP")
	public_players[9].dead = true
	public_players[8].hp = 2
	t.check(driver.choose(visible) == "target-8", "H02d public client recomputes neighbor after final death")
	for seat in range(1, 9): public_players[seat].dead = true
	public_players[9].dead = false
	t.check(driver.choose(visible) == "target-9", "H02d two survivors share one legal neighbor without duplicate target")
	visible.targeting = false
	visible.controls = [{"text": "决斗", "id": "duel", "disabled": false}, {"text": "结束出牌", "id": "end", "disabled": false}]
	t.check(driver.choose(visible) == "duel", "H02d public client selects first enabled duel")
	t.check(driver.choose(visible) == "duel", "H02d public client can use manual's second enabled duel")
	t.check(driver.choose(visible) == "end", "H02d public client ends after two duel selections, without exceeding limit")
	visible.controls = [{"text": "出【闪】", "id": "dodge", "disabled": false}, {"text": "不响应", "id": "decline", "disabled": false}]
	t.check(driver.choose(visible) == "decline", "H02d public client declines actual strike response wording without hanging")
	var basic_driver = load("res://Test/lan_autoplayer.gd").new()
	visible.controls = [{"text": "基本牌", "id": "basic", "disabled": false}, {"text": "锦囊牌", "id": "trick", "disabled": false}]
	t.check(basic_driver.choose(visible) == "basic", "H02d public client navigates actual basic selector")
	visible.controls = [{"text": "杀", "id": "strike", "disabled": false}, {"text": "酒", "id": "wine", "disabled": false}]
	t.check(basic_driver.choose(visible) == "wine", "H02d public client selects wine before strike despite button order")
	visible.labels = ["选择杀的属性"]
	t.check(basic_driver.choose(visible) == "strike", "H02d public client declares ordinary strike through actual variant selector")
	var identity_players: Array = []
	for seat in 9:
		identity_players.append({"seat": seat, "hp": 1 if seat == 1 else 6, "dead": false, "identity": "主公" if seat == 8 else ""})
	visible.players = identity_players
	visible.mode = GameModes.CLASSIC
	visible.targeting = true
	visible.notice = "选择【决斗】目标"
	visible.controls = []
	t.check(driver.choose(visible) == "target-8", "H02d identity client prefers only public in-range lord without hidden-role access")
	for count in [5, 7, 9]:
		for lord_at_end in [false, true]:
			for scenario in ["ongoing", "lord", "loyal", "renegade", "dying"]:
				var roles = GameModes.roles(GameModes.CLASSIC, count)
				if lord_at_end: roles.reverse()
				var players: Array[Player] = []
				for i in count:
					var p = Player.new()
					p.identity = roles[i]
					p.hp = 4
					p.seat_index = i
					p.player_name = "P%d" % i
					players.append(p)
				for p in players:
					if (scenario == "lord" and p.identity == "主公") or (scenario == "loyal" and p.identity in ["反贼", "内奸"]) or (scenario == "renegade" and p.identity != "内奸"):
						p.hp = 0
						p.mark_dead()
					if scenario == "dying" and p.identity == "主公": p.hp = -1
				var expected = {"ongoing": "", "lord": "反贼", "loyal": "主公", "renegade": "内奸", "dying": ""}[scenario]
				t.check(IdentityVictory.evaluate(players).get("winner", "") == expected, "H02c pure classic outcome independent of lord seat")
				players[0].identity = "奸雄"
				t.check(IdentityVictory.evaluate(players).is_empty(), "H02c ambitious role cannot bypass H03")
				for p in players: p.free()

func opening(t, entry):
	var game = fixture(t, entry.count, entry.mode)
	t.check(game.players.size() == entry.count and GameModes.valid_opening(entry.mode, entry.count, game.players.map(func(p): return p.identity)), "H02b actual opening has configured roles")
	t.check(game.players.all(func(p): return p.max_hp == (6 if p.identity == "主公" else 5) and p.hp == p.max_hp), "H02b initial lord bonus isolated from general base")
	t.check(game.players.all(func(p): return p.identity_revealed == (p.identity == "主公")) and game.turn_manager.current_player_idx == 0, "H02b only lord publicly revealed, fixed first seat preserved")
	for viewer in [0, entry.count - 1]:
		var state = PlayerObservation.capture(game.players, game.players[viewer], 0, 0)
		t.check(state.players.all(func(row): return row.identity == (game.players[row.seat].identity if row.seat == viewer or game.players[row.seat].identity_revealed else "")), "H02b own role known, other hidden roles private")
	var victims: Array = []
	if entry.mode != GameModes.FREE_FOR_ALL:
		victims = game.players.filter(func(p): return p.identity in ["反贼", "内奸", "奸雄"])
	else:
		victims = game.players.slice(1)
	var wins: Array = []
	game.game_over.connect(func(w): wins.append(w))
	for victim in victims:
		await game._deal_damage(null, victim, 20, EffectChain.DamageType.PHYSICAL)
	t.check(game._game_over and wins == [("主公" if entry.mode != GameModes.FREE_FOR_ALL else "玩家 1")], "H02c actual rescue/death pipeline reaches correct single terminal result")
	t.check(game._pending_card_actions.is_empty() and game._dying_contexts.is_empty(), "H02c death/terminal contexts clean")
	game.queue_free()
	await frames(t)

func menu(t):
	var previous = t.current_scene
	var adopt = func(node):
		if node is GameManager and node.get_parent() == t.root: node.auto_start = false
	t.node_added.connect(adopt)
	for entry in GameModes.catalog().filter(func(row): return row.playable):
		t.change_scene_to_file("res://Scenes/MainMenu.tscn")
		await frames(t)
		var main = t.current_scene
		MainMenu.random_mode = false
		main._show_test()
		var text = "%d人%s" % [entry.count, {GameModes.CLASSIC: "标准", GameModes.AMBITIOUS: "奸雄", GameModes.FREE_FOR_ALL: "乱斗"}[entry.mode]]
		var buttons = main._page.get_children().filter(func(b): return b is Button and b.text == text and not b.is_queued_for_deletion())
		t.check(buttons.size() == 1, "H02d actual menu exposes confirmed configuration")
		buttons[0].pressed.emit()
		main._select_general("稻草人")
		await frames(t)
		var game = t.current_scene
		game.start_game()
		game._halt_countdown()
		t.check(game.game_mode == entry.mode and game.player_count == entry.count and game.players.size() == entry.count, "H02d real menu navigation preserves mode/count")
		game._game_over = true
	t.node_added.disconnect(adopt)
	t.current_scene.queue_free()
	t.current_scene = null
	await frames(t)
	t.current_scene = previous if is_instance_valid(previous) else null

func network_setup(t):
	var session = LanSession.new()
	t.root.add_child(session)
	var result = ERR_CANT_CREATE
	for i in 20:
		result = session.host("H02", 10, 35000 + randi_range(0, 17000), GameModes.FREE_FOR_ALL)
		if result == OK: break
	t.check(result == OK, "H02d explicit 10-player FFA authority starts")
	for i in range(1, 11): session.members[i] = {"peer": i, "name": "P%d" % i, "general": "随机", "ready": true}
	t.check(session.begin_match(), "H02d 10 random slots filled without insufficient-pool crash")
	var game = session.bridge.game
	var names = game.players.map(func(p): return p.general_name)
	t.check(names.all(func(name): return names.count(name) == 1) and names.all(func(name): return GeneralData.get_implementation_status(name) == "prototype"), "H02d ten random slots retain ten unique actual playable generals")
	t.check(names.filter(func(name): return GeneralData.get_implementation_status(name) == "metadata_only").size() == 10 - LanSession.GENERALS.size(), "H02d supplements fill only missing slots, preserving all available implemented generals")
	var room = load("res://Scenes/LanRoom.tscn").instantiate()
	t.root.add_child(room)
	room._state_changed(session.bridge.snapshot(0))
	t.check(room._board.get_child_count() == 10 and room._board.get_children().all(func(b): return "技能尚未实装" not in b.tooltip_text), "H02d actual ten-general LAN board does not label implemented skills as metadata")
	# Explicit presentation fixture preserves metadata UI coverage now that ten
	# supported seats fit the full playable pool; no 11-player game is invented.
	var supplement=GeneralData.draw_unique_random_generals(LanSession.GENERALS.size()+1)
	t.check(supplement.filter(func(name): return GeneralData.get_implementation_status(name)=="metadata_only").size()==1 and supplement.all(func(name): return supplement.count(name)==1),"H02d helper still supplements a pool shortage with exactly one unique metadata general")
	var display=session.bridge.snapshot(0).duplicate(true)
	display.players[0].general="彼得·伊茨·朗·欧弗·约尔·欧耳·麦·彼茨尼兹"
	room._state_changed(display)
	t.check(room._board.get_child_count()==10 and "技能尚未实装" in room._board.get_child(0).tooltip_text,"H02d explicit metadata display fixture retains actual LAN fallback rendering")
	t.check(session.lobby.mode == GameModes.FREE_FOR_ALL and session.latest.mode == session.mode, "H02d lobby and game carry explicit same mode")
	session.close()
	for pair in [[6, GameModes.CLASSIC], [5, GameModes.AMBITIOUS], [5, "unknown"]]:
		t.check(session.host("invalid", pair[0], 24567, pair[1]) == ERR_INVALID_PARAMETER and not session.connected, "H02d unimplemented/malformed modes cannot host")
	room.queue_free()
	session.queue_free()
	await frames(t)

func replay(t):
	for entry in [[7, GameModes.CLASSIC], [9, GameModes.CLASSIC], [10, GameModes.FREE_FOR_ALL]]:
		prepare(entry[0], entry[1])
		var finals: Array = []
		for repeat in 2:
			var game = load("res://Scenes/Game.tscn").instantiate()
			game.set_script(load("res://Test/replay_game.gd"))
			game.auto_start = false
			t.root.add_child(game)
			game.ai_driver.rng.seed = 7401
			game._dodge_override = func(): return true
			game._aoe_override = func(): return true
			game._duel_respond_override = func(): return true
			game._duel_second_override = func(): return true
			game._nullify_override = func(): return false
			game._sacrifice_override = func(): return false
			game._hand_discard_override = func(snapshot, amount, _mandatory): return snapshot.defaults(amount)
			game._zone_pick_override = func(): return "hand"
			game._rescue_choice_override = func(r, d, o): return game._choose_ai_rescue(r, d, o)
			game.start_game()
			game._halt_countdown()
			for frame in 1600:
				if game._game_over: break
				await t.process_frame
			t.check(game._game_over and game.replay_violations.is_empty(), "H02c extended real default AI game reaches legal terminal")
			finals.append([game.replay_state(), game.replay_actions])
			game._game_over = true
			game.queue_free()
			await frames(t)
		t.check(finals[0] == finals[1], "H02c fixed-seed expanded full game repeats identically")

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity, MainMenu.random_mode]
	pure(t)
	for entry in GameModes.catalog().filter(func(row): return row.playable): await opening(t, entry)
	for count in [7, 9]:
		var game = fixture(t, count, GameModes.CLASSIC)
		var lord = game.players[0]
		await game._deal_damage(lord, game.players[1], 20, EffectChain.DamageType.PHYSICAL)
		t.check(lord.hand_size() == 0 and not game._game_over, "H02c expanded lord-kills-loyalist penalty uses real death")
		var rebel = game.players.filter(func(p): return p.identity == "反贼")[0]
		await game._deal_damage(lord, rebel, 20, EffectChain.DamageType.PHYSICAL)
		t.check(lord.hand_size() == 3, "H02c expanded classic rebel kill reward exactly three")
		game._game_over = true
		game.queue_free()
		await frames(t)
	for count in [5, 7, 9, 10]:
		var game = fixture(t, count, GameModes.FREE_FOR_ALL)
		var before = game.players[0].hand_size()
		await game._deal_damage(game.players[0], game.players[1], 20, EffectChain.DamageType.PHYSICAL)
		t.check(game.players[0].hand_size() == before and game.players.all(func(p): return p.identity == "" and p.identity_max_hp_bonus == 0), "H02c same-size FFA has no roles, lord bonus or kill reward")
		game._game_over = true
		game.queue_free()
		await frames(t)
	for pair in [[6, GameModes.CLASSIC], [5, GameModes.AMBITIOUS], [5, "unknown"]]:
		var game = fixture(t, pair[0], pair[1])
		t.check(game.players.is_empty(), "H02b invalid configuration cannot become blank-role half-game")
		game.queue_free()
		await frames(t)
	await menu(t)
	await network_setup(t)
	await replay(t)
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]
	MainMenu.random_mode = saved[5]
