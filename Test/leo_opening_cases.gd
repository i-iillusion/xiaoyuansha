extends RefCounted

func run(suite):
	var previous = [GameManager.selected_players, GameManager.selected_mode,
		GameManager.selected_general, GameManager.random_general, GameManager.random_identity, MainMenu.random_mode]
	var name = "里奥·普利威尔"
	suite.check(GeneralData.get_implementation_status(name) == "prototype" and GeneralData.GENERALS.has(name)
		and not GeneralData.METADATA_ONLY_GENERALS.has(name) and GeneralData.get_max_hp(name) == 5
		and GeneralData.get_handbook_section(name) == "6.7", "F03c Leo enters prototype roster once, keeps base HP and handbook section")
	var skills = GeneralData.get_skills(name)
	suite.check(skills.size() == 3 and skills[0].begins_with("【丑态】") and skills[1].begins_with("【预习】")
		and skills[2].begins_with("【预大习】") and "结算完成" in skills[1] and "判定区" in skills[2], "F03c three displayed skills describe completion timing and preserved zones")
	var draw = GeneralData.draw_unique_random_generals(8)
	suite.check(draw.size() == 8 and draw.count(name) == 1 and draw.all(func(n): return GeneralData.get_implementation_status(n) == "prototype")
		and not draw.has("稻草人"), "F03c eight-name random pool contains one Leo and no metadata supplement/placeholder")
	MainMenu.random_mode = false
	var menu = load("res://Scenes/MainMenu.tscn").instantiate()
	menu.set_script(load("res://Test/leo_menu_observer.gd"))
	suite.root.add_child(menu)
	await suite.process_frame
	for count in [2, 3, 5]:
		var mode = GameManager.MODE_CLASSIC_IDENTITY if count == 5 else GameManager.MODE_FREE_FOR_ALL
		menu._start_test_game(count, mode)
		await suite.process_frame
		var buttons = menu.get_node("Center/Box/Page").get_children().filter(func(n): return n is Button and not n.is_queued_for_deletion())
		var leo_buttons = buttons.filter(func(b): return name in b.text)
		suite.check(leo_buttons.size() == 1 and "体力 5" in leo_buttons[0].text and "【丑态】" in leo_buttons[0].text
			and "【预习】" in leo_buttons[0].text and "【预大习】" in leo_buttons[0].text, "F03c actual %d-player menu has exactly one Leo button with all skills" % count)
		suite.check(buttons.size() == GeneralData.GENERALS.size() + 1 and not buttons.any(func(b): return "彼得·伊茨" in b.text or "安迪·沃费尔" in b.text), "F03c selectable menu count remains exact; metadata and deferred generals not opened")
		if leo_buttons.is_empty(): continue # Failure recorded above; never call a missing button.
		var scroller: ScrollContainer = menu.get_node("Center")
		scroller.ensure_control_visible(leo_buttons[0])
		await suite.process_frame
		await suite.process_frame
		suite.check(scroller.clip_contents and scroller.get_global_rect().intersects(leo_buttons[0].get_global_rect())
			and leo_buttons[0].autowrap_mode == TextServer.AUTOWRAP_WORD_SMART, "F03c actual Leo entry can scroll into visible viewport, long skill text wraps")
		leo_buttons[0].pressed.emit()
		suite.check(menu.launches.back() == [count, mode, name, false, false], "F03c real button preserves actual player count/mode and selects only self Leo")
		var game: GameManager = load("res://Scenes/Game.tscn").instantiate()
		game.auto_start = false
		suite.root.add_child(game)
		await suite.process_frame
		game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
		game.start_game()
		game._stop_countdown()
		suite.check(game.players.size() == count and game.players[0].general_name == name and game.players[0].hp == (6 if count == 5 else 5)
			and game.players.slice(1).all(func(p): return p.general_name == "稻草人"), "F03c actual menu selection initializes correct mode/Leo/lord bonus, duplicate straw placeholders remain legal")
		game._open_player_detail(game.players[0])
		var labels = game._detail_popup_root.find_children("*", "Label", true, false)
		suite.check(["【丑态】", "【预习】", "【预大习】"].all(func(key): return labels.any(func(l): return key in l.text))
			and not labels.any(func(l): return "技能尚未实装" in l.text), "F03c real detail panel presents three implemented skills, not metadata warning")
		if count == 5:
			# Legal AI seat for a single Leo, with identical base HP at that seat.
			game.players[0].general_name = "稻草人"
			game.players[1].general_name = name
			game.players[1].prep_tokens = 1
			game._zone_pick_override = func(): return "hand"
			game._nullify_override = func(): return false
			game.turn_manager.current_phase = TurnManager.Phase.PLAY
			await game.execute_card_on_target(game.players[4], CardData.CardSubType.SNATCH)
			suite.check(game.players[1].prep_tokens == 1 and game.turn_manager.steal_count_this_turn == 1
				and game.players[4].hand_size() == 3 and game.players[0].hand_size() == 4
				and game._choice_prompt_stack.is_empty() and game._pending_card_actions.is_empty(), "F03c non-self Leo default AI legally declines replacing, preserves mark, original paid effect completes")
		game.queue_free()
		await suite.process_frame
	menu.queue_free()
	await suite.process_frame
	GameManager.selected_players = previous[0]
	GameManager.selected_mode = previous[1]
	GameManager.selected_general = previous[2]
	GameManager.random_general = previous[3]
	GameManager.random_identity = previous[4]
	MainMenu.random_mode = previous[5]
