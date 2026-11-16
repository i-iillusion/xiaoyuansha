extends RefCounted
const SIMBA = "辛巴·古德曼"
var helper = preload("res://Test/lan_mountain_driver.gd").new()
var last_signature = ""
var source_step = 0
var second_step = 0
var source_round = 0
var give_step = 0
var reclaim_step = 0
var ready = false
var given = false
var emergency_seen = false
var duel_answered = false
var decline = false
var canceled_give = false
var trace_signature = ""

func source_name_token(state, source) -> String:
	for control in state.controls:
		if not control.disabled and control.text.begins_with(state.players[source].name + " ·"):
			return control.id
	return ""

func choose(state) -> String:
	if state.owner != state.actor or state.ended: return ""
	var signature = var_to_str([state.owner, state.turn, state.phase, state.controls, state.targets])
	if signature == last_signature: return ""
	var hero = -1
	for p in state.players:
		if p.general == SIMBA: hero = p.seat
	if hero < 0: return ""
	var source = state.players.filter(func(p): return p.general == "凯文·罗本")[0].seat
	var victim = -1
	var origin = state.space.find(source)
	for offset in range(1, state.space.size()):
		var seat = state.space[(origin + offset) % state.space.size()]
		if seat != hero:
			victim = seat
			break
	var text = "\n".join(state.labels)
	var token = ""
	if trace_signature != signature:
		trace_signature = signature
		var path = "res://.git/lan-tests/simba-trace-%d.log" % OS.get_process_id()
		var trace = FileAccess.open(path, FileAccess.READ_WRITE)
		if trace == null: trace = FileAccess.open(path, FileAccess.WRITE)
		if trace != null:
			trace.seek_end(); trace.store_line(str([state.actor, state.phase, source_step, give_step, reclaim_step, state.labels, state.controls])); trace.flush()
	if helper.find(state, "石头") != "":
		token = helper.find(state, "石头" if state.actor == source else "剪刀")
	elif "是否发动【急救】" in text:
		if ("令" + state.players[hero].name + "获得") in text:
			ready = true
			token = helper.find(state, "取消" if emergency_seen or decline else "发动急救")
			emergency_seen = true
		else: token = helper.find(state, "取消")
	elif "回收好事：" in text:
		if reclaim_step == 0:
			token = source_name_token(state, source)
			if token != "": reclaim_step = 1
		else:
			token = helper.find(state, "确认回收")
			if token != "": reclaim_step = 2
	elif "做好事：失去1体力" in text:
		if decline and not canceled_give:
			token = helper.find(state, "取消做好事")
			if token != "": canceled_give = true; give_step = 4
		elif give_step == 2:
			token = source_name_token(state, source)
			if token != "": give_step = 3
		else:
			token = helper.find(state, "确认做好事")
			if token != "": give_step = 4
	elif helper.find(state, "发动拼点") != "": token = helper.find(state, "发动拼点")
	elif "【决斗】" in text and helper.find(state, "出【杀】") != "":
		if state.actor == victim and not duel_answered:
			token = helper.find(state, "出【杀】")
			if token != "": duel_answered = true
		else: token = helper.find(state, "放弃")
	elif helper.find(state, "确认弃牌") != "" or state.controls.any(func(c): return c.toggle and not c.disabled):
		token = helper.fee(state).token
	else:
		for label in ["放弃", "不响应", "不出", "不使用", "不救"]:
			if token == "":
				for control in state.controls:
					if not control.disabled and control.text.begins_with(label): token = control.id; break
		if token == "" and state.actor != state.turn: token = helper.find(state, "取消")
		if token == "" and state.phase == TurnManager.Phase.DISCARD: token = helper.fee(state).token
		if token == "" and state.actor == source and state.phase == TurnManager.Phase.PLAY:
			if source_round == 0: source_round = state.round
			var first = ["出牌", "装备牌", "武器", "麒麟弓", "出牌", "锦囊牌", "普通锦囊", "决斗", "@victim", "是", "出牌", "基本牌", "杀", "杀", "@hero", "是", "出牌", "锦囊牌", "延时锦囊", "火烧连营", "@hero", "是", "结束出牌"]
			var second = ["出牌", "基本牌", "酒", "出牌", "基本牌", "杀", "杀", "@hero", "是", "结束出牌"]
			var route = first if source_step < first.size() else second
			var index = source_step if source_step < first.size() else second_step
			if index < route.size() and (source_step < first.size() or state.round > source_round):
				var step = route[index]
				if step.begins_with("@"):
					token = state.targets.get(str(victim if step == "@victim" else hero), "") if state.targeting else ""
				else: token = helper.find(state, step)
				if token != "":
					if source_step < first.size(): source_step += 1
					else: second_step += 1
			else: token = helper.find(state, "结束出牌")
		elif token == "" and state.actor == hero and state.phase == TurnManager.Phase.PLAY:
			if not ready or given: token = helper.find(state, "结束出牌")
			elif state.players[hero].hp <= 2:
				given = true
				token = helper.find(state, "结束出牌")
			else:
				if give_step >= 4: give_step = 0
				if give_step == 0:
					token = state.targets.get(str(hero), "")
					if token != "": give_step = 1
				elif give_step == 1:
					token = helper.find(state, "做好事")
					if token != "": give_step = 2
		elif token == "": token = helper.find(state, "结束出牌")
	if token != "": last_signature = signature
	return token
