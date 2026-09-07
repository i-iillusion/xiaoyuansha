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

@export var player_count: int = 4
@export var debug_log: bool = true

var current_player_idx: int = 0
var current_phase: Phase = Phase.START
# 本回合已使用的【杀】次数（摸牌阶段重置；上限由武器决定，-1 = 无限制）
var strike_count_this_turn: int = 0
# 每回合卡牌使用次数限制（摸牌阶段重置，与杀次数一起）
var duel_count_this_turn: int = 0      # 决斗 ≤2
var aoe_count_this_turn: int = 0       # 南蛮入侵+万箭齐发 合计 ≤2
var steal_count_this_turn: int = 0     # 顺手牵羊+过河拆桥 合计 ≤2
var peach_garden_count_this_turn: int = 0  # 桃园结义 ≤1
var harvest_count_this_turn: int = 0   # 五谷丰登 ≤1
var disarm_count_this_turn: int = 0    # 卸甲归田 ≤1（回合开始重置）
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

# 【没用】麦克斯·欧尼斯特：回合开始阶段跳过自己的阶段，并指定其他角色立刻获得对应阶段（-1 = 无）
var granted_judge_target_idx: int = -1   # 跳过自己的判定阶段 → 目标立刻进行判定阶段（乐不思蜀/兵粮寸断失效）
var granted_draw_target_idx: int = -1    # 跳过自己的摸牌阶段 → 目标立刻获得一个摸牌阶段
var granted_play_target_idx: int = -1    # 跳过自己的出牌阶段 → 目标立刻获得一个出牌阶段

# ---- WAITING 状态上下文 ----
var waiting_responder_idx: int = -1
var waiting_response_type: String = ""  # 如 "dodge_for_strike", "strike_for_barbarian"

func start_game():
	current_player_idx = 0
	disarm_count_this_turn = 0
	_change_phase(Phase.START)

func _change_phase(new_phase: Phase):
	var old = current_phase
	current_phase = new_phase
	phase_changed.emit(old, new_phase, current_player_idx)
	if debug_log:
		print("[回合] P%d: %s → %s" % [current_player_idx, Phase.keys()[old], Phase.keys()[new_phase]])

# 推进到下一阶段（阶段内逻辑由 GameManager 处理）
func advance_phase():
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
			strike_count_this_turn = 0
			duel_count_this_turn = 0
			aoe_count_this_turn = 0
			steal_count_this_turn = 0
			peach_garden_count_this_turn = 0
			harvest_count_this_turn = 0
			if skip_play_phase and granted_play_target_idx < 0:
				# 乐不思蜀：跳过出牌阶段（但【没用】已授予他人出牌阶段时，出牌阶段仍进行并交给目标）
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
	current_player_idx = (current_player_idx + 1) % player_count
	disarm_count_this_turn = 0
	skip_play_phase = false
	skip_judge_phase = false
	skip_play_discard_phase = false
	supply_shortage_active = false
	skip_full_turn = false
	granted_judge_target_idx = -1
	granted_draw_target_idx = -1
	granted_play_target_idx = -1
	_change_phase(Phase.START)

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
	return true

# 记录一次使用（摸牌阶段重置）
func use_card(card_key: String):
	match card_key:
		"duel": duel_count_this_turn += 1
		"aoe": aoe_count_this_turn += 1
		"steal": steal_count_this_turn += 1
		"peach_garden": peach_garden_count_this_turn += 1
		"harvest": harvest_count_this_turn += 1
		"disarm": disarm_count_this_turn += 1

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
