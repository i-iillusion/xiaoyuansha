# ============================================================
# EffectChain.gd — 三阶段效果处理链
# 响应阶段 → 效果阶段 → 结算阶段
#
# 设计核心：
#   三个阶段通过 await 异步流过，每个阶段有触发点供
#   GameManager 注入技能检查/响应询问。
#   杀→闪流程整个走完 ≈ 70 行逻辑。
# ============================================================
class_name EffectChain
extends RefCounted

# === 链的阶段 ===
enum Phase {
	RESPONSE,   # ① 响应阶段：技能触发 + 目标出闪/响应
	EFFECT,     # ② 效果阶段：即将发生的效果修正
	RESOLUTION, # ③ 结算阶段：效果发生后触发
	DONE        # 完成
}

# === 效果类型 ===
enum EffectType {
	DAMAGE,  # 造成伤害
	HEAL,    # 回复体力
}

# === 伤害属性（铁索连环只传导属性伤害）===
enum DamageType {
	PHYSICAL,  # 无属性
	FIRE,      # 火
	THUNDER,   # 雷
}

# === 响应结果 ===
enum ResponseResult {
	NONE,      # 未响应 / 正常通过
	DODGED,    # 被闪避
	COUNTERED, # 被无懈/技能抵消
	CANCELED,  # 被主动取消
}

# ---- 链数据 ----

var source_player: Player
var target_player: Player
var source_card: CardBase
var effect_type: EffectType
var effect_value: int = 0
var damage_element: DamageType = DamageType.PHYSICAL

var current_phase: Phase = Phase.RESPONSE
var is_cancelled: bool = false
var response_result: ResponseResult = ResponseResult.NONE
# true → 跳过目标响应阶段（【贯石斧】强制命中用：杀被闪抵消后重新结算伤害）
var skip_response: bool = false

# ---- 异步回调（由 GameManager 注入） ----

# 当响铃阶段需要询问目标是否出闪/响应时调用
# 签名：func(chain, responder, expected_card_sub_type, attacker) -> bool
var response_callback: Callable

# 当各阶段有触发点时调用（技能钩子）
# 签名：func(chain, event_name, subject, source, data) -> bool
# 返回 true → 该事件已处理/打断了流程
var trigger_callback: Callable

func _init(source: Player, target: Player, card: CardBase, etype: EffectType, value: int = 0):
	source_player = source
	target_player = target
	source_card = card
	effect_type = etype
	effect_value = value

# 启动链条，可 await 获取结果
func start() -> ResponseResult:
	await _phase_response()
	if is_cancelled:
		_finish()
		return response_result

	await _phase_effect()
	if is_cancelled:
		_finish()
		return response_result

	await _phase_resolution()
	_finish()
	return response_result

func _finish():
	current_phase = Phase.DONE

# ============================
#  ① 响应阶段
# ============================
func _phase_response():
	current_phase = Phase.RESPONSE

	# 1. 发起者"出牌时"技能触发（如：吕布无双要求两张闪）
	if trigger_callback.is_valid():
		var handled = await trigger_callback.call(self, "on_play_card", source_player, null, {})
		if handled:
			is_cancelled = true
			response_result = ResponseResult.CANCELED
			return

	# 2. 对其他玩家触发（锦囊牌 → 无懈可击）
	# （待扩展）

	# 3. 目标侧"成为目标时"技能触发
	if trigger_callback.is_valid() and target_player:
		var handled = await trigger_callback.call(self, "on_being_targeted", target_player, source_player, {})
		if handled:
			is_cancelled = true
			response_result = ResponseResult.COUNTERED
			return

	# 4. 目标响应（杀→闪）——skip_response 时跳过（贯石斧强制命中）
	if not skip_response and effect_type == EffectType.DAMAGE and target_player and response_callback.is_valid():
		var dodged = await response_callback.call(self, target_player, CardData.CardSubType.DODGE, source_player)
		if dodged:
			is_cancelled = true
			response_result = ResponseResult.DODGED
			return

# ============================
#  ② 效果阶段
# ============================
func _phase_effect():
	current_phase = Phase.EFFECT
	var data = { "value": effect_value }

	# 1. "将要造成伤害" — 发起者侧
	if trigger_callback.is_valid():
		await trigger_callback.call(self, "before_deal_damage", source_player, null, data)
	effect_value = data.get("value", effect_value)
	if effect_value <= 0:
		is_cancelled = true
		return

	# 2. "将要受到伤害" — 目标侧
	if trigger_callback.is_valid() and target_player:
		var cancel = await trigger_callback.call(self, "before_take_damage", target_player, source_player, data)
		effect_value = data.get("value", effect_value)
		if cancel or effect_value <= 0:
			is_cancelled = true
			return

	# 3. 执行实际效果
	_apply_effect()

func _apply_effect():
	match effect_type:
		EffectType.DAMAGE:
			target_player.take_damage(effect_value)
			# 伤害已施加：通知 GameManager 立即同步 UI（血条/数字实时变化，不等后续延迟弹窗）
			if trigger_callback.is_valid():
				await trigger_callback.call(self, "damage_applied", target_player, source_player, { "damage": effect_value })
		EffectType.HEAL:
			target_player.heal(effect_value)

# ============================
#  ③ 结算阶段
# ============================
func _phase_resolution():
	current_phase = Phase.RESOLUTION

	if not trigger_callback.is_valid():
		return

	# 1. "造成伤害后" — 发起者
	if effect_type == EffectType.DAMAGE:
		await trigger_callback.call(self, "after_deal_damage", source_player, null, { "damage": effect_value })

	# 2. "受到伤害后" — 目标
	if effect_type == EffectType.DAMAGE and target_player:
		await trigger_callback.call(self, "after_take_damage", target_player, source_player, { "damage": effect_value })
