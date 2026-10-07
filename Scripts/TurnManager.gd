# ============================================================
# TurnManager.gd — 回合状态机
# START → DRAW → PLAY → DISCARD → END → 下一位玩家
# ============================================================
class_name TurnManager
extends Node

enum Phase {
	START,       # 回合开始
	JUDGE,       # 判定阶段（延时锦囊）
	DRAW,        # 摸牌阶段
	PLAY,        # 出牌阶段
	DISCARD,     # 弃牌阶段
	END,         # 回合结束
	WAITING      # 等待响应链（杀→闪等）
}

signal phase_changed(old_phase: Phase, new_phase: Phase, player_idx: int)
signal turn_ended(player_idx: int)
signal standalone_play_finished(frame: Dictionary)

@export var player_count: int = 4
@export var debug_log: bool = true

# 交互上下文代次：字段离开又回到同值也不能重新授权旧答复。
# 不是规则中的轮数/回合次数，不参与技能次数刷新。
var _context_revision: int = 0
# 规则回合/阶段标识与交互代次分开；WAITING暂停不创建新规则阶段。
var turn_id: int = 0
var phase_id: int = 0
var _turn_card_counts: Dictionary = {}
# 技能名 -> 座位 -> 最近使用/禁用的阶段ID；固定键不随回合数增长。
var _phase_skill_uses: Dictionary = {}
var current_player_idx: int = 0:
	set(value):
		if value != current_player_idx:
			_context_revision += 1
		current_player_idx = value
var current_phase: Phase = Phase.START:
	set(value):
		if value != current_phase:
			_context_revision += 1
		current_phase = value
		if value not in [Phase.PLAY, Phase.WAITING]:
			play_actor_idx = -1
# 单独出牌阶段的操作者，不改变当前回合角色或发放额外回合。
var play_actor_idx: int = -1:
	set(value):
		if value != play_actor_idx:
			_context_revision += 1
		play_actor_idx = value
# 本回合已使用的【杀】次数（回合开始重置；上限由武器决定，-1 = 无限制）
var strike_count_this_turn: int:
	get: return _get_turn_count("strike")
	set(value): _set_turn_count("strike", value)
# 主动使用酒的历史，不是下一张杀的加伤层数；濒死自救不占此额度。
var wine_count_this_turn: int:
	get: return _get_turn_count("wine")
	set(value): _set_turn_count("wine", value)
# 每个座位本回合是否已经使用/打出过杀；与主动杀使用次数分开。
# 属于回合历史，不是武将牌状态，阶段切换/装备变动不清空。
var _strike_actors_this_turn: Dictionary = {}
# 每回合卡牌使用次数限制（按实际操作者登记，回合开始统一重置）
var duel_count_this_turn: int:
	get: return _get_turn_count("duel")
	set(value): _set_turn_count("duel", value)
var aoe_count_this_turn: int:
	get: return _get_turn_count("aoe")
	set(value): _set_turn_count("aoe", value)
var steal_count_this_turn: int:
	get: return _get_turn_count("steal")
	set(value): _set_turn_count("steal", value)
var peach_garden_count_this_turn: int:
	get: return _get_turn_count("peach_garden")
	set(value): _set_turn_count("peach_garden", value)
var harvest_count_this_turn: int:
	get: return _get_turn_count("harvest")
	set(value): _set_turn_count("harvest", value)
var disarm_count_this_turn: int:
	get: return _get_turn_count("disarm")
	set(value): _set_turn_count("disarm", value)
# CARD-04最新Q16：限制的是借刀牌本身，按实际使用者每回合两次。
var borrowed_sword_count_this_turn: int:
	get: return _get_turn_count("borrowed_sword")
	set(value): _set_turn_count("borrowed_sword", value)
# 酒状态已改为按玩家存（Player.wine_stacks）：狂暴战斧可叠加且跨回合保留，普通玩家每回合最多 1 层

# 判定效果标志
# 乐不思蜀生效：本回合跳过出牌阶段
var skip_play_phase: bool = false
# 【神速】（比尔·盖伊）选项1：跳过判定阶段（判定牌保留不结算）
var skip_judge_phase: bool = false
# 【神速】（比尔·盖伊）选项2：跳过出牌和弃牌阶段（出牌阶段后直接进回合结束）
var skip_play_discard_phase: bool = false
# 兵粮寸断生效：本回合摸牌阶段少摸一张
var supply_shortage_active: bool = false
# 武将牌反面：本回合被整回合跳过（摄魂刀翻面）
var skip_full_turn: bool = false

