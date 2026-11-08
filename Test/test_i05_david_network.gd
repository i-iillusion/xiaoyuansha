extends SceneTree
const DAVID="大卫·法米尔"
var session: LanSession
var driver=preload("res://Test/lan_david_driver.gd").new()
var child=false
var host_controller=false
var drop_case=false
var reserve_case=false
var cancel_case=false
var waiting=false
var wait_finished=false
var began_at=0
var wait_began_at=0
var reserve_observed=false
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
var stale_token=""
var stale_checked=false
var audit: Dictionary={}
var bonus_draw_observed=false

func _initialize(): run.call_deferred()
func check(ok:bool,message:String):
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+message)
func signature(state) -> String:
	return var_to_str(state.players.map(func(p): return [p.seat,p.hp,p.dead,p.hand_count,p.general,p.get("empty_fields",0),p.get("good_fields",0)])).sha256_text()
func notice(text:String):
	print("NOTICE "+text)
	if text.begins_with("I05_DONE:"):
		digest=text.trim_prefix("I05_DONE:")
		final_state=session.latest.duplicate(true)
		final_history=session.history.entries.duplicate(true)
		finished=true
	if drop_case and ("本局中断" in text or "房主已断开" in text): aborted=true; finished=true
func capture_immune():
	if child or drop_case or session.bridge==null: return
	var heroes=session.bridge.game.players.filter(func(p): return p.general_name==DAVID)
	if heroes.is_empty(): return
	var hero=heroes[0]
	if hero.farm_good_fields==1 and hero.hand_size()==3 and session.bridge.game._play_actor()==hero:
		bonus_draw_observed=true
	if stale_token=="": stale_token=driver.helper.find(session.bridge.snapshot(hero.seat_index),"发动摔角")

