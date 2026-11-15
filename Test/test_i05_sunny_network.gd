extends SceneTree
const SUNNY="桑尼·斯派"
var session: LanSession
var driver=preload("res://Test/lan_sunny_driver.gd").new()
var child=false
var host_controller=false
var drop_case=false
var reserve_case=false
var cancel_case=false
var size=3
var mode=""
var port=0
var number=0
var children: Array[int]=[]
var child_logs: Array[String]=[]
var checks=0
var failures=0
var packets=0
var actions=0
var started=false
var finished=false
var aborted=false
var dropped=false
var digest=""
var final_state: Dictionary={}
var final_history: Array=[]
var facts: Array=[]
var old_roles: Array=[]
var stale_token=""
var wrong_checked=false
var wait_began=0
var reserve_observed=false
var greed_counts: Array=[]

func _initialize(): run.call_deferred()
func check(ok:bool,message:String):
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+message)
func signature(state) -> String:
	return var_to_str(state.players.map(func(p): return [p.seat,p.hp,p.dead,p.hand_count,p.general])).sha256_text()
func notice(text:String):
	if text.begins_with("SUNNY_DONE:"):
		digest=text.trim_prefix("SUNNY_DONE:")
		final_state=session.latest.duplicate(true); final_history=session.history.entries.duplicate(true); finished=true
	if drop_case and ("本局中断" in text or "房主已断开" in text): aborted=true; finished=true
func state_changed(state):
	packets+=1
	if finished: return
	if not child and session.bridge!=null:
		var hero=session.bridge.game.players.filter(func(p): return p.general_name==SUNNY)[0].seat_index
		var view=session.bridge.snapshot(hero)
		if "本次额外摸的牌发动【贪污】" in "\n".join(view.labels) and stale_token=="":
			var game=session.bridge.game
			greed_counts=[game.players[hero].hand_size(),game.players[1 if host_controller else 0].hand_size()]
			check(facts.size()==5 and not facts[4].settlement_completed,"initial deals and ordinary DRAW never interrupt; real Harvest remains pending after bow, Duel, Kill response and Strike")
			stale_token=driver.helper.find(view,"发动")
			for peer in session.members:
				if session.members[peer].seat!=hero:
					wrong_checked=true
					check(not session._apply_action(peer,session.match_id,stale_token),"wrong peer cannot answer actual Sunny Greed window")
					break
	if state.owner==state.actor and "本次额外摸的牌发动【贪污】" in "\n".join(state.labels):
		if wait_began==0: wait_began=Time.get_ticks_msec()
		# A real client deliberates briefly, so authority can audit the
		# published window before the independent peer answers it.
		if Time.get_ticks_msec()-wait_began<150: return
		if drop_case:
			dropped=true; session.close(); finished=true; return
		if reserve_case:
			if wait_began==0: wait_began=Time.get_ticks_msec()
			if Time.get_ticks_msec()-wait_began<32000: return
	var token=driver.choose(state)
	if token!="": actions+=1; session.act.call_deferred(token)

