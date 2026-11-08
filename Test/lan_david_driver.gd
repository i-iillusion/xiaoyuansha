extends RefCounted
const DAVID = "大卫·法米尔"
var helper = preload("res://Test/lan_mountain_driver.gd").new()
var last_signature = ""
var hero_step = 0
var source_step = 0
var ready = false
var decline_wrestle = false

func victim_for(players, hero): return (hero + 1) % players.size()

func choose(state) -> String:
	if state.owner != state.actor or state.ended: return ""
	var signature = var_to_str([state.owner, state.turn, state.phase, state.controls, state.targets])
	if signature == last_signature: return ""
	var hero = -1
	for p in state.players:
		if p.general == DAVID: hero = p.seat
	if hero < 0: return ""
	var opponent = victim_for(state.players, hero)
	var text = "\n".join(state.labels)
	var result = ""
	if helper.find(state, "发动摔角") != "":
		result = helper.find(state, "取消" if decline_wrestle else "发动摔角")
	elif state.actor == hero and "【决斗】" in text and ("对 %s 生效" % state.players[hero].name) in text:
		result = helper.find(state, "空田当无懈")
		if result == "": result = helper.find(state, "好田当无懈")
	# Counter-counter windows and other effects must not consume another field.
	if result == "" and (helper.find(state, "打出【无懈可击】") != "" or helper.find(state, "空田当无懈") != "" or helper.find(state, "好田当无懈") != ""):
		result = helper.find(state, "放弃")
		if result == "": result = helper.find(state, "取消")
	if result == "":
		for skip in ["不响应", "不出", "不救", "不使用", "放弃"]:
			result = helper.find(state, skip)
			if result != "": break
	if result == "" and state.phase == TurnManager.Phase.DISCARD:
		result = helper.fee(state).token
	if result == "" and state.phase == TurnManager.Phase.PLAY and state.actor == state.turn:
		if state.actor == hero:
			var route = ["出牌", "基本牌", "酒", "出牌", "装备牌", "防具", "圣光白衣", "出牌", "基本牌", "杀", "杀", "@source", "是", "出牌", "锦囊牌", "普通锦囊", "决斗", "@source", "是", "@self", "种田", "@fee", "结束出牌"]
			if hero_step < route.size():
				var step = route[hero_step]
				if step == "@source": result = state.targets.get(str(opponent), "") if state.targeting else ""
				elif step == "@self": result = state.targets.get(str(hero), "") if not state.targeting else ""
				elif step == "@fee":
					var reply = helper.fee(state)
					result = reply.token
					if reply.done: hero_step += 1
				else: result = helper.find(state, step)
				if result != "" and step != "@fee": hero_step += 1
			else: result = helper.find(state, "结束出牌")
		elif state.actor == opponent and state.players[hero].get("good_fields", 0) > 0:
			var route = ["出牌", "锦囊牌", "普通锦囊", "决斗", "@hero", "是", "出牌", "锦囊牌", "普通锦囊", "顺手牵羊", "@hero", "是", "装备牌", "@armor", "结束出牌", "出牌", "锦囊牌", "普通锦囊", "决斗", "@hero", "是"]
			if source_step < route.size():
				var step = route[source_step]
				if step == "@hero": result = state.targets.get(str(hero), "") if state.targeting else ""
				elif step == "@armor": result = helper.find(state, Player.EQUIP_SLOT_NAMES["armor"])
				else: result = helper.find(state, step)
				if result != "": source_step += 1
		elif state.actor != opponent: result = helper.find(state, "结束出牌")
		elif source_step == 0: result = helper.find(state, "结束出牌")
	if result != "": last_signature = signature
	return result
