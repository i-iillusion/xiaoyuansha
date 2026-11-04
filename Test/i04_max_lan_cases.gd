extends RefCounted

func run(t):
	var helper=load("res://Test/i04_paid_skill_lan_cases.gd").new()
	for mode in ["gift","gift_invalid","swap","swap_invalid"]:
		var bridge=load("res://Test/i04_sacrifice_region_cases.gd").new().bridge_fixture(t)
		var game=bridge.game
		game.players[1].general_name="麦克斯·欧尼斯特"
		var target=game.players[2]
		var weapon=CardBase.create(CardData.CardSubType.LIANNU)
		if mode.begins_with("swap"): target.equip_card_to_slot("weapon",weapon)
		await helper.click(t,bridge,0,"结束出牌")
		if mode.begins_with("gift"):
			await helper.click(t,bridge,1,"确认")
			var view=bridge.snapshot(1)
			t.check(not view.targets.has("0") and not view.targets.has("5") and view.targets.has("2"),"I04 real combined gift view excludes cross-region targets")
			var token=view.targets.get("2","")
			t.check(token!="" and bridge.submit(1,token),"I04 real combined gift selects C")
			await helper.frames(t)
			var old=load("res://Test/i04_movement_cases.gd").new().find(bridge.snapshot(1),"摸牌")
			if mode.ends_with("invalid"):
				move_wall(t,game)
				await helper.frames(t)
				t.check(not bridge.submit(1,old) and target.hand_size()==1 and game.players[1].hand_size()==0,"I04 technical invalidation grants no stage/bonus and cannot advance stale source START")
			else:
				await helper.click(t,bridge,1,"摸牌")
				t.check(target.hand_size()==3 and game.players[1].hand_size()==1,"I04 actual gift DRAW gives C two, source one bonus and skips own DRAW")
		else:
			await helper.click(t,bridge,1,"取消")
			var inspect=bridge.snapshot(1).targets.get("1","")
			t.check(inspect!="" and bridge.submit(1,inspect),"I04 Max opens actual own detail")
			await helper.frames(t)
			await helper.click(t,bridge,1,"没用")
			var view=bridge.snapshot(1)
			t.check(not view.targets.has("0") and view.targets.has("1") and view.targets.has("2"),"I04 actual swap target snapshot permits self and same-region C only")
			bridge.submit(1,view.targets.get("1",""))
			await helper.frames(t)
			bridge.submit(1,bridge.snapshot(1).targets.get("2",""))
			await helper.frames(t)
			await helper.click(t,bridge,1,"武器")
			await helper.click(t,bridge,1,"完成交换")
			var old=bridge.snapshot(1).controls[0].id if not bridge.snapshot(1).controls.is_empty() else ""
			if mode.ends_with("invalid"):
				move_wall(t,game)
				await helper.frames(t)
				t.check(not bridge.submit(1,old) and game.players[1].hand_size()==2 and target.get_equipment_card("weapon")==weapon and not game._lanzhonghou_used,"I04 invalidated swap fee cannot move original weapon or consume cards/use")
			else:
				await helper.pay(t,bridge,1)
				t.check(game.players[1].hand_size()==1 and game.players[1].get_equipment_card("weapon")==weapon and target.get_equipment_card("weapon")==null and game._lanzhonghou_used,"I04 actual swap pays one real hand slot and moves original weapon into empty slot")
		t.check(bridge.input_owner()==1 and game.turn_manager.current_phase==(TurnManager.Phase.START if mode=="gift_invalid" else TurnManager.Phase.PLAY) and game._meiyong_execution_owner==-1 and game._lanzhonghou_execution_owner==-1,"I04 Max restores valid phase or keeps invalid START frozen, clearing its execution owners")
		game._game_over=true
		bridge.queue_free()
		await helper.frames(t)

func move_wall(t,game):
	var mountains=game.unit_registry.active_units().filter(func(body): return game._is_mountain_body(body))
	var live: Array[int]=[0,1,2,3,4,5]
	t.check(game.mountain_space.move(game.unit_registry.id_for(mountains[0]),1,2,live),"I04 technical partition mutation during Max choice; not an out-of-turn skill")