# 【烂忠厚】麦克斯·欧尼斯特：回合开始阶段跳过自己的阶段，并指定其他角色立刻获得对应阶段（-1 = 无）
var granted_judge_target_idx: int = -1   # 跳过自己的判定阶段 → 目标立刻进行判定阶段（乐不思蜀/兵粮寸断失效）
var granted_draw_target_idx: int = -1    # 跳过自己的摸牌阶段 → 目标立刻获得一个摸牌阶段
var granted_judge_completed: bool = false
var granted_draw_completed: bool = false
var granted_play_target_idx: int = -1    # 跳过自己的出牌阶段 → 目标立刻获得一个出牌阶段
var granted_play_completed: bool = false
var _standalone_play_frame: Dictionary = {}

# 烂忠厚在START插入单独出牌阶段；不发回合开始/弃牌/结束事件。
func begin_standalone_play(actor: int) -> Dictionary:
	return begin_standalone_phase(actor, Phase.PLAY)

func begin_standalone_phase(actor: int, phase: Phase) -> Dictionary:
	if current_phase != Phase.START or not _standalone_play_frame.is_empty() or actor < 0 or actor >= player_count or actor == current_player_idx: return {}
	if phase not in [Phase.JUDGE, Phase.DRAW, Phase.PLAY]: return {}
	var frame = {"source": current_player_idx, "turn": turn_id, "actor": actor, "phase": phase, "completed": false}
	_standalone_play_frame = frame
	current_phase = phase
	phase_id += 1
	if phase == Phase.PLAY: play_actor_idx = actor
	frame.revision = _context_revision
	return frame

func complete_standalone_phase(frame: Dictionary) -> bool:
	if not is_same(_standalone_play_frame, frame) or current_phase != frame.phase \
		or current_player_idx != frame.source or turn_id != frame.turn or _context_revision != frame.revision:
		return false
	if frame.phase == Phase.PLAY and play_actor_idx != frame.actor: return false
	var allowed: Callable = frame.get("allowed", Callable())
	if allowed.is_valid() and not allowed.call(): return false
	frame["allowed"] = Callable()
	_standalone_play_frame = {}
	current_phase = Phase.START
	frame.completed = true
	standalone_play_finished.emit(frame)
	return true

func cancel_standalone_play(frame: Dictionary):
	if is_same(_standalone_play_frame, frame):
		frame["allowed"] = Callable()
		_standalone_play_frame = {}
		_context_revision += 1

# ---- WAITING 状态上下文 ----
var waiting_responder_idx: int = -1
var waiting_response_type: String = ""  # 如 "dodge_for_strike", "strike_for_barbarian"

func get_context_revision() -> int:
	return _context_revision

func get_play_actor_idx() -> int:
	return play_actor_idx if play_actor_idx >= 0 and current_phase in [Phase.PLAY, Phase.WAITING] else current_player_idx

func start_game():
	_context_revision += 1
	current_player_idx = 0
	_begin_turn()
	_change_phase(Phase.START)

func _change_phase(new_phase: Phase):
	var old = current_phase
	if old == new_phase:
		_context_revision += 1 # 显式进入同名阶段仍是新上下文。
	if new_phase != Phase.WAITING and not (old == Phase.WAITING and new_phase == Phase.PLAY):
		phase_id += 1
	current_phase = new_phase
	phase_changed.emit(old, new_phase, current_player_idx)
	if debug_log:
		print("[回合] P%d: %s → %s" % [current_player_idx, Phase.keys()[old], Phase.keys()[new_phase]])

# 推进到下一阶段（阶段内逻辑由 GameManager 处理）
func advance_phase():
	if not _standalone_play_frame.is_empty():
		# 判定/摸牌由效果入口明确完成；不能把一次旧advance当作完成。
		if current_phase == Phase.PLAY: complete_standalone_phase(_standalone_play_frame)
		return
	match current_phase:
		Phase.START:
			if skip_full_turn:
				# 武将牌翻回正面后跳过整个回合（不摸牌/不出牌/不弃牌）
				skip_full_turn = false
				_change_phase(Phase.END)
			else:
				_change_phase(Phase.JUDGE)
		Phase.JUDGE:   _change_phase(Phase.DRAW)
		Phase.DRAW:
			if skip_play_phase and granted_play_target_idx < 0:
				# 乐不思蜀：跳过出牌阶段（但【烂忠厚】已授予他人出牌阶段时，出牌阶段仍进行并交给目标）
				skip_play_phase = false
				_change_phase(Phase.DISCARD)
			else:
				_change_phase(Phase.PLAY)
		Phase.PLAY:
			if skip_play_discard_phase:
				# 【神速】选项2：跳过出牌与弃牌阶段，直接回合结束
				skip_play_discard_phase = false
				_change_phase(Phase.END)
			else:
				_change_phase(Phase.DISCARD)
		Phase.DISCARD: _change_phase(Phase.END)
		Phase.END:     turn_ended.emit(current_player_idx)

