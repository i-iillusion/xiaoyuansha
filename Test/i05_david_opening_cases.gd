extends RefCounted
const DAVID = "大卫·法米尔"

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity, MainMenu.random_mode]
	t.check(GeneralData.get_implementation_status(DAVID) == "prototype" and GeneralData.get_max_hp(DAVID) == 4 and not GeneralData.METADATA_ONLY_GENERALS.has(DAVID), "I05b6 public David has one four-HP playable catalog entry")
	t.check(GeneralData.get_available_random_generals().size() == 12 and GeneralData.get_available_random_generals().count(DAVID) == 1 and LanSession.GENERALS.count(DAVID) == 1 and LanSession.PROTOCOL == "campus-lan-15", "I05b6 native/random/LAN agree on twelve unique generals and updated protocol")
	t.check(GeneralData.get_skills(DAVID).size() == 2 and GeneralData.get_skills(DAVID)[0].begins_with("【种田】") and GeneralData.get_skills(DAVID)[1].begins_with("【我要跟你摔角】"), "I05b6 public skill data contains both adopted skills exactly once")
	MainMenu.random_mode = false
	var menu = load("res://Scenes/MainMenu.tscn").instantiate()
	menu.set_script(load("res://Test/leo_menu_observer.gd"))
	t.root.add_child(menu); await t.process_frame
	for count in [2, 5, 10]:
		var mode = GameModes.CLASSIC if count == 5 else GameModes.FREE_FOR_ALL
		menu._start_test_game(count, mode); await t.process_frame
		var buttons = menu.get_node("Center/Box/Page").get_children().filter(func(n): return n is Button and not n.is_queued_for_deletion() and DAVID in n.text)
		t.check(buttons.size() == 1 and "体力 4" in buttons[0].text and "【种田】" in buttons[0].text and "【我要跟你摔角】" in buttons[0].text, "I05b6 real native selection displays David, HP and both skills")
		if buttons.is_empty(): continue # Keep the recorded failure rather than masking it with an index error.
		buttons[0].pressed.emit()
		t.check(menu.launches.back() == [count, mode, DAVID, false, false], "I05b6 real David button preserves chosen mode/count and explicit general")
	menu.queue_free(); await t.process_frame
	var bridge = LanGameBridge.new(); t.root.add_child(bridge)
	var roster: Array[Dictionary] = [{"name": "David", "general": DAVID}, {"name": "Other", "general": "稻草人"}]
	t.check(bridge.start(roster, GameModes.FREE_FOR_ALL, AiActionPacer.Speed.FAST), "I05b6 normal public Bridge starts David without metadata fixture or capability override")
	var game = bridge.game; game._halt_countdown()
	t.check(game._david_rules_enabled and game._wrestling_rules_enabled and game.players[0].max_hp == 4 and game.players[0].hand_size() == 6 and game.players[0].farm_empty_fields == 0 and game.players[0].farm_good_fields == 0, "I05b6 normal initial draw/HP and both server capabilities active with zero invented fields")
	t.check(bridge.snapshot(0).players[0].empty_fields == 0 and bridge.snapshot(1).players[0].good_fields == 0, "I05b6 field markers are consistent value-only public observations")
	var panels = game.find_children("*", "Control", true, false).filter(func(n): return n.has_meta("player") and n.get_meta("player") == game.players[0] and n.has_meta("prep_indicator"))
	t.check(panels.size() == 1 and panels[0].get_meta("prep_indicator").visible and "空田:0 好田:0" == panels[0].get_meta("prep_indicator").text, "I05b6 native seat renders actual empty/good field counts")
	var room = load("res://Scenes/LanRoom.tscn").instantiate(); t.root.add_child(room)
	room._state_changed(bridge.snapshot(0))
	t.check("空田：0  好田：0" in room._board.get_child(0).text, "I05b6 actual LAN board renders serialized field counts")
	room.session.close(); room.queue_free(); await t.process_frame
	var own = bridge.snapshot(0).targets.get("0", "")
	t.check(own != "" and bridge.submit(0, own), "I05b6 own public portrait opens actual skill detail")
	await t.process_frame
	var view = bridge.snapshot(0)
	t.check(view.controls.filter(func(c): return "【种田】" in c.text).size() == 1 and view.labels.filter(func(label): return "【我要跟你摔角】" in label).size() == 1 and bridge.snapshot(1).controls.is_empty(), "I05b6 upgrade button and counter description are not duplicated or shared with wrong seat")
	game._game_over = true; bridge.queue_free()
	for i in 4: await t.process_frame
	GameManager.selected_players = saved[0]; GameManager.selected_mode = saved[1]; GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]; GameManager.random_identity = saved[4]; MainMenu.random_mode = saved[5]
