extends RefCounted

# Test-only UI driver. It sees exactly the same filtered state as a remote player.
var played_revision := -1
var played_count := 0
var target_cursor := 0
var wine_revision := -1
var strike_revision := -1

func choose(state: Dictionary) -> String:
	if state.is_empty() or state.get("ended", false): return ""
	var controls: Array = state.get("controls", [])
	if state.get("labels", []).any(func(label): return "【偷药品】" in label):
		var choices = controls.filter(func(control): return control.text.begins_with("获得：") and not control.disabled)
		var pairs = choices.filter(func(control): return " / " in control.text)
		if not pairs.is_empty(): return pairs[0].id
		if not choices.is_empty(): return choices[0].id
		for control in controls:
			if control.text == "不发动（正常摸牌）": return control.id
	if state.get("targeting", false):
		var confirmation = controls.any(func(x): return "确认" in x.text or "确定" in x.text or x.text == "是")
		if not confirmation:
			var candidates = state.players.filter(func(player): return player.seat != state.actor and not player.dead)
			if not candidates.is_empty():
				# The unarmed-strawman harness plays range-limited duels. Concentrate
				# on a public living target within the manual's distance 2, never retry a distant low-HP
				# target. Other targeting retains rotation; no authority-only reads.
				var dueling = "决斗" in state.get("notice", "")
				var striking = "【杀】" in state.get("notice", "")
				if dueling or striking:
					var alive: Array = []
					for seat in state.get("space", range(state.players.size())):
						if not state.players[seat].dead: alive.append(state.players[seat])
					var actor_index = alive.find(state.players.filter(func(player): return player.seat == state.actor)[0])
					candidates = candidates.filter(func(player):
						var diff = absi(alive.find(player) - actor_index)
						return mini(diff, alive.size() - diff) <= (2 if dueling else 1))
					candidates.sort_custom(func(a, b): return a.hp < b.hp)
					# Identity fixtures end via the already-public lord when in range;
					# hidden roles are never inferred and opening roles remain random.
					if state.get("mode", "") in [GameModes.CLASSIC, GameModes.AMBITIOUS]:
						var public_lords = candidates.filter(func(player): return player.get("identity", "") == "主公")
						if not public_lords.is_empty(): candidates = public_lords
				var player = candidates[0 if dueling or striking else target_cursor % candidates.size()]
				target_cursor += 1
				return state.targets.get(str(player.seat), "")
	# Use one ordinary wine/strike through the real selector before the two
	# duels. Damage, payment, range and responses still come from production UI.
	for action in controls:
		if action.disabled: continue
		if action.text == "基本牌" and (wine_revision != int(state.revision) or strike_revision != int(state.revision)): return action.id
		if action.text == "酒" and wine_revision != int(state.revision):
			wine_revision = int(state.revision)
			return action.id
		if action.text == "杀" and wine_revision == int(state.revision) and strike_revision != int(state.revision):
			if "选择杀的属性" in state.get("labels", []): strike_revision = int(state.revision)
			return action.id
	if played_revision == int(state.revision) and played_count >= 2:
		for action in controls:
			if action.text == "结束出牌" and not action.disabled: return action.id
	# Decline responses/rescue; pay normal declarations through the actual widgets.
	for text in ["声明成为主公", "不响应", "不出", "放弃", "不救", "不使用", "自动选牌", "石头", "确认", "确定", "是", "锦囊牌", "普通锦囊", "决斗", "出牌"]:
		for action in controls:
			if text in action.text and not action.disabled:
				if action.text == "决斗":
					if played_revision != int(state.revision): played_count = 0
					played_revision = int(state.revision)
					played_count += 1
				return action.id
	for action in controls:
		if "结束" in action.text and not action.disabled: return action.id
	return ""
