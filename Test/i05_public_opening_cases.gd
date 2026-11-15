extends RefCounted
const Cards=preload("res://Test/i05_peter_card_cases.gd")

func run(t):
	var saved=[GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity,MainMenu.random_mode]
	t.check(GeneralData.get_implementation_status(Cards.PETER)=="prototype" and GeneralData.get_max_hp(Cards.PETER)==3 and not GeneralData.METADATA_ONLY_GENERALS.has(Cards.PETER),"I05 public Peter has one three-HP playable entry, no metadata duplicate")
	t.check(GeneralData.get_available_random_generals().size()==13 and GeneralData.get_available_random_generals().count(Cards.PETER)==1 and LanSession.GENERALS.count(Cards.PETER)==1,"I05 thirteen-general random/native/LAN pool includes Peter exactly once")
	t.check(LanSession.PROTOCOL=="campus-lan-16","I05 capability opening changes protocol, older clients do not silently join")
	MainMenu.random_mode=false
	var menu=load("res://Scenes/MainMenu.tscn").instantiate()
	menu.set_script(load("res://Test/leo_menu_observer.gd"))
	t.root.add_child(menu)
	await t.process_frame
	for count in [2,5,10]:
		var mode=GameModes.CLASSIC if count==5 else GameModes.FREE_FOR_ALL
		menu._start_test_game(count,mode)
		await t.process_frame
		var buttons=menu.get_node("Center/Box/Page").get_children().filter(func(node): return node is Button and not node.is_queued_for_deletion() and Cards.PETER in node.text)
		t.check(buttons.size()==1,"I05 actual native selection presents Peter exactly once")
		if not buttons.is_empty():
			t.check("体力 3" in buttons[0].text and "【关我屁事】" in buttons[0].text and "【关你屁事】" in buttons[0].text,"I05 native Peter displays correct base HP and both adopted skills")
			buttons[0].pressed.emit()
			t.check(menu.launches.back()==[count,mode,Cards.PETER,false,false],"I05 actual Peter button preserves count, mode and explicit choice")
	menu.queue_free()
	await t.process_frame
	await ai_and_reset(t)
	await unit_counter(t)
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]
	MainMenu.random_mode=saved[5]

func ai_and_reset(t):
	var game=Cards.new().fixture(t)
	game.lan_enabled=false
	game._peter_ignore_override=Callable()
	game._peter_exclusion_override=Callable()
	game._ai_response_override=func(_v,_k,_o): return -1
	await Cards.new().play(game,"aoe")
	t.check(game.players[1].hp==2 and game.players[2].hp==2 and game._choice_prompt_stack.is_empty(),"I05 public AI takes optional harmful-effect immunity, preserves other recipients without human window")
	await Cards.new().dispose(t,game)
	game=Cards.new().fixture(t,5,2)
	game.lan_enabled=false
	game._peter_exclusion_override=Callable()
	game._ai_response_override=func(_v,_k,_o): return -1
	await game.execute_card_on_target(game.players[1],CardData.CardSubType.DUEL)
	t.check(game.players[1].hp==2 and game._choice_prompt_stack.is_empty(),"I05 basic AI conservatively declines counter exclusions, normal Duel still resolves")
	await Cards.new().dispose(t,game)
	# Sage restores the true game-opening general, not a renamed Straw fixture.
	var bridge=LanGameBridge.new()
	t.root.add_child(bridge)
	var roster: Array[Dictionary]=[]
	for seat in 5: roster.append({"name":"P%d"%seat,"general":Cards.PETER if seat==1 else "稻草人"})
	t.check(bridge.start(roster,GameModes.FREE_FOR_ALL,AiActionPacer.Speed.FAST),"I05 Sage fixture opens actual public Peter general")
	game=bridge.game
	game._halt_countdown()
	game._duel_respond_override=func(): return false
	game._nullify_override=func(): return false
	game._sacrifice_actor_override=func(_p,_t,_a): return false
	game._rescue_choice_override=func(_p,_t,_o): return -1
	for p in game.players: p.hand.clear(); p.determined_cards.clear()
	game.players[0].hand.assign([null,null])
	var peter=game.players[1]
	peter.hp=1
	peter.equip_card_to_slot("armor",CardBase.create(CardData.CardSubType.SAGE_PROTECTION))
	peter.sage_activated=true
	game._sage_save_override=func(): return true
	var asks: Array=[]
	game._peter_exclusion_override=func(_p,_c,_k,_v): asks.append(true); return [game.players[3]]
	await game.execute_card_on_target(peter,CardData.CardSubType.DUEL)
	t.check(peter.hp==3 and peter.max_hp==3 and peter.hand_size()==4 and peter.get_armor()==-1,"I05 actual Sage restores public Peter general, equips cleared and four drawn")
	await game.execute_card_on_target(peter,CardData.CardSubType.DUEL)
	t.check(asks.size()==2 and peter.hp==2 and game._pending_card_actions.is_empty(),"I05 post-Sage next original card receives fresh counter list; previous restrictions not permanent")
	game._game_over=true
	bridge.queue_free()
	for i in 3: await t.process_frame

func unit_counter(t):
	var game=Cards.new().fixture(t,5,2)
	var dragon=load("res://Test/i04_stealth_sacrifice_cases.gd").new().make_dragon(game)
	var id=game.unit_registry.id_for(dragon)
	dragon.hand.append(null)
	var asks: Array=[]
	game._peter_exclusion_override=func(_p,candidates,_k,_v):
		asks.append(true)
		t.check(not candidates.has(dragon),"I05 hidden dragon cannot be selected for Peter's counter exclusion")
		return []
	game._nullify_override=func(): return game._input_seat==1 and dragon.hand_size()>0
	await game.execute_card_on_target(game.players[3],CardData.CardSubType.DUEL)
	t.check(asks.size()==1 and dragon.hand_size()==0 and game.players[3].hp==3,"I05 legal hidden intelligent unit still pays its own allowed counter while Peter observes")
	t.check(not game.fire_dragon_state.is_revealed_to(id,game.players[2]) and game.players.size()==5 and game._pending_card_actions.is_empty(),"I05 counter exemption does not reveal dragon or add identity/seat, original facts complete")
	await Cards.new().dispose(t,game)
