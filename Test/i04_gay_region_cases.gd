extends RefCounted

func run(t):
	var saved=[GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for walls in [0,1,2]:
		for across in [false,true]:
			for concrete in [false,true]:
				var game=load("res://Test/h02_integration_cases.gd").new().fixture(t,6,GameModes.FREE_FOR_ALL)
				load("res://Test/i04_sacrifice_region_cases.gd").new().configure(game,walls)
				var actor=game.players[1]
				var target=game.players[0 if across else 2]
				actor.general_name="比尔·盖伊"
				actor.hp=2
				target.hp=2
				actor.hand.assign([null,null])
				actor.determined_cards.clear()
				var fee=CardBase.create(CardData.CardSubType.DODGE)
				if concrete:
					actor.hand.clear()
					actor.determined_cards.append(fee)
				game.turn_manager.current_phase=TurnManager.Phase.PLAY
				game.turn_manager.play_actor_idx=1
				game._set_input_player(actor)
				game._gay_x_override=func(): return 1
				game._hand_discard_override=func(snapshot,count,_mandatory): return snapshot.defaults(count)
				var before=actor.hand_size()
				var blocked=walls==2 and across
				var bridge=LanGameBridge.new()
				bridge.game=game
				game._is_gay_targeting=true
				t.check(bridge._declaration_target_allowed(target)==not blocked and not bridge._declaration_target_allowed(actor),"I04 Gay Bridge respects same-region injured other target")
				game._is_gay_targeting=false
				await game._execute_gay(actor,target)
				t.check(actor.hand_size()==before-(0 if blocked else 1) and actor.hp==(2 if blocked else 3) and target.hp==actor.hp,"I04 Gay cross-wall cannot pay/heal; same region/single wall heals both normally")
				t.check(game._gay_used==not blocked and game._gay_execution_owner==-1,"I04 Gay only successful use consumes limit and releases ownership")
				if concrete: t.check(game.deck._discard.count(fee)==(0 if blocked else 1),"I04 Gay uses same concrete original exactly once, never converts it to arbitrary")
				bridge.free()
				await load("res://Test/i04_burning_interception_cases.gd").new().dispose(t,game)
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]
