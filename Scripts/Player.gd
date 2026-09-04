# ============================================================
# Player.gd — 玩家数据模型
# 管理体力、手牌、装备、攻击距离等状态
# ============================================================
class_name Player
extends Node

signal hp_changed(new_hp: int)
signal hand_updated()

@export var player_name: String = "玩家"
@export var max_hp: int = 4
@export var identity: String = "主公"   # 主公 / 忠臣 / 反贼 / 内奸
# 身份是否已公开：主公开局公开；其余角色阵亡（翻开身份）后公开
var identity_revealed: bool = false

# 武将（以同学为原型）：默认稻草人（5 血无技能）
var general_name: String = "稻草人"

# 性别（雌雄双股剑判定用）："male" / "female"
var gender: String = "male"

var hp: int : set = _set_hp
var hand: Array[CardBase] = []
var equipment: Dictionary = {}

# 铁索连环状态：受到属性伤害后传导
var chained: bool = false

# 已确定的牌（顺手牵羊获得的装备/判定牌存放区）
var determined_cards: Array[CardBase] = []
# 判定牌区（判定系统开发中，暂为空）
var judgment_cards: Array[CardBase] = []

# 装备槽位（顺序即显示顺序）：武器/护甲占位 + 4 个坐骑槽位
# 坐骑规则：每名玩家可装备 4 匹马，+1 马（防御）与 -1 马（进攻）自由搭配
const EQUIP_SLOTS: Array[String] = ["weapon", "armor", "mount_1", "mount_2", "mount_3", "mount_4"]
const MOUNT_SLOTS: Array[String] = ["mount_1", "mount_2", "mount_3", "mount_4"]
const EQUIP_SLOT_NAMES = {
	"weapon": "武器",
	"armor": "护甲",
	"mount_1": "坐骑1",
	"mount_2": "坐骑2",
	"mount_3": "坐骑3",
	"mount_4": "坐骑4",
}
const EQUIP_SLOT_SUB_TYPES = {
	"weapon": CardData.CardSubType.WEAPON,
	"armor": CardData.CardSubType.ARMOR,
}

# 座位索引（圆形排列）
var seat_index: int = 0

# 【破风枪】手牌上限加成：每造成一点伤害 +1，失去该武器后清零
# 手牌上限 = 体力值 + 该加成
var hand_limit_bonus: int = 0

# 【治疗权杖】本回合是否已使用过桃（每回合第一张桃额外+1；回合开始时重置）
var heal_staff_peach_used: bool = false

# 【酒】层数（狂暴战斧可叠加且跨回合保留；普通玩家每回合最多 1 层，回合开始清零）
var wine_stacks: int = 0

# 武将牌状态：反面 = 下个自己的回合开始前翻回正面并跳过该回合（摄魂刀）
var facedown: bool = false

# 【摄魂刀】激活状态：对同一名玩家连续且累计造成 3 点伤害后激活（装备时重置跟踪）
var soul_blade_activated: bool = false
var soul_blade_track_target: Player = null
var soul_blade_track_count: int = 0

# 【下跪】状态（布鲁斯·萨维奇限定技）：kneeling = 当前是否下跪；kneel_used = 限定技是否已使用（永久）
var kneeling: bool = false
var kneel_used: bool = false

# 【贤者的加护】：贤者标记计数（3 个标记激活装备）；sage_activated = 激活后的保命能力
var sage_tokens: int = 0
var sage_activated: bool = false

# 【神速】（比尔·盖伊）：选项2 的摸牌减益欠账层数（每选一次 +1，非发动回合的摸牌阶段一次扣清归零）
var shensu_penalty: int = 0
# 【神速】本回合是否已选择选项2（选2 的当回合摸牌阶段不扣减益，顺延到下个未发动的回合）
var shensu_used_this_turn: bool = false

