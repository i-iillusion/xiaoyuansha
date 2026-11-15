extends RefCounted
const SUNNY="桑尼·斯派"
const Filming=preload("res://Test/i05_sunny_filming_cases.gd")

func fixture(t,count:=5,mode:=GameModes.CLASSIC):
	var game=load("res://Test/h02_integration_cases.gd").new().fixture(t,count,mode)
	game._corruption_rules_enabled=false # Isolated active-skill fixture; actual Greed cases explicitly enable it.
	game.lan_enabled=true
	game._spy_rules_enabled=true
	game.turn_manager.current_phase=TurnManager.Phase.PLAY
	var actor=game.players[0]
	actor.general_name=SUNNY
	actor.hand.clear(); actor.determined_cards.clear()
	actor.capture_game_start_state()
	game._set_input_player(actor)
	return game

func run(t):
	var saved=[GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	await actual(t)
	await guards(t)
	await granted(t)
	await native(t)
	for seat in [0,1]:
		for mode in ["confirm","cancel","restore","phase","lord"]:
			await bridge_case(t,seat,mode)
	GameManager.selected_players=saved[0]; GameManager.selected_mode=saved[1]; GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]; GameManager.random_identity=saved[4]

func actual(t):
	for own in [false,true]:
		var game=fixture(t)
		var actor=game.players[0]
		if own:
			game.turn_manager.current_player_idx=1
			actor=game.players[1]
			game.players[0].general_name="稻草人"
			actor.general_name=SUNNY
			actor.hand.clear(); actor.determined_cards.clear(); actor.capture_game_start_state()
			game._set_input_player(actor)
		var a=actor if own else game.players[1]
		var b=game.players[2]
		var roles=[a.identity,b.identity]
		var hp=[a.hp,b.hp,a.max_hp,b.max_hp]
		a.general_name=SUNNY if own else load("res://Test/i05_peter_peach_cases.gd").PETER
		var immune: Array=[]
		game._peter_ignore_override=func(_p,_a,_k,_v): immune.append(true); return 1
		var list: Array[Player]=[a,b]
		if not own:
			t.check(await game._peter_ignore_effect(a,list,"spy",func(): return true)==0 and immune.is_empty(),"I05c Q7 common immunity boundary also rejects Spy without asking Peter")
		t.check(game._execute_spy(actor,list)==1 and a.identity==roles[1] and b.identity==roles[0] and actor.spy_used,"I05c actual Spy exchanges two non-lord identities and consumes limited use")
		t.check(immune.is_empty() and hp==[a.hp,b.hp,a.max_hp,b.max_hp] and actor.hand_size()==0,"I05c Q7 Peter cannot interfere; Spy costs no hand card or hp")
		t.check(game._execute_spy(actor,list)==0 and a.identity==roles[1],"I05c limited skill cannot repeat before restoration")
		actor.restore_game_start_state()
		t.check(not actor.spy_used and a.identity==roles[1] and game._execute_spy(actor,list)==1,"I05c Sage restores actual Spy availability without undoing prior exchanged identities")
		t.check(a.identity==roles[0] and b.identity==roles[1] and game._card_action_serial==0,"I05c second restored Spy reverses pair without manufacturing card USE")
		await load("res://Test/i05_david_farming_cases.gd").new().dispose(t,game)
	var game=fixture(t)
	var actor=game.players[0]
	var same: Array[Player]=[game.players[2],game.players[3]]
	t.check(same[0].identity==same[1].identity and game._execute_spy(actor,same)==1 and actor.spy_used,"I05c same hidden-role pair is a legal spent use, preventing eligibility leaks")
	await load("res://Test/i05_david_farming_cases.gd").new().dispose(t,game)
	for count in [6,8,10]:
		game=fixture(t,count,GameModes.AMBITIOUS)
		actor=game.players[0]
		var former=game.players.back()
		var next=game.players[1]
		var pair: Array[Player]=[former,next]
		t.check(game._execute_spy(actor,pair)==1 and game._ambitious_state.valid() and next.identity=="奸雄","I05c actual Spy synchronizes ambitious holder and trusted cache")
		await load("res://Test/i05_david_farming_cases.gd").new().dispose(t,game)

