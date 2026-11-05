extends SceneTree

var session: LanSession
var driver=preload("res://Test/lan_mountain_driver.gd").new()
var child := false
var public_case := false
var size := 3
var mode := ""
var port := 0
var child_number := 0
var children: Array[int]=[]
var child_logs: Array[String]=[]
var checks := 0
var failures := 0
var finished := false
var ready_to_finish := false
var started := false
var actions := 0
var packets := 0
var saw_two := false
var saw_one := false
var saw_rebuilt := false
var bad_actor := false
var hushan := false
var yishan := false
var jushan := false
var killed := false
var initial_ids: Array=[]
var initial_hp := 0
var initial_max := 0
var old_target_token := ""
var stale_checked := false
var done_snapshot: Dictionary={}
var done_history: Array=[]
var final_digest := ""

func _initialize(): _run.call_deferred()
func check(ok: bool,text: String):
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+text)

func _notice(text: String):
	print("NOTICE ",text)
	if text.begins_with("I04_DONE:"):
		final_digest=text.trim_prefix("I04_DONE:")
		done_snapshot=session.latest.duplicate(true)
		done_history=session.history.entries.duplicate(true)
		finished=true

func _state(state: Dictionary):
	packets+=1
	bad_actor=bad_actor or not str(state.acting_unit).is_empty()
	saw_two=saw_two or state.units.size()==2
	if saw_two and state.units.size()==1: saw_one=true
	if saw_one and state.units.size()==2: saw_rebuilt=true
	if not child: observe(state)
	if finished or ready_to_finish: return
	var token=driver.choose(state)
	if token!="":
		actions+=1
		session.act(token)

func observe(state):
	if session.bridge==null: return
	var game=session.bridge.game
	if initial_ids.is_empty() and state.units.size()==2:
		initial_ids=state.units.map(func(unit): return unit.id)
		initial_hp=game.players[0].hp
		initial_max=game.players[0].max_hp
		check(game._mountain_rules_enabled and game.players[0].general_name=="吉姆·芒顿","real Jim start and private/public rule gate enabled")
		check(game.players[0].hand_size()==6,"initial normal Jim DRAW, no injected hand resources")
	if game.turn_manager.current_player_idx==0 and game.turn_manager.current_phase==TurnManager.Phase.PLAY:
		hushan=hushan or game.turn_manager.phase_skill_used("hushan",0)
		yishan=yishan or game.turn_manager.phase_skill_used("yishan",0)
		jushan=jushan or game.turn_manager.phase_skill_used("jushan",0)
	if old_target_token=="" and game._selecting_strike_targets() and game._play_actor()==game.players[1]:
		var view=session.bridge.snapshot(1)
		for id in initial_ids:
			if view.targets.has(id): old_target_token=view.targets[id]; break
	if not stale_checked and state.units.any(func(unit): return unit.hp==2):
		var peer=session.members.keys().filter(func(key): return session.members[key].seat==1)[0]
		check(old_target_token!="" and not session._apply_action(peer,session.match_id,old_target_token),"actual remote seat cannot replay old mountain target token after first hit")
		stale_checked=true
	if not killed and saw_one:
		check(hushan and yishan and jushan,"all three active mountain skills paid and consumed normal PLAY limits")
		check(game.players[0].max_hp==initial_max-1 and game.players[0].hp==initial_hp-2 and game.players[0].jim_rebuild_pending==1,"real mountain death immediately charges one max HP and one HP after Gather loss")
		killed=true
	if killed and saw_rebuilt and game.turn_manager.current_player_idx==0 and game.turn_manager.current_phase==TurnManager.Phase.PLAY:
		check(game.players[0].jim_rebuild_pending==0 and state.units.size()==2,"next real normal START spends pending rebuild and creates one replacement")
		check(not state.units.any(func(unit): return unit.id==initial_ids[0]) and state.units.any(func(unit): return unit.id==initial_ids[1]),"replacement has new identity, surviving original mountain retained")
		check(not game._game_over and game.players.size()==size,"lifecycle smoke does not fabricate victory or extra fixed players")
		ready_to_finish=true