# 【苕】安普提·斯丢皮得：暗置装备
# 暗置后装备区对应槽位 = HIDDEN_EQUIPMENT 占位；hidden_equip_slot 记录暗置所在槽位（"" = 无暗置）
var hidden_equip_slot: String = ""

# 【觉醒】（史蒂芬·彼特先斯）：觉醒技已发动 / 觉醒三选一（1=不能成为【杀】的目标，2=不能成为【决斗】的目标，3=不能成为【南蛮入侵】和【万箭齐发】的目标）
var awoken: bool = false
var awake_choice: int = 0

# 是否有暗置装备
func has_hidden_equip() -> bool:
	return hidden_equip_slot != ""

# 暗置装备的类型："weapon" / "armor" / "mount"（无暗置返回 ""）
func get_hidden_equip_type() -> String:
	if hidden_equip_slot == "weapon":
		return "weapon"
	if hidden_equip_slot == "armor":
		return "armor"
	if MOUNT_SLOTS.has(hidden_equip_slot):
		return "mount"
	return ""

# 第一个空坐骑槽位（无空槽返回 ""）
func get_free_mount_slot() -> String:
	for slot in MOUNT_SLOTS:
		if not equipment.has(slot):
			return slot
	return ""

# 武器无攻击距离加成：攻击范围恒为 1，距离只由坐骑决定
var attack_range: int = 1
# -1 马（进攻马）数量：攻击别人时距离 -N
var mount_minus: int = 0
# +1 马（防御马）数量：被别人攻击时距离 +N
var mount_plus: int = 0

# 总玩家数（用于距离计算）
var _total_players: int = 5

func _ready():
	hp = max_hp

func _set_hp(value: int):
	hp = clampi(value, 0, max_hp)
	hp_changed.emit(hp)

func take_damage(amount: int = 1):
	hp -= amount

func heal(amount: int = 1):
	hp += amount

func is_alive() -> bool:
	return hp > 0

# 当前手牌上限（弃牌阶段用）：体力 + 破风枪加成 + 圣光白衣加成
func hand_limit() -> int:
	var bonus = hand_limit_bonus
	# 【圣光白衣】：你的手牌上限+2（锁定被动，装备即生效，失去/替换自动恢复）
	if get_armor() == CardData.CardSubType.SHENGGUANG_BAIYI:
		bonus += 2
	# 【下跪】状态（布鲁斯·萨维奇）：固定手牌上限 5（【无谋】失效）
	if general_name == "布鲁斯·萨维奇" and kneeling:
		return 5
	# 【无谋】锁定技（布鲁斯·萨维奇）：体力值小于体力上限时，手牌上限为 0
	if general_name == "布鲁斯·萨维奇" and hp < max_hp:
		return 0
	return hp + bonus

func add_to_hand(card: CardBase):
	hand.append(card)
	hand_updated.emit()

func remove_from_hand(card: CardBase) -> bool:
	var idx = hand.find(card)
	if idx >= 0:
		hand.remove_at(idx)
		hand_updated.emit()
		return true
	return false

func hand_size() -> int:
	return hand.size()

# ---- 牌区域查询（过河拆桥/顺手牵羊用）----

# 是否任何区域有牌（手牌/装备/判定）
func has_any_card() -> bool:
	return hand_size() > 0 or equipment.size() > 0 or judgment_cards.size() > 0

# 已装备的槽位列表
func get_equip_slots() -> Array[String]:
	var slots: Array[String] = []
	for s in EQUIP_SLOTS:
		if equipment.has(s):
			slots.append(s)
	return slots