func guards(t):
	for fault in ["gate","used","phase","actor","general","lord","duplicate","count","dead","kneel","ffa"]:
		var game=fixture(t,5,GameModes.FREE_FOR_ALL if fault=="ffa" else GameModes.CLASSIC)
		var p=game.players[0]
		var a=game.players[1]
		var b=game.players[2]
		var list: Array[Player]=[a,b]
		if fault=="gate": game._spy_rules_enabled=false
		if fault=="used": p.spy_used=true
		if fault=="phase": game.turn_manager.current_phase=TurnManager.Phase.DRAW
		if fault=="actor": game.turn_manager.play_actor_idx=1
		if fault=="general": p.general_name="稻草人"
		if fault=="lord": list.assign([p,b])
		if fault=="duplicate": list.assign([a,a])
		if fault=="count": list.pop_back()
		if fault=="dead": a.hp=0; a.mark_dead()
		if fault=="kneel": a.general_name="布鲁斯·萨维奇"; a.kneeling=true
		var before=[a.identity,b.identity,p.spy_used]
		t.check(game._execute_spy(p,list)==0 and before==[a.identity,b.identity,p.spy_used],"I05c rejected Spy cannot mutate roles or spend use: "+fault)
		await load("res://Test/i05_david_farming_cases.gd").new().dispose(t,game)
	var game=fixture(t,6,GameModes.AMBITIOUS)
	game.players[2].identity="忠臣"
	var list: Array[Player]=[game.players[1],game.players[3]]
	t.check(game._execute_spy(game.players[0],list)==game.CHOICE_INVALID and not game.players[0].spy_used,"I05c corrupt cached roster aborts before limited-use commitment")
	await load("res://Test/i05_david_farming_cases.gd").new().dispose(t,game)

func granted(t):
	var game=fixture(t)
	var source=game.players[0]
	var actor=game.players[1]
	source.general_name="麦克斯·欧尼斯特"; actor.general_name=SUNNY
	game.turn_manager.current_phase=TurnManager.Phase.START
	game._meiyong_override=func(): return true
	game._meiyong_option_override=func(): return 2
	game._meiyong_target_override=func(): return actor
	var action=func():
		var list: Array[Player]=[actor,game.players[2]]
		t.check(game._play_actor()==actor and game.turn_manager.current_player_idx==0 and game._execute_spy(actor,list)==1,"I05c actual Max-granted PLAY permits non-lord actor to exchange own identity")
		game.end_play_phase()
	action.call_deferred()
	t.check(await game._maybe_meiyong(source)==1 and actor.spy_used and game.turn_manager.current_phase==TurnManager.Phase.START,"I05c granted Spy resumes donor START without moving bodies or source turn")
	await load("res://Test/i05_david_farming_cases.gd").new().dispose(t,game)

func native(t):
	var game=fixture(t)
	game.lan_enabled=false
	var p=game.players[0]
	game._open_player_detail(p)
	var popup=game._detail_popup_root.get_child(0)
	var actions=popup._skills_container.get_children().filter(func(n): return n is Button and "【间谍】" in n.text)
	t.check(actions.size()==1 and not actions[0].disabled,"I05c private native detail exposes exactly one available Spy button")
	if not actions.is_empty(): actions[0].pressed.emit()
	game._on_spy_target_click(p)
	game._on_spy_target_click(game.players[1])
	game._on_spy_target_click(game.players[2])
	t.check(game._spy_targets==[game.players[1],game.players[2]] and not game._confirm_target_btn.disabled,"I05c native selector excludes public lord and requires two non-lords")
	game._confirm_target_btn.pressed.emit()
	t.check(p.spy_used and game.players[1].identity=="反贼" and game.players[2].identity=="忠臣" and not game._is_spy_targeting,"I05c native confirmation synchronously commits identity pair and limited state")
	game._open_player_detail(p)
	popup=game._detail_popup_root.get_child(game._detail_popup_root.get_child_count()-1)
	actions=popup._skills_container.get_children().filter(func(n): return n is Button and "【间谍】" in n.text)
	t.check(actions.size()==1 and actions[0].disabled,"I05c spent native limited action is visibly disabled")
	await load("res://Test/i05_david_farming_cases.gd").new().dispose(t,game)

