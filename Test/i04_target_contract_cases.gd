extends RefCounted

func run(t):
	var saved=[GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for mode in ["strike","move","duel","ai"]:
		var helper=load("res://Test/i04_paid_skill_lan_cases.gd").new()
		var bridge=load("res://Test/i04_sacrifice_region_cases.gd").new().bridge_fixture(t)
		var game=bridge.game
		await helper.click(t,bridge,0,"结束出牌")
		var mountain=game.unit_registry.active_units().filter(func(body): return game._is_mountain_body(body))[0]
		var id=game.unit_registry.id_for(mountain)
		t.check(TargetIdentity.key_for(game.players,game.unit_registry,mountain)==id and TargetIdentity.resolve_live(game.players,game.unit_registry,id)==mountain,"I04 mountain is a resolvable target without fixed-seat alias")
		t.check(ActorIdentity.key_for(game.players,game.unit_registry,mountain)==null and ActorIdentity.resolve_live(game.players,game.unit_registry,id)==null and game.unit_registry.controller(id)==null,"I04 target admission never gives mountain actor or input owner")
		if mode=="ai":
			var actions=game._ai_play_candidates(game._ai_observation(game.players[1]))
			var offered=actions.filter(func(action): return typeof(action.target)==TYPE_STRING and action.target==id and action.sub==CardData.CardSubType.STRIKE)
			t.check(not offered.is_empty(),"I04 AI offers mountain with target identity, not null actor identity")
			if not offered.is_empty(): await game._execute_ai_action(offered[0])
			t.check(mountain.hp==4 and game.players[1].hand_size()==1,"I04 AI selected mountain executes through normal strike payment/damage")
		else:
			for text in ["出牌","锦囊牌","普通锦囊","决斗"] if mode=="duel" else ["出牌","基本牌","杀","杀"]:
				await helper.click(t,bridge,1,text)
			await t.create_timer(0.15).timeout
			var view=bridge.snapshot(1)
			if mode=="duel":
				t.check(not view.targets.has(id),"I04 direct trick remains unable to target mountains")
				await helper.click(t,bridge,1,"取消选择")
			else:
				var token=view.targets.get(id,"")
				t.check(token!="","I04 real strike selection exposes legal mountain token")
				if mode=="move":
					var live: Array[int]=[0,1,2,3,4,5]
					game.mountain_space.move(id,2,3,live)
					t.check(not bridge.submit(1,token) and game.players[1].hand_size()==2 and mountain.hp==5,"I04 spatial mutation expires old mountain token before payment")
					await helper.click(t,bridge,1,"取消选择")
				else:
					t.check(not bridge.submit(2,token) and bridge.submit(1,token),"I04 mountain token belongs to actual attacking controller")
					await helper.frames(t)
					await helper.click(t,bridge,1,"是")
					t.check(mountain.hp==4 and game.players[1].hand_size()==1 and bridge.input_owner()==1,"I04 real Bridge mountain strike pays once and returns B PLAY")
		game._game_over=true
		game.unit_registry.reset()
		t.check(TargetIdentity.resolve_live(game.players,game.unit_registry,id)==null,"I04 registry reset rejects retained old mountain target id")
		bridge.queue_free()
		await helper.frames(t)
	await native(t)
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]

func native(t):
	var game=load("res://Test/h02_integration_cases.gd").new().fixture(t,6,GameModes.FREE_FOR_ALL)
	load("res://Test/i04_burning_interception_cases.gd").new().prepare(game)
	game.players[0].hand.assign([null,null])
	var mountain=game._spawn_mountain_at(game.players[5],0,1)
	# The registration return is the unit body; card selection is an explicit native UI boundary.
	game._enter_targeting_mode(CardData.CardSubType.STRIKE)
	for i in 3: await t.process_frame
	game._native_unit_board.refresh(game)
	var buttons=game._native_unit_board._list.get_children().filter(func(child): return child is Button and child.has_meta("unit"))
	t.check(not buttons.is_empty(),"I04 native board presents legal mountain as target button during strike selection")
	if not buttons.is_empty():
		var reused=buttons[0]
		mountain.hp=4
		game._native_unit_board.refresh(game)
		t.check(is_instance_valid(reused) and not reused.is_queued_for_deletion() and "4/5" in reused.text and reused.pressed.get_connections().size()==1,"I04 live HP refresh keeps one current target callback, no duplicated attack")
		mountain.hp=5
		game._native_unit_board.refresh(game)
		t.check("5/5" in reused.text and reused.pressed.get_connections().size()==1,"I04 repeated board refresh updates immediately without accumulating callbacks")
		buttons[0].pressed.emit()
		for i in 3: await t.process_frame
		if not game._choice_prompt_stack.is_empty():
			var yes=game._choice_prompt_stack.back().overlay.find_children("*","Button",true,false).filter(func(button): return button.text=="是")
			if not yes.is_empty(): yes[0].pressed.emit()
		for i in 3: await t.process_frame
		var body=game.unit_registry.active_units().filter(func(unit): return game._is_mountain_body(unit))[0]
		t.check(body.hp==4 and game.players[0].hand_size()==1,"I04 native mountain button dispatches real confirmation and strike settlement")
	await load("res://Test/i04_burning_interception_cases.gd").new().dispose(t,game)