# 卸下指定槽位装备（同时重置对应属性）
func remove_equipment(slot: String):
	var sub = equipment.get(slot, -1)
	equipment.erase(slot)
	# 【白银狮子】：当你失去装备区里的白银狮子时，回复 1 点体力（上限内，死亡角色不回复）
	if sub == CardData.CardSubType.SILVER_LION and is_alive():
		hp += 1
	match sub:
		CardData.CardSubType.MOUNT_PLUS:
			mount_plus = maxi(mount_plus - 1, 0)
		CardData.CardSubType.MOUNT_MINUS:
			mount_minus = maxi(mount_minus - 1, 0)
		CardData.CardSubType.MULE_MINUS, CardData.CardSubType.MULE_PLUS:
			pass  # 劣马是全局效果，无个人计数
		CardData.CardSubType.LIANNU, CardData.CardSubType.ZHUGE_LIANNU, CardData.CardSubType.QINGLONG_BLADE, CardData.CardSubType.ZHANGBA_SPEAR, CardData.CardSubType.CHIXIONG_SHUANGGU, CardData.CardSubType.ICE_SWORD, CardData.CardSubType.QINGGANG_SWORD, CardData.CardSubType.GUDING_BLADE, CardData.CardSubType.GUANSHI_AXE, CardData.CardSubType.QILING_BOW, CardData.CardSubType.FANGTIAN_HALBERD, CardData.CardSubType.FATE_BLADE, CardData.CardSubType.GOU_LIAN_CLAW, CardData.CardSubType.BLOODTHIRSTY_BLADE, CardData.CardSubType.CALAMITY_SWORD, CardData.CardSubType.HEAL_STAFF, CardData.CardSubType.RAGING_AXE, CardData.CardSubType.SOUL_BLADE:
			pass  # 武器无攻击距离加成，属性无需重置（唯一性由 EquipmentPool 管理）
		CardData.CardSubType.POFENG_SPEAR:
			hand_limit_bonus = 0  # 失去破风枪：手牌上限加成清零
		CardData.CardSubType.RENWANG_DUN, CardData.CardSubType.BAIHUA_SKIRT, CardData.CardSubType.QIXING_PAO, CardData.CardSubType.SILVER_LION, CardData.CardSubType.SHENGGUANG_BAIYI, CardData.CardSubType.BAGUA_ZHEN, CardData.CardSubType.TENGJIA, CardData.CardSubType.ZHANQI, CardData.CardSubType.LIEHUO_SHIELD, CardData.CardSubType.QINGGANG_SHIELD, CardData.CardSubType.THORN_ARMOR, CardData.CardSubType.CALAMITY_ROBE:
			pass  # 防具无属性重置
		CardData.CardSubType.SAGE_PROTECTION:
			# 贤者标记跟随装备移动：失去贤者的加护时标记/激活状态一起清空
			sage_tokens = 0
			sage_activated = false
		CardData.CardSubType.HIDDEN_EQUIPMENT:
			# 【苕】暗置装备被卸下：清空暗置状态
			hidden_equip_slot = ""

# ============================
#  攻击距离计算（标准三国杀）
# ============================

# 设置总玩家数
func set_total_players(count: int):
	_total_players = count

# 计算与另一玩家的座位距离（顺时针与逆时针取最小值）
func seat_distance_to(other: Player) -> int:
	var diff = abs(seat_index - other.seat_index)
	return mini(diff, _total_players - diff)

# 是否装备了 -1劣马（全局距离修正）
func has_mule_minus() -> bool:
	for s in MOUNT_SLOTS:
		if equipment.get(s, -1) == CardData.CardSubType.MULE_MINUS:
			return true
	return false

# 是否装备了 +1劣马（全局距离修正）
func has_mule_plus() -> bool:
	for s in MOUNT_SLOTS:
		if equipment.get(s, -1) == CardData.CardSubType.MULE_PLUS:
			return true
	return false