func run():
	for arg in OS.get_cmdline_user_args():
		if arg=="--lan-child": child=true
		if arg=="--host-controller": host_controller=true
		if arg=="--drop-case": drop_case=true
		if arg=="--reserve-case": reserve_case=true
		if arg=="--cancel-case": cancel_case=true
		if arg.begins_with("--players="): size=int(arg.trim_prefix("--players="))
		if arg.begins_with("--port="): port=int(arg.trim_prefix("--port="))
		if arg.begins_with("--child-number="): number=int(arg.trim_prefix("--child-number="))
		if arg.begins_with("--mode="): mode=arg.trim_prefix("--mode=")
	if mode=="": mode=GameModes.CLASSIC if size==5 else GameModes.FREE_FOR_ALL
	driver.decline=cancel_case or reserve_case
	var holder=Node.new(); holder.name="SunnyHarness"; root.add_child(holder)
	session=LanSession.new(); session.name="Session"; holder.add_child(session)
	session.notice.connect(notice); session.state_received.connect(state_changed)
	if child:
		session.lobby_changed.connect(func(state):
			if state.is_empty() or state.playing: return
			for member in state.members:
				if member.peer==session.multiplayer.get_unique_id() and not member.ready:
					session.choose(SUNNY if number==1 and not host_controller else "稻草人",true))
		check(session.join_room("127.0.0.1","P%d"%number,port)==OK,"independent Sunny client joins ENet")
	else:
		port=32000+randi_range(0,9000)
		check(session.host("P0",size,port,mode)==OK,"real Sunny ENet authority starts")
		session.set_pace(AiActionPacer.Speed.FAST)
		check(LanSession.GENERALS.count(SUNNY)==1 and GeneralData.get_implementation_status(SUNNY)=="prototype","public roster offers Sunny exactly once")
		session.choose(SUNNY if host_controller else "稻草人",true)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.git/lan-tests"))
		for i in range(1,size):
			var log=ProjectSettings.globalize_path("res://.git/lan-tests/sunny-client-%d-%d.log"%[port,i]); child_logs.append(log)
			var args=PackedStringArray(["--headless","--disable-render-loop","--log-file",log,"--path",ProjectSettings.globalize_path("res://"),"--script","res://Test/test_i05_sunny_network.gd","--","--lan-child","--port="+str(port),"--players="+str(size),"--child-number="+str(i),"--mode="+mode])
			for flag in [[host_controller,"--host-controller"],[drop_case,"--drop-case"],[reserve_case,"--reserve-case"],[cancel_case,"--cancel-case"]]:
				if flag[0]: args.append(flag[1])
			var pid=OS.create_process(OS.get_executable_path(),args); check(pid>0,"launch independent Sunny client"); children.append(pid)
	var deadline=Time.get_ticks_msec()+45000
	while Time.get_ticks_msec()<deadline and not finished:
		if not child and not started and session.members.size()==size and session.members.values().all(func(m): return m.ready):
			started=session.begin_match()
			if started:
				var game=session.bridge.game
				check(game._paipian_rules_enabled and game._spy_rules_enabled and game._corruption_rules_enabled,"all Sunny production abilities enabled without overrides")
				old_roles=game.players.map(func(p): return p.identity)
				game.card_action_committed.connect(func(e): facts.append(e))
		if not child and started and not drop_case and session.bridge!=null:
			var game=session.bridge.game; var hero=game.players.filter(func(p): return p.general_name==SUNNY)[0]
			var view=session.bridge.snapshot(hero.seat_index)
			if reserve_case and "本次额外摸的牌发动【贪污】" in "\n".join(view.labels) and game._step_remaining<=0 and game._bank_remaining>0 and game._bank_remaining<GameManager.BANK_SECONDS: reserve_observed=true
			var filmed=game.action_history.entries.any(func(e): return e.kind=="skill" and "【拍片】" in e.text)
			if filmed and (mode==GameModes.FREE_FOR_ALL or hero.spy_used) and game._paipian_pending.is_empty() and game._pending_card_actions.is_empty() and game._choice_prompt_stack.is_empty():
				check(facts.size()==5 and facts.all(func(e): return e.settlement_completed),"four natural USE cards plus one real Kill response complete once; Sunny skills fabricate no USE")
				check(wrong_checked and stale_token!="","actual Greed input token observed and wrong peer checked")
				var peer=session.members.keys().filter(func(key): return session.members[key].seat==hero.seat_index)[0]
				check(not session._apply_action(peer,session.match_id,stale_token),"old Greed token cannot replay in later PLAY")
				var source=game.players[1 if hero.seat_index==0 else 0]
				check(source.hp==source.max_hp and hero.hp==hero.max_hp-1,"paid Filming heals injured source while preserving other HP")
				var transfer=0 if cancel_case or reserve_case else 1
				check(greed_counts.size()==2 and source.hand_size()==greed_counts[1]-transfer and hero.hand_size()==greed_counts[0]+transfer+2,"Greed moves exactly Harvest's new card; own Harvest plus normal DRAW minus one Filming fee are exact")
				for seat in size:
					var snap=session.bridge.snapshot(seat)
					check(snap.players.all(func(row): return row.identity==PlayerObservation.visible_identity(game.players[row.seat],game.players[seat])),"identity observations remain viewer-specific after Spy")
				if mode!=GameModes.FREE_FOR_ALL:
					var eligible=game.players.filter(func(p): return p.identity!="主公")
					check(eligible[0].identity==old_roles[eligible[1].seat_index] and eligible[1].identity==old_roles[eligible[0].seat_index],"Spy exchanges real non-lord identities atomically")
					if mode==GameModes.AMBITIOUS: check(game._ambitious_state.valid(),"real ambitious identity cache remains consistent after Spy")
				if reserve_case: check(reserve_observed,"real base step expires into reserve without shortened clocks")
				session._publish_states(); final_state=session.latest.duplicate(true); final_history=session.history.entries.duplicate(true); digest=signature(final_state)
				for key in session.members:
					if key!=1: session._remote_notice.rpc_id(key,"SUNNY_DONE:"+digest)
				finished=true
		await create_timer(0.02).timeout
	if not finished:
		var diagnostic=session.bridge.snapshot(0 if host_controller else 1) if not child and session.bridge!=null else session.latest
		print("DIAGNOSTIC ",driver.source_step,"/",driver.hero_step," ",diagnostic.get("phase"),"/",diagnostic.get("actor")," ",diagnostic.get("labels")," ",diagnostic.get("controls"))
	check(finished,"natural Sunny lifecycle or disconnect completes within original 45 seconds")
	check(packets>0 and (actions>0 or drop_case),"actual packets and own actions observed")
	if drop_case:
		check(dropped or aborted,"active Greed disconnect aborts rather than forging victory")
		if not child: check(session.bridge==null and session.match_id=="","authority releases aborted match")
	elif finished:
		check(signature(final_state)==digest,"host and client agree on final public state")
		check(final_history.any(func(e): return e.kind=="skill" and "【拍片】" in e.text),"history reports actual paid Filming")
		check(final_history.any(func(e): return e.kind=="skill" and "【贪污】" in e.text)==not (cancel_case or reserve_case),"confirmed or declined Greed is reported accurately")
	if not child:
		await create_timer(0.5).timeout
		for pid in children:
			if OS.is_process_running(pid):
				await create_timer(0.3).timeout
				if OS.is_process_running(pid): OS.kill(pid)
		for log in child_logs:
			var text=FileAccess.get_file_as_string(log)
			check("RESULT:" in text and "0 failures" in text and "SCRIPT ERROR" not in text and "ERROR:" not in text and "FAIL " not in text,"independent Sunny client log is clean")
	session.close(); await process_frame
	print("RESULT: %d asserts, %d failures"%[checks,failures]); quit(1 if failures else 0)