func bridge_case(t,seat,mode):
	var bridge=LanGameBridge.new()
	t.root.add_child(bridge)
	var roster: Array[Dictionary]=[]
	for n in 5: roster.append({"name":"P%d"%n,"general":"稻草人"})
	t.check(bridge.start(roster,GameModes.CLASSIC,AiActionPacer.Speed.FAST),"I05c real identity Bridge starts before private Sunny fixture")
	var game=bridge.game
	game._halt_countdown(); game._spy_rules_enabled=true
	var p=game.players[seat]
	p.general_name=SUNNY; p.capture_game_start_state()
	var frame: Dictionary={}
	if seat==1:
		game.turn_manager.current_phase=TurnManager.Phase.START
		frame=game.turn_manager.begin_standalone_play(seat)
		game._do_play(0); game._halt_countdown()
	game._set_input_player(p); game._open_player_detail(p)
	var skill=""
	for control in bridge.snapshot(seat).controls:
		if "【间谍】" in control.text: skill=control.id
	t.check(not skill.is_empty() and not bridge.submit(1-seat,skill) and bridge.submit(seat,skill),"I05c remote Spy detail is actor-owned")
	var state=bridge.snapshot(seat)
	var lord=game.players.filter(func(body): return body.identity=="主公")[0]
	var pair: Array[Player]=[]
	pair.assign(game.players.filter(func(body): return body.identity!="主公").slice(0,2))
	t.check(not state.targets.has(str(lord.seat_index)),"I05c remote target capabilities never include public lord")
	var old=""
	for target in pair:
		var token=bridge.snapshot(seat).targets.get(str(target.seat_index),"")
		old=token
		t.check(not token.is_empty() and not bridge.submit(1-seat,token) and bridge.submit(seat,token),"I05c remote non-lord toggles are owner-bound, including self when legal")
	var confirm=Filming.new().FarmingToken(bridge,seat,"确认间谍（2/2 名目标）")
	var before=[pair[0].identity,pair[1].identity]
	if mode=="cancel":
		t.check(bridge.submit(seat,Filming.new().FarmingToken(bridge,seat,"取消选择")),"I05c remote cancellation does not spend limited use")
	elif mode=="restore": p.restore_game_start_state()
	elif mode=="phase": game.turn_manager.current_phase=TurnManager.Phase.DRAW
	elif mode=="lord": pair[0].identity="主公"
	if mode=="confirm": t.check(bridge.submit(seat,confirm) and not bridge.submit(seat,confirm),"I05c remote confirmed Spy token commits only once")
	elif mode!="cancel":
		bridge.submit(seat,confirm)
	for i in 3: await t.process_frame
	t.check(p.spy_used==(mode=="confirm") and (mode!="confirm" or [pair[0].identity,pair[1].identity]==[before[1],before[0]]),"I05c stale/cancelled remote choice does not spend limited state: "+mode)
	if mode=="confirm":
		for viewer in [0,1,2,3]:
			var visible=bridge.snapshot(viewer)
			for row in visible.players:
				var subject=game.players[row.seat]
				t.check(row.identity==(subject.identity if row.seat==viewer or subject.identity_revealed else ""),"I05c remote views show only each owner's new role and public lord")
	t.check(not bridge.submit(seat,skill) and not bridge.submit(seat,old),"I05c old remote menu and target tokens cannot replay after selection")
	if seat==1 and mode!="phase": t.check(game.turn_manager.complete_standalone_phase(frame),"I05c remote gifted Spy phase returns to donor")
	game._game_over=true; bridge.queue_free()
	for i in 3: await t.process_frame