# 攻击此目标需要的实际距离（计数制：自己的 -1 马数量缩短距离，目标的 +1 马数量增加距离）
# 武器无攻击距离加成；距离最小为 1
# 【劣马】全局修正：其他玩家视作额外装备了劣马（-1劣马→攻击距离额外-1；+1劣马→目标被攻击距离额外+1）
func attack_distance_to(target: Player) -> int:
	var dist = seat_distance_to(target)
	dist -= mount_minus     # 每匹 -1 马缩短 1 距离
	dist += target.mount_plus  # 目标的每匹 +1 马增加 1 距离
	# 劣马全局效果：由 GameManager 提供（玩家是 GameManager 的子节点）
	var parent_node = get_parent()
	if parent_node != null and parent_node.has_method("_mule_distance_mod"):
		var mod: Vector2i = parent_node._mule_distance_mod(self, target)
		dist -= mod.x
		dist += mod.y
	return maxi(dist, 1)    # 距离最小为 1

# 此目标是否在攻击范围内（攻击范围恒为 1，只由马决定距离）
func can_attack(target: Player) -> bool:
	if target == self:
		return false
	return attack_distance_to(target) <= attack_range

# 装备坐骑：自动装入第一个空坐骑槽（4 个槽位，+1/-1 马与劣马自由搭配）
# 成功返回 true；槽位已满返回 false
func equip_mount(sub_type: CardData.CardSubType) -> bool:
	if sub_type != CardData.CardSubType.MOUNT_PLUS and sub_type != CardData.CardSubType.MOUNT_MINUS \
			and sub_type != CardData.CardSubType.MULE_PLUS and sub_type != CardData.CardSubType.MULE_MINUS:
		return false
	for slot in MOUNT_SLOTS:
		if not equipment.has(slot):
			equipment[slot] = sub_type
			if sub_type == CardData.CardSubType.MOUNT_PLUS:
				mount_plus += 1
			elif sub_type == CardData.CardSubType.MOUNT_MINUS:
				mount_minus += 1
			# 劣马：全局效果，不计入个人 +1/-1 计数
			return true
	return false

# 是否还有空坐骑槽位
func has_free_mount_slot() -> bool:
	for slot in MOUNT_SLOTS:
		if not equipment.has(slot):
			return true
	return false

# 已占用的坐骑槽位列表
func get_mount_slots() -> Array[String]:
	var slots: Array[String] = []
	for s in MOUNT_SLOTS:
		if equipment.has(s):
			slots.append(s)
	return slots

# 替换指定槽位的马（槽满时顶掉任意一匹）：旧马计数-1，新马计数+1（劣马无个人计数）
func replace_mount(slot: String, sub_type: CardData.CardSubType) -> bool:
	if not MOUNT_SLOTS.has(slot) or not equipment.has(slot):
		return false
	if sub_type != CardData.CardSubType.MOUNT_PLUS and sub_type != CardData.CardSubType.MOUNT_MINUS \
			and sub_type != CardData.CardSubType.MULE_PLUS and sub_type != CardData.CardSubType.MULE_MINUS:
		return false
	var old = equipment[slot]
	equipment[slot] = sub_type
	if old == CardData.CardSubType.MOUNT_PLUS:
		mount_plus -= 1
	elif old == CardData.CardSubType.MOUNT_MINUS:
		mount_minus -= 1
	if sub_type == CardData.CardSubType.MOUNT_PLUS:
		mount_plus += 1
	elif sub_type == CardData.CardSubType.MOUNT_MINUS:
		mount_minus += 1
	return true

# 当前已装备的马数量（含劣马，占用的坐骑槽数）
func mount_count() -> int:
	return get_mount_slots().size()

# ---- 武器 ----

# 当前武器（-1 = 无武器）
func get_weapon() -> CardData.CardSubType:
	return equipment.get("weapon", -1)

# 当前防具（-1 = 无防具）
func get_armor() -> CardData.CardSubType:
	return equipment.get("armor", -1)

# 本回合可使用的【杀】次数上限（-1 = 无次数限制）
# 无武器：1 次；连弩：2 次（每回合可额外打出一张杀）；诸葛连弩：无限制
func strike_limit() -> int:
	var weapon = get_weapon()
	if weapon == CardData.CardSubType.ZHUGE_LIANNU:
		return -1
	if weapon == CardData.CardSubType.LIANNU:
		return 2
	return 1