func _run():
	for arg in OS.get_cmdline_user_args():
		if arg=="--lan-child": child=true
		if arg=="--public-mountain-case": public_case=true
		if arg.begins_with("--players="): size=int(arg.trim_prefix("--players="))
		if arg.begins_with("--port="): port=int(arg.trim_prefix("--port="))
		if arg.begins_with("--child-number="): child_number=int(arg.trim_prefix("--child-number="))
		if arg.begins_with("--mode="): mode=arg.trim_prefix("--mode=")
	if mode=="": mode=GameModes.CLASSIC if size==5 else GameModes.FREE_FOR_ALL
	var holder=Node.new()
	holder.name="MountainHarness"
	root.add_child(holder)
	session=LanSession.new()
	session.name="Session"
	holder.add_child(session)
	session.notice.connect(_notice)
	session.state_received.connect(_state)
	if child:
		session.lobby_changed.connect(func(state):
			if state.is_empty() or state.playing: return
			for member in state.members:
				if member.peer==session.multiplayer.get_unique_id() and not member.ready: session.choose("稻草人",true))
		check(session.join_room("127.0.0.1","P%d"%child_number,port)==OK,"independent remote ENet joins actual session")
	else:
		port=32000+randi_range(0,9000)
		session._enable_mountain_rules_for_tests=not public_case
		check(session.host("P0",size,port,mode)==OK,"actual ENet host starts")
		session.set_pace(AiActionPacer.Speed.FAST)
		if public_case: check("吉姆·芒顿" in LanSession.GENERALS and GeneralData.get_implementation_status("吉姆·芒顿")=="prototype","public entry enables verified Jim")
		session.choose("吉姆·芒顿",true)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.git/lan-tests"))
		for i in range(1,size):
			var log=ProjectSettings.globalize_path("res://.git/lan-tests/mountain-client-%d-%d.log"%[port,i])
			child_logs.append(log)
			var args=PackedStringArray(["--headless","--disable-render-loop","--log-file",log,"--path",ProjectSettings.globalize_path("res://"),"--script","res://Test/test_i04_network.gd","--","--lan-child","--port="+str(port),"--players="+str(size),"--child-number="+str(i),"--mode="+mode])
			if public_case: args.append("--public-mountain-case")
			var pid=OS.create_process(OS.get_executable_path(),args)
			check(pid>0,"launch independent client process")
			if pid>0: children.append(pid)
	var deadline=Time.get_ticks_msec()+45000
	while Time.get_ticks_msec()<deadline and not finished:
		if not child and not started and session.members.size()==size and session.members.values().all(func(member): return member.ready): started=session.begin_match()
		if not child and ready_to_finish:
			done_snapshot=session.latest.duplicate(true)
			done_history=session.history.entries.duplicate(true)
			final_digest=var_to_str(done_snapshot.terrain_space).sha256_text()
			for peer in session.members:
				if peer!=1: session._remote_notice.rpc_id(peer,"I04_DONE:"+final_digest)
			finished=true
			break
		await create_timer(0.02).timeout
	check(finished,"five-skill real mountain lifecycle completes within original 45 seconds")
	check(packets>0 and actions>0,"actual session packets and own authorized actions observed")
	check(saw_two and saw_one and saw_rebuilt,"remote sees initial pair, one death, next START replacement")
	check(not bad_actor,"no mountain ever becomes acting unit")
	if finished:
		check(TerrainObservation.valid(done_snapshot.terrain_space,done_snapshot.space,done_snapshot.units),"final complete terrain packet validates")
		check(var_to_str(done_snapshot.terrain_space).sha256_text()==final_digest,"host and remote final positions match")
		var text=""
		for entry in done_history: text+=entry.text+"\n"
		for skill in ["王屋太行","护山","移山","聚山","造山"]: check(skill in text,"public history contains real skill settlement: "+skill)
	if not child:
		await create_timer(0.5).timeout
		for pid in children:
			if OS.is_process_running(pid):
				await create_timer(0.3).timeout
				if OS.is_process_running(pid): OS.kill(pid)
		for log in child_logs:
			var text=FileAccess.get_file_as_string(log)
			check("RESULT:" in text and "0 failures" in text and "SCRIPT ERROR" not in text and "ERROR:" not in text and "FAIL " not in text,"independent client log clean")
	session.close()
	await process_frame
	print("RESULT: %d asserts, %d failures"%[checks,failures])
	quit(1 if failures else 0)
