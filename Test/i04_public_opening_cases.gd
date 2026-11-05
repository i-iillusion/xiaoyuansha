extends RefCounted

func run(t):
	var saved=[GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity,MainMenu.random_mode]
	var name="吉姆·芒顿"
	t.check(GeneralData.get_implementation_status(name)=="prototype" and GeneralData.get_max_hp(name)==6 and not GeneralData.METADATA_ONLY_GENERALS.has(name),"I04 public Jim has one playable six-HP entry, no metadata duplicate")
	t.check(GeneralData.get_available_random_generals().size()==10 and GeneralData.get_available_random_generals().count(name)==1 and LanSession.GENERALS.count(name)==1,"I04 native random pool and LAN choice list include Jim exactly once")
	MainMenu.random_mode=false
	var menu=load("res://Scenes/MainMenu.tscn").instantiate()
	menu.set_script(load("res://Test/leo_menu_observer.gd"))
	t.root.add_child(menu)
	await t.process_frame
	for count in [2,5,10]:
		var mode=GameModes.CLASSIC if count==5 else GameModes.FREE_FOR_ALL
		menu._start_test_game(count,mode)
		await t.process_frame
		var buttons=menu.get_node("Center/Box/Page").get_children().filter(func(node): return node is Button and not node.is_queued_for_deletion() and name in node.text)
		t.check(buttons.size()==1,"I04 real native %d-player selection presents one Jim button"%count)
		if buttons.is_empty(): continue
		var button=buttons[0]
		t.check("体力 6" in button.text and ["王屋太行","造山","护山","移山","聚山"].all(func(skill): return "【"+skill+"】" in button.text),"I04 native Jim displays six HP and all five adopted skills")
		button.pressed.emit()
		t.check(menu.launches.back()==[count,mode,name,false,false],"I04 actual native Jim button preserves player count and chosen game mode")
	menu.queue_free()
	var owner=Player.new()
	owner.general_name=name
	owner.max_hp=6
	owner.hp=6
	t.root.add_child(owner)
	var popup=PlayerDetailPopup.create(t.root,owner,0,owner,true)
	await t.process_frame
	var pressed: Array=[]
	popup.skill_clicked.connect(func(key): pressed.append(key))
	for skill in ["护山","移山","聚山"]:
		var buttons=popup._skills_container.get_children().filter(func(node): return node is Button and "【"+skill+"】" in node.text)
		t.check(buttons.size()==1,"I04 published detail has exactly one active button: "+skill)
		if not buttons.is_empty(): buttons[0].pressed.emit()
	t.check(pressed==["护山","移山","聚山"],"I04 published buttons dispatch actual skill keys once, not duplicate fallback actions")
	popup.queue_free()
	owner.queue_free()
	await t.process_frame
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]
	MainMenu.random_mode=saved[5]
