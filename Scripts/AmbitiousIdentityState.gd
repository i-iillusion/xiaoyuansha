# H03b: trusted opening plus explicit succession, not an opening-count check
# on transformed identities. UI/death-chain integration belongs to H03c.
class_name AmbitiousIdentityState
extends RefCounted

enum Declaration { UNRESOLVED, ACCEPTED, DECLINED }
var declaration: Declaration = Declaration.UNRESOLVED
var _players: Array[Player] = []
var _roles: Dictionary = {}
var _original_lord: Player
var _lord: Player
var _ambitious: Player

func initialize(players: Array[Player]) -> bool:
	if not _players.is_empty() or not GameModes.valid_opening(GameModes.AMBITIOUS,
		players.size(), players.map(func(p): return p.identity if is_instance_valid(p) else "")):
		return false
	var seen: Array[Player] = []
	for p in players:
		if not is_instance_valid(p) or seen.has(p) or not p.is_alive(): return false
		seen.append(p)
	_players.assign(players)
	for p in _players:
		_roles[p] = p.identity
		if p.identity == "主公": _original_lord = p
		if p.identity == "奸雄": _ambitious = p
	_lord = _original_lord
	return true

func valid() -> bool:
	if _players.is_empty(): return false
	for p in _players:
		if not is_instance_valid(p) or p.identity != _roles[p]: return false
	return true

func candidate() -> Player:
	if not valid() or declaration != Declaration.UNRESOLVED \
		or not _original_lord.is_dead() or _ambitious.is_dead(): return null
	return _ambitious

func declare() -> bool:
	var successor := candidate()
	if successor == null: return false
	# No yielding or hp/hand signals until all roles and public flags are committed.
	for p in _players:
		if p.is_dead() or p == successor: continue
		if p.identity == "忠臣": p.identity = "内奸"
		elif p.identity == "内奸": p.identity = "忠臣"
		_roles[p] = p.identity
	successor.identity = "主公"
	successor.identity_revealed = true
	successor.identity_max_hp_bonus += 1
	_roles[successor] = "主公"
	_lord = successor
	declaration = Declaration.ACCEPTED
	# H03-Q1: 2/4 -> 3/5. Normal healing is capped, not reset to full.
	successor.heal(1)
	return true

func decline() -> bool:
	if candidate() == null: return false
	declaration = Declaration.DECLINED
	return true

func evaluate() -> Dictionary:
	if not valid() or candidate() != null: return {}
	var survivors: Array[Player] = []
	var opponents := false
	for p in _players:
		if p.is_dying(): return {}
		if not p.is_dead():
			survivors.append(p)
			if p.identity in ["反贼", "内奸", "奸雄"]: opponents = true
	if survivors.is_empty(): return {} # No new simultaneous-annihilation ruling.
	if _lord.is_dead():
		if survivors.size() == 1 and survivors[0].identity == "内奸":
			return {"winner": "内奸", "reason": "主公阵亡，内奸为唯一存活角色"}
		return {"winner": "反贼", "reason": "%s 阵亡" % _lord.player_name}
	if not opponents:
		return {"winner": "主公", "reason": "反贼、内奸与未声明奸雄已全部阵亡"}
	return {}