func state_changed(state):
	packets+=1
	capture_immune() # Observe the actual published window before a fast peer answers.
	if finished: return
	if drop_case and state.owner==state.actor and state.players[state.actor].general==DAVID and driver.helper.find(state,"发动摔角")!="":
		dropped=true
		session.close()
		finished=true
		return
	if reserve_case and state.players[state.actor].general==DAVID and state.owner==state.actor:
		if not wait_finished and driver.helper.find(state,"发动摔角")!="":
			if not waiting: wait_began_at=Time.get_ticks_msec()
			waiting=true
			driver.ready=true
			if Time.get_ticks_msec()-wait_began_at<32000: return
			wait_finished=true
			var cancel=driver.helper.find(state,"取消")
			if cancel!="": actions+=1; session.act.call_deferred(cancel)
			return # Natural base-step plus reserve usage, then an actual client cancel.

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
	driver.decline_wrestle=cancel_case or reserve_case
	began_at=Time.get_ticks_msec()
	if mode=="": mode=GameModes.CLASSIC if size==5 else GameModes.FREE_FOR_ALL
	var holder=Node.new()
	holder.name="DavidHarness"
	root.add_child(holder)
	session=LanSession.new()
	session.name="Session"
	holder.add_child(session)
	session.notice.connect(notice)
	session.state_received.connect(state_changed)
	if child:
		session.lobby_changed.connect(func(state):
			if state.is_empty() or state.playing: return
			for member in state.members:
				if member.peer==session.multiplayer.get_unique_id() and not member.ready:
					session.choose(DAVID if number==1 and not host_controller else "稻草人",true))
		check(session.join_room("127.0.0.1","P%d"%number,port)==OK,"independent David client joins actual ENet")
	else:
		port=32000+randi_range(0,9000)
		check(session.host("P0",size,port,mode)==OK,"actual David ENet authority starts")
		session.set_pace(AiActionPacer.Speed.FAST)
		check(DAVID in LanSession.GENERALS and GeneralData.get_implementation_status(DAVID)=="prototype","public roster offers David without metadata allocation")
		session.choose(DAVID if host_controller else "稻草人",true)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.git/lan-tests"))
		for i in range(1,size):
			var log=ProjectSettings.globalize_path("res://.git/lan-tests/peter-client-%d-%d.log"%[port,i])
			child_logs.append(log)
			var args=PackedStringArray(["--headless","--disable-render-loop","--log-file",log,"--path",ProjectSettings.globalize_path("res://"),"--script","res://Test/test_i05_david_network.gd","--","--lan-child","--port="+str(port),"--players="+str(size),"--child-number="+str(i),"--mode="+mode])
			if host_controller: args.append("--host-controller")
			if drop_case: args.append("--drop-case")
			if reserve_case: args.append("--reserve-case")
			if cancel_case: args.append("--cancel-case")
			var pid=OS.create_process(OS.get_executable_path(),args)
			check(pid>0,"launch independent David client process")
			if pid>0: children.append(pid)
	var deadline=Time.get_ticks_msec()+45000
	while Time.get_ticks_msec()<deadline and not finished:
		if not child and not started and session.members.size()==size and session.members.values().all(func(m): return m.ready):
			started=session.begin_match()
			if started:
				check(session.bridge.game._david_rules_enabled and session.bridge.game._wrestling_rules_enabled,"production David capabilities enabled without test override")
				session.bridge.game.card_action_committed.connect(func(a): facts.append(a))
		if not child and started and not drop_case and session.bridge!=null:
			var game=session.bridge.game
			var hero=game.players.filter(func(p): return p.general_name==DAVID)[0]
			var victim=driver.victim_for(game.players,hero.seat_index)
			var view=session.bridge.snapshot(hero.seat_index)
			var immune=driver.helper.find(view,"发动摔角")
			if reserve_case and immune!="" and game._step_remaining<=0 and game._bank_remaining>0 and game._bank_remaining<GameManager.BANK_SECONDS:
				reserve_observed=true
			if stale_token=="" and immune!="": stale_token=immune
			elif stale_token!="" and immune=="" and not stale_checked:
				var peer=session.members.keys().filter(func(key): return session.members[key].seat==hero.seat_index)[0]
				check(not session._apply_action(peer,session.match_id,stale_token),"actual owner cannot replay prior immune token into a later window")
				stale_checked=true
			var virtual_nulls=facts.filter(func(a): return a.actor_body==hero and a.sub_type==CardData.CardSubType.NULLIFICATION and a.is_virtual)
			if bonus_draw_observed and virtual_nulls.size()==2 and hero.farm_good_fields==0 and hero.farm_empty_fields==0 and game._pending_card_actions.is_empty() and game._choice_prompt_stack.is_empty():
				session._publish_states()
				final_state=session.latest.duplicate(true)
				final_history=session.history.entries.duplicate(true)
				digest=signature(final_state)
				var refused=reserve_case or cancel_case
				audit={"hp":hero.hp==hero.max_hp and hero.max_hp==4+(1 if hero.identity=="主公" else 0),
					"facts":facts.size()==(9 if refused else 10) and facts.all(func(a): return a.settlement_completed),
					"duels":facts.filter(func(a): return a.actor_body==hero and a.sub_type==CardData.CardSubType.DUEL and a.is_virtual).size()==(0 if refused else 1),
					"equipment":(hero.get_armor()==-1 and game.players[victim].determined_cards.any(func(c): return c.sub_type==CardData.CardSubType.SHENGGUANG_BAIYI)) if refused else hero.get_armor()==CardData.CardSubType.SHENGGUANG_BAIYI,
					"draw":bonus_draw_observed}
				for peer in session.members:
					if peer!=1: session._remote_notice.rpc_id(peer,"I05_DONE:"+digest)
				finished=true
		await create_timer(0.02).timeout
	if not finished: print("DIAGNOSTIC ",driver.source_step,"/",driver.hero_step," ",session.latest.get("phase")," ",session.latest.get("notice")," ",session.latest.get("labels")," ",session.latest.get("controls"))
	check(finished,"David lifecycle or requested disconnect finishes within original 45 seconds")
	check(packets>0 and (actions>0 or drop_case),"actual packets and authorized own actions observed")
	if drop_case:
		check(dropped or aborted,"disconnect during active David window aborts match rather than granting another actor control")
		if not child: check(session.bridge==null and session.match_id=="","authority discards aborted game and match identity")
	elif finished:
		check(signature(final_state)==digest,"host and remote agree on public HP, death and hand counts")
		var text=""
		for entry in final_history: text+=entry.text+"\n"
		for phrase in ["种田","升级为好田","无懈可击"]:
			check(phrase in text,"public history contains actual David result: "+phrase)
		if reserve_case or cancel_case:
			check(not final_history.any(func(e): return e.kind=="skill" and "我要跟你摔角" in e.text),"declining Wrestle never records a false activation")
		if reserve_case: check(Time.get_ticks_msec()-began_at>=32000,"actual base step and reserve elapsed without shortening test clock")
		if not child:
			check(audit.hp,"actual opening HP retains correct general/lord layers")
			if reserve_case: check(reserve_observed,"base step naturally expires into positive reserve before actual client cancel")
			check(stale_checked,"lifecycle includes checked stale immune input")
			check(audit.facts,"all natural hand and virtual USE facts complete with correct count")
			check(audit.duels,"confirmed or declined extra Duel count matches real response")
			check(audit.equipment and audit.draw,"original equipment and earned good-field natural next-turn draw verified")
	if not child:
		await create_timer(0.5).timeout
		for pid in children:
			if OS.is_process_running(pid):
				await create_timer(0.3).timeout
				if OS.is_process_running(pid): OS.kill(pid)
		for log in child_logs:
			var text=FileAccess.get_file_as_string(log)
			check("RESULT:" in text and "0 failures" in text and "SCRIPT ERROR" not in text and "ERROR:" not in text and "FAIL " not in text,"independent David client log clean")
	session.close()
	await process_frame
	print("RESULT: %d asserts, %d failures"%[checks,failures])
	quit(1 if failures else 0)
