extends RefCounted

func frames(t):
	for i in 3: await t.process_frame

func click(t,bridge,seat,text) -> bool:
	var token = load("res://Test/i04_movement_cases.gd").new().find(bridge.snapshot(seat),text)
	var ok = token != "" and bridge.submit(seat,token)
	t.check(ok,"I04 paid skill real Bridge command: " + text)
	await frames(t)
	return ok

func pay(t,bridge,seat) -> bool:
	var view = bridge.snapshot(seat)
	for control in view.controls:
		if control.toggle and not control.disabled:
			t.check(not bridge.submit((seat+1)%6,control.id),"I04 fee selection rejects another seat")
			bridge.submit(seat,control.id)
			await frames(t)
			return await click(t,bridge,seat,"确认弃牌")
	t.check(false,"I04 real fee window has selectable material")
	return false

func run(t):
	for skill in ["校园霸主","装逼"]:
		for invalidated in [false,true]:
			var bridge = load("res://Test/i04_sacrifice_region_cases.gd").new().bridge_fixture(t)
			var game = bridge.game
			game.players[1].general_name = "杰基·斯特朗" if skill == "校园霸主" else "史蒂芬·彼特先斯"
			game.players[1].awoken = true
			game._zhuangbi_again_override = func(): return false
			if not await click(t,bridge,0,"结束出牌"): bridge.queue_free(); await frames(t); continue
			var inspect = bridge.snapshot(1).targets.get("1","")
			t.check(inspect != "" and bridge.submit(1,inspect),"I04 B opens own actual detail panel")
			await frames(t)
			if not await click(t,bridge,1,skill): bridge.queue_free(); await frames(t); continue
			var view = bridge.snapshot(1)
			t.check(not view.targets.has("0") and not view.targets.has("5") and view.targets.has("2"),"I04 skill targeting snapshot excludes opposite region, permits C")
			var selected = view.targets.get("2","")
			if selected == "": game._game_over=true; bridge.queue_free(); await frames(t); continue
			t.check(bridge.submit(1,selected),"I04 actual skill selects C by target token")
			await frames(t)
			if skill == "装逼":
				if not await click(t,bridge,1,"确认装逼"): game._game_over=true; bridge.queue_free(); await frames(t); continue
			if not await pay(t,bridge,1): game._game_over=true; bridge.queue_free(); await frames(t); continue
			var old = bridge.snapshot(2).controls[0].id if not bridge.snapshot(2).controls.is_empty() else ""
			if invalidated:
				# Technical topology mutation during mandatory C fee; not an authorized out-of-turn move skill.
				var ids = game.unit_registry.active_units().filter(func(body): return game._is_mountain_body(body))
				var live: Array[int] = [0,1,2,3,4,5]
				t.check(game.mountain_space.move(game.unit_registry.id_for(ids[0]),1,2,live),"I04 inject partition change after B fee, before C fee")
				await frames(t)
				t.check(game.players[1].hand_size()==1 and game.players[2].hand_size()==1 and game.players[2].hp==5,"I04 invalidated skill preserves paid B fee, does not charge C or deal damage")
			else:
				if not await pay(t,bridge,2): game._game_over=true; bridge.queue_free(); await frames(t); continue
				if not await click(t,bridge,1,"石头"): game._game_over=true; bridge.queue_free(); await frames(t); continue
				if not await click(t,bridge,2,"剪刀"): game._game_over=true; bridge.queue_free(); await frames(t); continue
				for response in 6:
					var seat = bridge.input_owner()
					var response_view = bridge.snapshot(seat)
					if load("res://Test/i04_movement_cases.gd").new().find(response_view,"打出【舍己为人】") == "": break
					await click(t,bridge,seat,"放弃")
				t.check(game.players[1].hand_size()==1 and game.players[2].hand_size()==0 and game.players[2].hp==4,"I04 actual bilateral fees and real RPS cause exactly one skill damage")
			t.check(bridge.input_owner()==1 and game.turn_manager.current_phase==TurnManager.Phase.PLAY and game._campus_execution_owner==-1 and game._zhuangbi_execution_owner==-1,"I04 completed or invalidated skill restores B PLAY and releases locks")
			t.check(old != "" and not bridge.submit(2,old),"I04 expired C fee token cannot act after settlement")
			game._game_over=true
			bridge.queue_free()
			await frames(t)
