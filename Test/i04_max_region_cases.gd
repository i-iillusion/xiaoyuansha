extends RefCounted

func run(t):
	var saved = [GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for mode in ["gift","swap"]:
		for walls in [0,1,2]:
			for across in [false,true]:
				var game = load("res://Test/h02_integration_cases.gd").new().fixture(t,6,GameModes.FREE_FOR_ALL)
				load("res://Test/i04_sacrifice_region_cases.gd").new().configure(game,walls)
				var actor = game.players[1]
				var target = game.players[0 if across else 2]
				actor.general_name = "麦克斯·欧尼斯特"
				actor.hand.assign([null,null])
				game.turn_manager.play_actor_idx=1
				game._set_input_player(actor)
				var blocked = walls==2 and across
				if mode=="gift":
					game.turn_manager.current_phase=TurnManager.Phase.START
					game._meiyong_override=func(): return true
					game._meiyong_option_override=func(): return 1
					game._meiyong_target_override=func(): return target
					var before=target.hand_size()
					await game._maybe_meiyong(actor)
					t.check(actor.hand_size()==(2 if blocked else 3) and target.hand_size()==before+(0 if blocked else 2),"I04 gift rejects opposite region before bonus or DRAW; same region/single wall draws normally")
					t.check(game.turn_manager.current_phase==TurnManager.Phase.START and game._meiyong_execution_owner==-1,"I04 gift returns source START and releases ownership")
				else:
					game.turn_manager.current_phase=TurnManager.Phase.PLAY
					var weapon=CardBase.create(CardData.CardSubType.LIANNU)
					target.equip_card_to_slot("weapon",weapon)
					var zones: Array=["weapon","done"]
					game._lanzhonghou_zone_override=func(): return zones.pop_front()
					game._hand_discard_override=func(snapshot,count,_mandatory): return snapshot.defaults(count)
					await game._run_lanzhonghou(actor,target)
					t.check(actor.hand_size()==(2 if blocked else 1) and (target.get_equipment_card("weapon")==weapon if blocked else actor.get_equipment_card("weapon")==weapon),"I04 swap blocks cross-region movement before fee, permits legal empty-slot exchange")
					t.check(game._lanzhonghou_execution_owner==-1 and game._lanzhonghou_used==not blocked,"I04 swap only consumes phase use on successful exchange")
				var bridge=LanGameBridge.new()
				bridge.game=game
				game._is_meiyong_targeting=mode=="gift"
				game._is_lanzhonghou_targeting=mode=="swap"
				t.check(bridge._declaration_target_allowed(target)==not blocked,"I04 Bridge follows gift/swap region eligibility")
				bridge.free()
				await load("res://Test/i04_burning_interception_cases.gd").new().dispose(t,game)
	await granted_play_survives_partition(t)
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]

func granted_play_survives_partition(t):
	var game=load("res://Test/h02_integration_cases.gd").new().fixture(t,6,GameModes.FREE_FOR_ALL)
	load("res://Test/i04_sacrifice_region_cases.gd").new().configure(game,2)
	var source=game.players[1]
	var target=game.players[2]
	source.general_name="麦克斯·欧尼斯特"
	target.general_name="吉姆·芒顿"
	game.turn_manager.current_phase=TurnManager.Phase.START
	game.turn_manager.play_actor_idx=1
	game._set_input_player(source)
	game._meiyong_override=func(): return true
	game._meiyong_option_override=func(): return 2
	game._meiyong_target_override=func(): return target
	var play = func():
		t.check(game._play_actor()==target and game.turn_manager.current_phase==TurnManager.Phase.PLAY,"I04 Q55 legal granted PLAY actually begins")
		var mountains=game.unit_registry.active_units().filter(func(body): return game._is_mountain_body(body))
		var live: Array[int]=[0,1,2,3,4,5]
		t.check(game.mountain_space.move(game.unit_registry.id_for(mountains[1]),1,2,live),"I04 Q55 inject completed move effect; does not claim yishan menu or fee")
		await t.process_frame
		t.check(not game._mountain_effect_reaches(source,target) and game._play_actor()==target and game.turn_manager.current_phase==TurnManager.Phase.PLAY,"I04 Q55 new partition does not revoke already granted PLAY")
		game.end_play_phase()
	play.call_deferred()
	await game._maybe_meiyong(source)
	t.check(game.turn_manager.current_phase==TurnManager.Phase.START and game.turn_manager.current_player_idx==1 and game._meiyong_execution_owner==-1,"I04 Q55 recipient ends granted PLAY and restores source START")
	await load("res://Test/i04_burning_interception_cases.gd").new().dispose(t,game)
