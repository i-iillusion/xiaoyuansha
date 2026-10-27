extends RefCounted

# Only public, viewer-filtered packets/history. No authority state mutation.
var draw_seen := false
var judge_seen := false
var judgment_seeded := false
var play_seen := false
var gifted_play_seen := false
var nested_seen := false
var restored_seen := false
var egg_seen := false
var own_response_seen := false
var own_restored_seen := false
var max_seat := -1
var controller_seat := -1
var viewer_seat := -1
var final_events: Array = []

func observe(state: Dictionary, events: Array):
	viewer_seat = state.actor
	judge_seen = judge_seen or events.any(func(e): return "选定赠送判定阶段给火龙" in e.text)
	judgment_seeded = judgment_seeded or state.units.any(func(row): return row.judgments.has(CardData.CardSubType.INDULGENCE))
	draw_seen = draw_seen or events.any(func(e): return "选定赠送摸牌阶段给火龙" in e.text)
	play_seen = play_seen or events.any(func(e): return "选定赠送出牌阶段给火龙" in e.text)
	var id: String = state.get("acting_unit", "")
	if id.is_empty() or state.phase != TurnManager.Phase.PLAY: return
	var units: Array = state.units.filter(func(row): return row.id == id)
	if units.is_empty(): return
	var unit = units[0]
	if state.players[state.turn].general != "麦克斯·欧尼斯特": return
	max_seat = state.turn
	controller_seat = unit.controller
	gifted_play_seen = true
	egg_seen = egg_seen or state.players[unit.controller].eggs == 1
	# Every observer can verify public input ownership. Only the addressed peer
	# receives private response buttons; never expect another peer's controls.
	if state.owner == state.turn:
		nested_seen = true
		own_response_seen = own_response_seen or state.controls.any(func(c): return "不出" in c.text or "不响应" in c.text)
	if nested_seen and state.owner == unit.controller:
		restored_seen = true
		own_restored_seen = own_restored_seen or state.controls.any(func(c): return c.text == "结束出牌" and not c.disabled)

func choose(state: Dictionary, events: Array) -> String:
	var controls: Array = state.controls
	var units: Array = state.units.filter(func(row): return row.kind == UnitRegistry.Kind.FIRE_DRAGON)
	var maxes: Array = state.players.filter(func(row): return row.general == "麦克斯·欧尼斯特")
	if maxes.is_empty(): return ""
	var max_target: int = maxes[0].seat
	if state.labels.any(func(label): return "是否发动【烂忠厚】" in label):
		var revealed = not units.is_empty() and events.any(func(e): return e.kind == "use" and e.details.get("actor_unit", "") == units[0].id)
		return button(controls, "确认" if revealed and (judge_seen or judgment_seeded) and not play_seen else "取消")
	if state.labels.any(func(label): return "先点击其他角色头像" in label) and not units.is_empty():
		var phase = button(controls, "判定" if not judge_seen else ("出牌" if draw_seen else "摸牌"))
		return phase if not phase.is_empty() else state.targets.get(units[0].id, "")
	if play_seen: return "" # Resume the ordinary victory driver after acceptance.
	if not units.is_empty() and not judgment_seeded and state.actor == (units[0].controller + 1) % state.count and not events.filter(func(e): return e.kind == "use" and e.details.get("actor_unit", "") == units[0].id).is_empty():
		if state.targeting and "乐不思蜀" in state.notice:
			var confirm = button(controls, "确认")
			return confirm if not confirm.is_empty() else state.targets.get(units[0].id, "")
		for text in ["乐不思蜀", "延时锦囊", "锦囊牌", "出牌"]:
			var token = button(controls, text)
			if not token.is_empty(): return token
	var id: String = state.get("acting_unit", "")
	if not id.is_empty() and state.owner == state.actor and not units.is_empty():
		var uses = events.filter(func(e): return e.kind == "use" and e.details.get("actor_unit", "") == id)
		var gifted = state.players[state.turn].general == "麦克斯·欧尼斯特"
		# The first normal turn reveals Max; the second banks its cards.
		# Gifted PLAY then uses one of those actual original arbitrary cards.
		if (not gifted and not uses.is_empty()) or (gifted and uses.size() >= 2):
			var end = button(controls, "结束出牌")
			if not end.is_empty(): return end
		if uses.is_empty():
			for text in ["南蛮入侵", "普通锦囊", "锦囊牌", "出牌"]:
				var token = button(controls, text)
				if not token.is_empty(): return token
		# This branch opens only Strike. Do not route its target from the last
		# transient notice, which can still describe a preceding response.
		if state.targeting:
			var confirm = button(controls, "确认")
			return confirm if not confirm.is_empty() else state.targets.get(str(max_target), "")
		for text in ["普通杀", "杀", "基本牌", "出牌"]:
			var token = button(controls, text)
			if not token.is_empty(): return token
	# All fixed players wait legally while the unit/gift timeline develops.
	return button(controls, "结束出牌")

func button(controls: Array, text: String) -> String:
	var matches = controls.filter(func(c): return c.text == text and not c.disabled)
	return "" if matches.is_empty() else matches[0].id

func verify(t):
	t.check(judgment_seeded and judge_seen and draw_seen and play_seen, "ENet actual Max gifts unit JUDGE, DRAW then PLAY through public target/phase controls")
	t.check(gifted_play_seen and egg_seen, "ENet gifted unit PLAY retains source Max turn and actual second-turn egg")
	t.check(nested_seen and restored_seen, "ENet gifted unit strike delegates response to Max then restores unit controller")
	if viewer_seat == max_seat: t.check(own_response_seen, "ENet Max peer receives actual private gifted-unit response controls")
	if viewer_seat == controller_seat: t.check(own_restored_seen, "ENet controller peer regains actual unit END control after response")
	var gifts = final_events.filter(func(e): return "选定赠送" in e.text and "阶段给火龙" in e.text)
	t.check(gifts.size() == 3, "ENet gifted stages complete exactly once without extra gift loop")
