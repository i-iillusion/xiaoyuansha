# Strategy only. All inputs are already-authorized value snapshots; no Nodes,
# secret identities, card names or new legality restrictions are inspected here.
class_name SimbaPolicy
extends RefCounted

static func body(view: Dictionary, key: Variant) -> Dictionary:
	for row in view.get("players", []):
		if typeof(key) == TYPE_INT and row.seat == key: return row
	for row in view.get("units", []):
		if typeof(key) == TYPE_STRING and row.id == key: return row
	return {}

static func allied(view: Dictionary, key: Variant) -> bool:
	if typeof(key) == typeof(view.actor) and key == view.actor: return true
	var other = body(view, key)
	if other.is_empty(): return false
	if typeof(key) == TYPE_STRING:
		if other.get("controller", -1) == view.actor: return true
		other = body(view, other.get("controller", -1))
	var own = body(view, view.actor)
	if own.is_empty() or other.is_empty() or view.get("mode", "") == GameModes.FREE_FOR_ALL: return false
	var a = own.get("identity", "")
	var b = other.get("identity", "")
	return (a in ["主公", "忠臣"] and b in ["主公", "忠臣"]) or (a == "反贼" and b == "反贼")

static func choose(view: Dictionary, kind: String, options: Array) -> int:
	if options.is_empty(): return -1
	var own = body(view, view.actor)
	if own.is_empty(): return -1
	if kind == "simba_emergency":
		var key = view.response.get("target", -1)
		if typeof(key) == typeof(view.actor) and key == view.actor: return options[0]
		var target = body(view, key)
		return options[0] if own.hp > 1 and allied(view, key) and not target.is_empty() and target.hp < target.max_hp else -1
	if kind not in ["simba_give", "simba_reclaim"]: return -1
	if kind == "simba_give" and own.hp <= 1: return -1
	var keys: Array = view.response.get("targets", [])
	var best := -1
	var score := -2147483648
	for index in options:
		if typeof(index) != TYPE_INT or index < 0 or index >= keys.size(): continue
		var key = keys[index]
		if typeof(key) == typeof(view.actor) and key == view.actor: continue
		var row = body(view, key)
		if row.is_empty(): continue
		var value: int
		if kind == "simba_give":
			if not allied(view, key) or row.hp >= row.max_hp: continue
			value = row.max_hp - row.hp
		else:
			if row.get("good_deed_marks", 0) <= 0: continue
			value = int(row.good_deed_marks) + (0 if allied(view, key) else 1000)
		if value > score:
			score = value
			best = index
	return best
