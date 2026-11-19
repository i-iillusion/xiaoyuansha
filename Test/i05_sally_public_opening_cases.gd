extends RefCounted

const SALLY = "萨利·赛克斯"

func run(t):
	var saved = [GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity,MainMenu.random_mode]
	MainMenu.random_mode = false
	var menu = load("res://Scenes/MainMenu.tscn").instantiate()
	menu.set_script(load("res://Test/leo_menu_observer.gd"))
	t.root.add_child(menu)
	await t.process_frame
	for spec in [[2,GameModes.FREE_FOR_ALL],[5,GameModes.CLASSIC],[10,GameModes.AMBITIOUS]]:
		menu._start_test_game(spec[0],spec[1])
		for frame in 3: await t.process_frame
		var buttons = menu.get_node("Center/Box/Page").get_children().filter(func(node): return node is Button and not node.is_queued_for_deletion() and SALLY in node.text)
		t.check(buttons.size()==1 and GeneralData.get_skills(SALLY).size()==5,"I05e7 main menu lists Sally and five implemented skills")
		if buttons.size() == 1:
			buttons[0].pressed.emit()
			t.check(menu.launches.back()==[spec[0],spec[1],SALLY,false,false],"I05e7 native menu selects Sally in each mode")
	menu.queue_free()
	await t.process_frame
	for spec in [[2,GameModes.FREE_FOR_ALL],[5,GameModes.CLASSIC],[6,GameModes.AMBITIOUS]]:
		GameManager.selected_players=spec[0]; GameManager.selected_mode=spec[1]
		GameManager.selected_general=SALLY; GameManager.random_general=false; GameManager.random_identity=false
		var game = load("res://Scenes/Game.tscn").instantiate()
		game.auto_start=false
		t.root.add_child(game)
		game.start_game()
		game._halt_countdown()
		var hero = game.players[0]
		t.check(hero.general_name==SALLY and hero.gender=="female" and hero.hp==(3 if spec[1]==GameModes.FREE_FOR_ALL else 4),"I05e7 real native initialization uses base HP, lord bonus and female gender")
		t.check(hero.has_jiegui() and hero.has_sally_woman() and hero.has_sally_lieqi() and SallySmokingState.enabled(hero) and hero.sally_surgery_enabled,"I05e7 real native initialization enables five capabilities")
		t.check(game.players.slice(1).all(func(p): return not p.sally_smoking_enabled and not p.sally_surgery_enabled and not p.sally_woman_enabled and not p.sally_jiegui_enabled and not p.sally_lieqi_enabled),"I05e7 other generals never inherit Sally capabilities")
		game._game_over=true
		game.queue_free()
		for frame in 3: await t.process_frame
	GameManager.selected_players=saved[0]; GameManager.selected_mode=saved[1]; GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]; GameManager.random_identity=saved[4]; MainMenu.random_mode=saved[5]
