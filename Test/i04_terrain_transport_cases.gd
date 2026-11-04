extends RefCounted

func run(t):
	var bridge=load("res://Test/i04_sacrifice_region_cases.gd").new().bridge_fixture(t)
	var game=bridge.game
	var state=bridge.snapshot(0)
	t.check(TerrainObservation.valid(state.terrain_space,state.space,state.units) and state.terrain_space.size()==8 and state.space.size()==6,"I04 terrain wire carries mountains separately from six permanent player seats")
	var receiver=LanSession.new()
	t.root.add_child(receiver)
	state.match=state.history.match
	receiver.mode=state.mode
	receiver.count=state.count
	receiver._view_match=state.match
	receiver.history.reset(state.match)
	receiver._receive_state(state)
	t.check(not receiver.latest.is_empty(),"I04 actual receiver accepts complete terrain ring")
	for fault in ["missing","unknown","duplicate","order","float","dragon"]:
		var changed=state.duplicate(true)
		match fault:
			"missing": changed.erase("terrain_space")
			"unknown": changed.terrain_space[1]="unit:unknown"
			"duplicate": changed.terrain_space[1]=changed.terrain_space[6]
			"order": changed.terrain_space[0]=1; changed.terrain_space[2]=0
			"float": changed.terrain_space[0]=0.0
			"dragon": changed.units[0].kind=UnitRegistry.Kind.FIRE_DRAGON
		receiver.latest={}
		receiver._receive_state(changed)
		t.check(receiver.latest.is_empty(),"I04 malformed terrain packet is rejected before state mutation: "+fault)
	var mountains=game.unit_registry.active_units().filter(func(body): return game._is_mountain_body(body))
	var first=game.unit_registry.id_for(mountains[0])
	t.check("1号" in TerrainObservation.describe(state.terrain_space,state.units) and "山甲" in TerrainObservation.describe(state.terrain_space,state.units) and TerrainObservation.location(first,state.terrain_space,state.units)=="1号 / 2号","I04 display describes stable mountain name and actual neighboring markers")
	var helper=load("res://Test/i04_paid_skill_lan_cases.gd").new()
	await helper.click(t,bridge,0,"结束出牌")
	var actions=game._ai_play_candidates(game._ai_observation(game.players[1]))
	var offered=actions.filter(func(action): return typeof(action.target)==TYPE_STRING and action.target==first and action.sub==CardData.CardSubType.STRIKE)
	t.check(not offered.is_empty(),"I04 AI initially sees legal adjacent mountain")
	var live: Array[int]=[0,1,2,3,4,5]
	game.mountain_space.move(first,1,2,live)
	t.check(game._get_strike_targets(game.players[1]).has(mountains[0]),"I04 moved mountain is still in range, isolating spatial snapshot invalidation from distance")
	if not offered.is_empty(): await game._execute_ai_action(offered[0])
	t.check(mountains[0].hp==5 and game.players[1].hand_size()==2,"I04 old AI spatial decision cannot pay even when its target remains in range")
	var fresh=game._ai_play_candidates(game._ai_observation(game.players[1])).filter(func(action): return typeof(action.target)==TYPE_STRING and action.target==first and action.sub==CardData.CardSubType.STRIKE)
	if not fresh.is_empty(): await game._execute_ai_action(fresh[0])
	t.check(mountains[0].hp==4 and game.players[1].hand_size()==1,"I04 fresh same-target AI decision can pay and strike normally")
	var updated=bridge.snapshot(1)
	t.check(TerrainObservation.valid(updated.terrain_space,updated.space,updated.units) and updated.terrain_space!=state.terrain_space,"I04 server publishes changed ring consistently after move")
	game._game_over=true
	receiver.queue_free()
	bridge.queue_free()
	await helper.frames(t)
