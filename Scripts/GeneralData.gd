# ============================================================
# GeneralData.gd — 武将数据（以同学为原型）
# 每个武将：体力上限、头像 emoji、技能描述列表
# ============================================================
class_name GeneralData

# 武将表：general_name -> 数据
const GENERALS = {
	"稻草人": {
		"max_hp": 5,
		"avatar": "🦊",
		"skills": [],
	},
	"比尔·盖伊": {
		"max_hp": 3,
		"avatar": "🧔",
		"skills": [
			"【英姿】锁定技：摸牌阶段，你多摸一张牌",
			"【神速】回合开始阶段，你可以选择以下两项中的一项：1.跳过你的判定阶段（当你的判定区有牌时），并视为你对一名其他角色打出一张无距离限制的杀；2.跳过你的出牌和弃牌阶段，你的下个摸牌阶段少摸一张牌；当你连续多个回合发动该技能并选择此项时，摸牌减益将叠加（最少摸 0 张）",
			"【Gay】出牌阶段限一次，你可以弃置 X 张手牌，令你和一名已受伤的同性角色各回复 X 点体力（X 不大于你与该角色体力上限中的最小值）",
		],
	},
	"凯文·罗本": {
		"max_hp": 4,
		"avatar": "🧑‍🎓",
		"skills": [
			"【裸奔】锁定技：当你装备区没有装备时，你不能成为【杀】的目标",
			"【你个壊货】每当你受到一点伤害后，你可以与伤害来源进行一次拼点（猜拳），若你赢，你摸两张牌；每当你造成一点伤害后，你可以与该目标进行一次拼点，若你赢，你摸两张牌",
		],
	},
	"布鲁斯·萨维奇": {
		"max_hp": 5,
		"avatar": "🦍",
		"skills": [
			"【无谋】锁定技：当你的体力值小于体力上限时，你的手牌上限为 0",
			"【暴怒】锁定技：你的【杀】和【决斗】额外造成你已损失体力值的伤害",
			"【下跪】限定技：在你的回合外，当你没有手牌且已经受伤时，你可以发动此技能，进入【下跪】状态。下跪状态：你不会成为任何效果的目标，无法使用或打出任何牌，技能【无谋】失效，固定手牌上限为 5；你可以在任意时刻解除【下跪】状态",
		],
	},
	"安普提·斯丢皮得": {
		"max_hp": 3,
		"avatar": "🤪",
		"skills": [
			"【是~啊~】当你需要使用一张锦囊牌时，你可以流失一点体力，视为你使用了一张锦囊牌",
			"【苕】当你使用装备牌时，你可以暗置你的装备，并在合适的时候明置你的装备牌",
			"【装傻】锁定技，当你将要死亡时，你与场上所有存活玩家进行一次拼点，若你赢至少一半（向上取整），你回复至1点体力；此技能猜拳平局不重猜",
		],
	},
	"史蒂芬·彼特先斯": {
		"max_hp": 3,
		"avatar": "😎",
		"skills": [
			"【拍胸脯】当你将要受到一次伤害时，若你发动该技能，伤害来源需要弃置一张手牌才能造成伤害",
			"【装逼】在你的出牌阶段，你可以选择任意数量的其他角色，你与他们各弃置一张手牌后依次进行拼点；若胜多于负，所有输给你的角色受到一点来自你的伤害，你可以再次使用此技能；若负多于胜，你立即进入弃牌阶段；若胜负各半，两者都不算，不造成技能伤害、不强制弃牌，本出牌阶段不能再发动",
			"【觉醒】觉醒技，当你没有手牌时，你立刻失去一点体力上限，摸两张牌，并在以下三项中选择一项：1.不能成为【杀】的目标；2.不能成为【决斗】的目标；3.不能成为【南蛮入侵】和【万箭齐发】的目标",
		],
	},
	"杰基·斯特朗": {
		"max_hp": 6,
		"avatar": "💪",
		"skills": [
			"【霸王】锁定技：你每回合可以额外使用一张【决斗】，你的【决斗】无距离限制；当你与其他角色进行【决斗】时，该角色每次响应此【决斗】需依次打出两张【杀】，且总是由该角色先响应此【决斗】",
			"【校园霸主】出牌阶段，你可以选择一名除你以外的有手牌的角色，你与该角色各弃置一张手牌并进行拼点，赢者对输者造成一点伤害",
		],
	},
	"麦克斯·欧尼斯特": {
		"max_hp": 4,
		"avatar": "🤠",
		"skills": [
			"【烂忠厚】出牌阶段限一次，你可以弃 X 张牌，选择两名角色（可含自己）的 X 个装备区域并交换其中的装备：武器/防具各最多 1 对，坐骑最多 4 对（每名角色 4 个坐骑槽），最多 6 对弃 6 张牌；坐骑可跨槽位交换（如 A 坐骑1 ↔ B 坐骑3）；某一方区域为空或为暗置装备时装备直接归还，不交换；选择坐骑区域时只能选有装备的坐骑槽",
			"【没用】回合开始阶段，你可以摸一张牌，并在以下三项中选择一项：1.跳过你的判定阶段，使一名除你以外判定区有牌的角色立刻进行他的判定阶段（其乐不思蜀/兵粮寸断失效，闪电/火烧连营正常生效）；2.跳过你的摸牌阶段，使一名除你以外的角色立刻获得一个摸牌阶段；3.跳过你的出牌阶段，使一名除你以外的角色立刻获得一个出牌阶段",
		],
	},
}

