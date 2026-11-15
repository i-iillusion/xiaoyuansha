extends RefCounted
const SUNNY="桑尼·斯派"
func run(t):
	var saved=[GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity,MainMenu.random_mode]
	t.check(GeneralData.get_available_random_generals().size()==13 and GeneralData.get_available_random_generals().count(SUNNY)==1 and LanSession.GENERALS.count(SUNNY)==1,"Sunny is exactly one of thirteen public generals")
	t.check(GeneralData.get_implementation_status(SUNNY)=="prototype" and not GeneralData.METADATA_ONLY_GENERALS.has(SUNNY) and GeneralData.get_max_hp(SUNNY)==4,"Sunny public data replaces metadata with four HP")
	t.check(GeneralData.get_skills(SUNNY).size()==3 and GeneralData.get_handbook_section(SUNNY)=="6.12","public descriptions retain three adopted skills and source section")
	t.check(LanSession.PROTOCOL=="campus-lan-16","new public capability has an incompatible protocol version")
	var manager=load("res://Scenes/Game.tscn").instantiate(); manager.auto_start=false; t.root.add_child(manager)
	await t.process_frame
	t.check(manager._paipian_rules_enabled and manager._spy_rules_enabled and manager._corruption_rules_enabled,"default server exposes all Sunny abilities together")
	manager.queue_free()
	for i in 3: await t.process_frame
	MainMenu.random_mode=false
	var menu=load("res://Scenes/MainMenu.tscn").instantiate(); menu.set_script(load("res://Test/leo_menu_observer.gd")); t.root.add_child(menu)
	await t.process_frame
	for count in [2,5,10]:
		var mode=GameModes.CLASSIC if count==5 else GameModes.FREE_FOR_ALL
		menu._start_test_game(count,mode); await t.process_frame
		var buttons=menu.get_node("Center/Box/Page").get_children().filter(func(node): return node is Button and not node.is_queued_for_deletion() and SUNNY in node.text)
		t.check(buttons.size()==1,"actual native selection offers Sunny once")
		if not buttons.is_empty():
			t.check("体力 4" in buttons[0].text and "【拍片】" in buttons[0].text and "【间谍】" in buttons[0].text and "【贪污】" in buttons[0].text,"native menu presents all adopted Sunny descriptions")
			buttons[0].pressed.emit()
			t.check(menu.launches.back()==[count,mode,SUNNY,false,false],"native Sunny selection preserves chosen mode and count")
	menu.queue_free(); await t.process_frame
	var player=Player.new(); player.general_name=SUNNY; player.player_name="Sunny"; player.max_hp=4; player.hp=4
	for used in [false,true]:
		player.spy_used=used
		var popup=PlayerDetailPopup.create(t.root,player,0,player,false,false,true,true)
		await t.process_frame
		var buttons=popup._skills_container.get_children().filter(func(c): return c is Button)
		t.check(buttons.filter(func(c): return "【拍片】" in c.text).size()==1 and buttons.filter(func(c): return "【间谍】" in c.text).size()==1,"public detail exposes exactly one action per active skill")
		var spies=buttons.filter(func(c): return "【间谍】" in c.text)
		t.check(spies.size()==1 and spies[0].disabled==used,"Spy button tracks actual limited-use state")
		popup.queue_free(); await t.process_frame
	player.free()
	GameManager.selected_players=saved[0]; GameManager.selected_mode=saved[1]; GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]; GameManager.random_identity=saved[4]; MainMenu.random_mode=saved[5]