func next_turn():
	_context_revision += 1
	current_player_idx = (current_player_idx + 1) % player_count
	_begin_turn()
	_change_phase(Phase.START)

func _begin_turn():
	turn_id += 1
	_reset_turn_counts()
	skip_play_phase = false
	skip_judge_phase = false
	skip_play_discard_phase = false
	supply_shortage_active = false
	skip_full_turn = false
	granted_judge_target_idx = -1
	granted_draw_target_idx = -1
	granted_judge_completed = false
	granted_draw_completed = false
	granted_play_target_idx = -1
	granted_play_completed = false
	_standalone_play_frame = {}
	waiting_responder_idx = -1
	waiting_response_type = ""

# 测试可清理回合历史；不刷新回合/阶段ID或调度状态。
func _reset_turn_counts():
	_turn_card_counts.clear()
	_strike_actors_this_turn.clear()

func _get_turn_count(key: String, seat: int = -1) -> int:
	if seat < 0:
		seat = get_play_actor_idx()
	return int(_turn_card_counts.get(seat, {}).get(key, 0))

func _set_turn_count(key: String, value: int):
	var seat = get_play_actor_idx()
	if not _turn_card_counts.has(seat):
		_turn_card_counts[seat] = {}
	_turn_card_counts[seat][key] = value

func phase_skill_used(key: String, seat: int = -1) -> bool:
	if seat < 0:
		seat = get_play_actor_idx()
	return _phase_skill_uses.get(key, {}).get(seat, -1) == phase_id

func set_phase_skill_used(key: String, used: bool, seat: int = -1):
	if seat < 0:
		seat = get_play_actor_idx()
	if not _phase_skill_uses.has(key):
		_phase_skill_uses[key] = {}
	if used:
		_phase_skill_uses[key][seat] = phase_id
	else:
		_phase_skill_uses[key].erase(seat)

# ---- 出牌约束 ----

# 是否还能出【杀】。limit = 每回合杀次数上限（由武器决定：无武器 1，连弩 2，诸葛连弩 -1 无限制）
func can_play_strike(limit: int = 1) -> bool:
	if current_phase != Phase.PLAY:
		return false
	if limit < 0:
		return true
	return strike_count_this_turn < limit

func use_strike():
	strike_count_this_turn += 1

func can_play_wine(unlimited: bool = false, seat: int = -1) -> bool:
	return current_phase == Phase.PLAY and (unlimited or _get_turn_count("wine", seat) < 1)

# 成功使用/打出后调用；返回是否为此角色在当前回合的第一次。
func record_strike_played(seat: int) -> bool:
	var first := not _strike_actors_this_turn.has(seat)
	_strike_actors_this_turn[seat] = true
	return first

func strikes_used() -> int:
	return strike_count_this_turn

# ---- 每回合卡牌使用次数（决斗/南蛮万箭/顺手拆桥/桃园/五谷）----

# 查询是否还能使用（key: duel / aoe / steal / peach_garden / harvest）
# limit 可选：指定上限（默认 -1 = 用内置上限；【霸王】杰基·斯特朗的决斗上限为 3）
func can_use(card_key: String, limit: int = -1) -> bool:
	match card_key:
		"duel": return duel_count_this_turn < (2 if limit < 0 else limit)
		"aoe": return aoe_count_this_turn < 2
		"steal": return steal_count_this_turn < 2
		"peach_garden": return peach_garden_count_this_turn < 1
		"harvest": return harvest_count_this_turn < 1
		"disarm": return disarm_count_this_turn < 1
		"borrowed_sword": return borrowed_sword_count_this_turn < 2
		"indulgence": return _get_turn_count(card_key) < 2
	return true

# 记录当前出牌操作者的一次使用（回合开始重置）
func use_card(card_key: String):
	match card_key:
		"wine": wine_count_this_turn += 1
		"duel": duel_count_this_turn += 1
		"aoe": aoe_count_this_turn += 1
		"steal": steal_count_this_turn += 1
		"peach_garden": peach_garden_count_this_turn += 1
		"harvest": harvest_count_this_turn += 1
		"disarm": disarm_count_this_turn += 1
		"borrowed_sword": borrowed_sword_count_this_turn += 1
		"indulgence": _set_turn_count(card_key, _get_turn_count(card_key) + 1)

# ---- 响应链 ----

func start_waiting(response_type: String, responder_idx: int):
	waiting_responder_idx = responder_idx
	waiting_response_type = response_type
	_change_phase(Phase.WAITING)

func end_waiting():
	waiting_responder_idx = -1
	waiting_response_type = ""
	_change_phase(Phase.PLAY)

func is_waiting() -> bool:
	return current_phase == Phase.WAITING

func can_play_card() -> bool:
	return current_phase == Phase.PLAY