# 手册第6章资料索引；以下武将的技能尚未完整接入，不进入自选菜单。
# 安迪整组暂缓；泰瑞的体力上限 X = 开局其他玩家数，需在开局时给出人数。
const METADATA_ONLY_GENERALS = {
	"里奥·普利威尔": {"max_hp": 5, "section": "6.7"},
	"彼得·伊茨·朗·欧弗·约尔·欧耳·麦·彼茨尼兹": {"max_hp": 3, "section": "6.8"},
	"大卫·法米尔": {"max_hp": 4, "section": "6.9"},
	"卢卡斯·托克": {"max_hp": 5, "section": "6.11"},
	"桑尼·斯派": {"max_hp": 4, "section": "6.12"},
	"辛巴·古德曼": {"max_hp": 5, "section": "6.13"},
	"克莉丝汀·艾": {"max_hp": 3, "gender": "female", "section": "6.14"},
	"史蒂夫·UB": {"max_hp": 4, "section": "6.15"},
	"克里斯·西弗": {"max_hp": 3, "section": "6.16"},
	"本尼·康绸尔": {"max_hp": 3, "section": "6.17"},
	"泰瑞·谢尔": {"max_hp": -1, "section": "6.18"},
	"萨利·赛克斯": {"max_hp": 3, "gender": "female", "section": "6.19"},
	"杰克·伯德": {"max_hp": 4, "section": "6.20"},
	"海因里希·迷因": {"max_hp": 4, "section": "6.21"},
	"汤姆·伊茨弥": {"max_hp": 4, "section": "6.22"},
	"菲利普·霓虹": {"max_hp": 4, "section": "6.23"},
	"托尼·巴斯基得博": {"max_hp": 4, "section": "6.24"},
	"杰克·安格": {"max_hp": 4, "section": "6.25"},
	"桑尼·泰姆": {"max_hp": 3, "section": "6.26"},
	"亨利·瑟提": {"max_hp": 4, "section": "6.27"},
	"纳撒尼尔·艾尔可霍": {"max_hp": 8, "section": "6.28"},
	"蒂姆·斯哈": {"max_hp": 4, "section": "6.29"},
	"吉姆·芒顿": {"max_hp": 6, "section": "6.30"},
	"安迪·沃费尔": {"max_hp": 4, "section": "6.31", "deferred": true},
}

static func get_max_hp(general_name: String, player_count: int = 0) -> int:
	var data = GENERALS.get(general_name)
	if data == null:
		data = METADATA_ONLY_GENERALS.get(general_name)
	if general_name == "泰瑞·谢尔":
		return maxi(player_count - 1, 0)
	if data == null:
		return 4
	return data.get("max_hp", 4)

static func get_gender(general_name: String) -> String:
	return METADATA_ONLY_GENERALS.get(general_name, {}).get("gender", "male")

static func get_implementation_status(general_name: String) -> String:
	if general_name == "稻草人":
		return "placeholder"
	if GENERALS.has(general_name):
		return "prototype"
	if METADATA_ONLY_GENERALS.has(general_name):
		return "deferred" if METADATA_ONLY_GENERALS[general_name].get("deferred", false) else "metadata_only"
	return "unknown"

static func get_handbook_section(general_name: String) -> String:
	return METADATA_ONLY_GENERALS.get(general_name, {}).get("section", "")

static func get_avatar(general_name: String) -> String:
	var data = GENERALS.get(general_name)
	if data == null:
		return "🦊"
	return data.get("avatar", "🦊")

static func get_skills(general_name: String) -> Array:
	var data = GENERALS.get(general_name)
	if data == null:
		return []
	return data.get("skills", [])

static func is_valid(general_name: String) -> bool:
	return GENERALS.has(general_name) or METADATA_ONLY_GENERALS.has(general_name)

# 从已实现的武将里随机选一个（排除稻草人占位）
static func get_random_general() -> String:
	var pool = get_available_random_generals()
	return pool[randi() % pool.size()] if not pool.is_empty() else ""

static func get_available_random_generals() -> Array[String]:
	var pool: Array[String] = []
	for key in GENERALS:
		if key != "稻草人":
			pool.append(key)
	return pool

# 同局随机武将无放回抽取。池不足时返回空数组，由开局入口拒绝不完整分配。
static func draw_unique_random_generals(count: int) -> Array[String]:
	var pool = get_available_random_generals()
	if count < 0:
		return []
	pool.shuffle()
	if count <= pool.size():
		return pool.slice(0, count)
	var supplements: Array[String] = []
	for key in METADATA_ONLY_GENERALS:
		if not METADATA_ONLY_GENERALS[key].get("deferred", false):
			supplements.append(key)
	if count > pool.size() + supplements.size():
		return []
	supplements.shuffle()
	pool.append_array(supplements.slice(0, count - pool.size()))
	return pool
