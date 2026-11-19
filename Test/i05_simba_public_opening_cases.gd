extends RefCounted
const SIMBA="辛巴·古德曼"

func run(t):
	var saved=[GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity,MainMenu.random_mode]
	t.check(GeneralData.get_available_random_generals().size() == 15 and GeneralData.get_available_random_generals().count(SIMBA)==1 and LanSession.GENERALS.count(SIMBA)==1,"I05d public native/random/LAN pools expose fifteen unique generals and exactly one Simba")
	t.check(GeneralData.get_implementation_status(SIMBA)=="prototype" and not GeneralData.METADATA_ONLY_GENERALS.has(SIMBA) and GeneralData.get_max_hp(SIMBA)==5,"I05d public data replaces metadata with adopted five HP")
	t.check(GeneralData.get_skills(SIMBA).size()==5 and GeneralData.get_handbook_section(SIMBA)=="6.13" and LanSession.PROTOCOL=="campus-lan-18","I05d public data retains all five skills and incompatible rule protocol")
	MainMenu.random_mode=false
	var menu=load("res://Scenes/MainMenu.tscn").instantiate(); menu.set_script(load("res://Test/leo_menu_observer.gd")); t.root.add_child(menu)
	await t.process_frame
	for count in [2,5,10]:
		var mode=GameModes.CLASSIC if count==5 else GameModes.FREE_FOR_ALL
		menu._start_test_game(count,mode)
		for frame in 3: await t.process_frame
		var buttons=menu.get_node("Center/Box/Page").get_children().filter(func(node): return node is Button and not node.is_queued_for_deletion() and SIMBA in node.text)
		t.check(buttons.size()==1,"I05d native menu offers exactly one public Simba at each supported selection size")
		if buttons.size()==1:
			var scroll=menu.get_node("Center")
			t.check(scroll is ScrollContainer and scroll.get_v_scroll_bar().max_value>scroll.size.y,"I05d long native general list has a real vertical scroll range")
			scroll.scroll_vertical=1000000
			for frame in 3: await t.process_frame
			t.check(buttons[0].get_global_rect().intersects(scroll.get_global_rect()),"I05d public Simba can scroll into the actual native clickable viewport")
			t.check("体力 5" in buttons[0].text and ["【班长】","【万磁】","【团费】","【做好事】","【急救】"].all(func(skill): return skill in buttons[0].text),"I05d native menu shows complete adopted five-skill description")
			buttons[0].pressed.emit()
			t.check(menu.launches.back()==[count,mode,SIMBA,false,false],"I05d public native selection retains count/mode and manual settings")
	menu.queue_free(); await t.process_frame
	for spec in [[2,GameModes.FREE_FOR_ALL],[5,GameModes.CLASSIC],[10,GameModes.AMBITIOUS]]:
		GameManager.selected_players=spec[0]; GameManager.selected_mode=spec[1]; GameManager.selected_general=SIMBA
		GameManager.random_general=false; GameManager.random_identity=false
		var game=load("res://Scenes/Game.tscn").instantiate(); game.auto_start=false; t.root.add_child(game)
		game.start_game(); game._halt_countdown()
		var hero=game.players[0]
		var lord=spec[1]!=GameModes.FREE_FOR_ALL
		t.check(hero.general_name==SIMBA and hero.hp==(6 if lord else 5) and hero.hand_limit()==(8 if lord else 5),"I05d native initial roster applies base HP, existing identity bonus and actual lord skill")
		t.check(hero.simba_lord_skill_enabled and hero.simba_wanci_enabled and hero.simba_tuanfei_enabled and hero.simba_good_deeds_enabled and hero.simba_emergency_enabled,"I05d normal authoritative init enables all five public capabilities together")
		t.check(game.players.slice(1).all(func(p): return not p.simba_lord_skill_enabled and not p.simba_wanci_enabled and not p.simba_tuanfei_enabled and not p.simba_good_deeds_enabled and not p.simba_emergency_enabled),"I05d opening never grants Simba capabilities to other generals")
		for viewer in [hero,game.players[1]]:
			var popup=PlayerDetailPopup.create(t.root,hero,0,viewer)
			await t.process_frame
			var buttons=popup._skills_container.get_children().filter(func(c): return c is Button and "【做好事】" in c.text)
			t.check(buttons.size()==(1 if viewer==hero else 0),"I05d public detail has one authorized active action, other viewers read descriptions")
			popup.queue_free(); await t.process_frame
		game._game_over=true; game.queue_free()
		for i in 3: await t.process_frame
	GameManager.selected_players=saved[0]; GameManager.selected_mode=saved[1]; GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]; GameManager.random_identity=saved[4]; MainMenu.random_mode=saved[5]
