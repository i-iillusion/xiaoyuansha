# ============================================================
# CardData.gd — 卡牌类型枚举和数据常量
# ============================================================
class_name CardData

# 卡牌大类
enum CardType { BASIC, STRATAGEM, EQUIPMENT }

# 卡牌子类型
enum CardSubType {
	# 基本牌
	STRIKE,   # 杀
	FIRE_STRIKE,    # 火杀（火属性）
	THUNDER_STRIKE, # 雷杀（雷属性）
	DODGE,    # 闪
	PEACH,    # 桃
	WINE,     # 酒
	# 锦囊牌
	BARBARIAN_INVASION,  # 南蛮入侵
	VOLLEY_OF_ARROWS,     # 万箭齐发
	DUEL,                 # 决斗
	IRON_CHAIN,           # 铁索连环
	PEACH_GARDEN,         # 桃园结义
	HARVEST,              # 五谷丰登
	DISARM,               # 卸甲归田
	SNATCH,               # 顺手牵羊
	DISMANTLE,            # 过河拆桥
	BURNING_CAMP,         # 火烧连营（火焰蔓延：瞬发+判定双效果）
	NULLIFICATION,        # 无懈可击（响应牌，不能主动打出）
	SACRIFICE,            # 舍己为人（响应牌：其他玩家将要受到伤害时打出，代替其承受）
	# 延时锦囊（判定牌）
	LIGHTNING,            # 闪电
	INDULGENCE,           # 乐不思蜀
	SUPPLY_SHORTAGE,      # 兵粮寸断
	# 装备牌
	WEAPON,       # 武器（占位/通用）
	ARMOR,        # 护甲（占位/通用）
	LIANNU,       # 连弩（武器）：每回合可额外打出一张杀
	ZHUGE_LIANNU, # 诸葛连弩（武器）：每回合使用杀无次数限制
	QINGLONG_BLADE, # 青龙偃月刀（武器）：每回合第一次打出杀时摸一张牌
	ZHANGBA_SPEAR, # 丈八蛇矛（武器）：杀造成伤害后，可流失X体力使目标额外受X伤害（X≤3）
	CHIXIONG_SHUANGGU, # 雌雄双股剑（武器）：杀指定异性目标后，令其弃一张手牌或令你摸一张牌
	ICE_SWORD,        # 寒冰剑（武器）：杀造成伤害后，可防止此伤害改为弃置其两张手牌
	QINGGANG_SWORD,   # 青釭剑（武器）：使用杀指定目标后，无视其防具
	GUDING_BLADE,     # 古锭刀（武器）：杀将要对目标造成伤害时，若其没有手牌，此伤害+1
	GUANSHI_AXE,      # 贯石斧（武器）：杀被闪抵消后，可弃置一张坐骑牌，令此杀依然造成伤害
	QILING_BOW,       # 麒麟弓（武器）：你的杀无距离限制
	POFENG_SPEAR,     # 破风枪（武器）：每当你造成一点伤害后，手牌上限+1（失去武器后清零）
	FANGTIAN_HALBERD, # 方天画戟（武器）：你的杀可以指定攻击范围内任意数量的角色为目标
	FATE_BLADE,       # 命运之刃（武器）：当你将要受到一次致命伤害时，可弃置此武器防止本次伤害
	GOU_LIAN_CLAW,    # 勾镰爪（武器）：当你对一名角色造成伤害后，可获得其装备区里的一张坐骑牌
	BLOODTHIRSTY_BLADE, # 噬血之刃（武器）：每当你造成一点伤害后，可与受伤角色进行一次拼点（猜拳），若你赢则回复1点体力
	CALAMITY_SWORD,   # 灾厄剑（武器）：你造成的所有伤害-1；当你造成一次伤害后，可将本装备移至一名其他角色的装备区
	HEAL_STAFF,       # 治疗权杖（武器）：每个回合内，你使用的第一张桃额外回复一点体力（含其他玩家回合）
	RAGING_AXE,       # 狂暴战斧（武器）：你打出的酒的伤害+1效果可以叠加，且你的酒状态不会因回合结束而消失
	SOUL_BLADE,       # 摄魂刀（武器）：激活：对同一玩家连续累计造成3点伤害后激活；杀造成伤害后可拼点两次，全赢/弃2张/弃4张令目标武将牌翻面
	RENWANG_DUN,      # 仁王盾（防具）：南蛮入侵和万箭齐发对你无效
	BAIHUA_SKIRT,     # 百花裙（防具）：当你体力值为1时，你不会受到任何伤害
	QIXING_PAO,       # 七星袍（防具）：你不会受到任何属性伤害
	SILVER_LION,      # 白银狮子（防具）：你受到伤害最多为1点；失去装备区里的白银狮子时回复1点体力
	SHENGGUANG_BAIYI, # 圣光白衣（防具）：你的手牌上限+2
	BAGUA_ZHEN,       # 八卦阵（防具）：你每使用或打出一张【闪】时，摸一张牌
	TENGJIA,          # 藤甲（防具）：你不能成为【杀】的目标
	ZHANQI,           # 战旗（防具）：你不能成为【决斗】的目标；你受到来自【杀】的伤害至多为1
	LIEHUO_SHIELD,    # 烈火盾（防具）：将失去一张牌时可流失1体力代替；寒冰剑打杀时双方弃装备再结算
	QINGGANG_SHIELD,  # 青釭盾（防具）：成为效果目标时无视使用效果者的武器；青釭剑打杀时双方弃装备再结算
	THORN_ARMOR,      # 荆棘战甲（防具）：每当你受到一点伤害后，你与伤害来源拼点，若你赢则对其造成1点伤害
	CALAMITY_ROBE,    # 灾厄袍（防具）：你受到的火焰伤害+1；当你受到一次伤害后，可将本装备移至一名其他角色的装备区
	SAGE_PROTECTION,  # 贤者的加护（防具）：出牌阶段弃一张手牌与一名角色拼点，赢则获贤者标记；3标记激活；激活后濒死时可弃所有牌复原武将牌并摸四张
	MOUNT_PLUS,   # +1马
	MOUNT_MINUS,  # -1马
	MULE_MINUS,   # -1劣马（坐骑）：距离判定时视作其他玩家额外装备了-1马
	MULE_PLUS,    # +1劣马（坐骑）：距离判定时视作其他玩家额外装备了+1马
	HIDDEN_EQUIPMENT,  # 暗置装备（【苕】占位，明置后变为具体装备）
}

# 卡牌中文名映射
const CARD_NAMES = {
	CardSubType.STRIKE: "杀",
	CardSubType.FIRE_STRIKE: "火杀",
	CardSubType.THUNDER_STRIKE: "雷杀",
	CardSubType.DODGE: "闪",
	CardSubType.PEACH: "桃",
	CardSubType.WINE: "酒",
	CardSubType.BARBARIAN_INVASION: "南蛮入侵",
	CardSubType.VOLLEY_OF_ARROWS: "万箭齐发",
	CardSubType.DUEL: "决斗",
	CardSubType.IRON_CHAIN: "铁索连环",
	CardSubType.PEACH_GARDEN: "桃园结义",
	CardSubType.HARVEST: "五谷丰登",
	CardSubType.DISARM: "卸甲归田",
	CardSubType.SNATCH: "顺手牵羊",
	CardSubType.DISMANTLE: "过河拆桥",
	CardSubType.BURNING_CAMP: "火烧连营",
	CardSubType.NULLIFICATION: "无懈可击",
	CardSubType.SACRIFICE: "舍己为人",
	CardSubType.LIGHTNING: "闪电",
	CardSubType.INDULGENCE: "乐不思蜀",
	CardSubType.SUPPLY_SHORTAGE: "兵粮寸断",
	CardSubType.WEAPON: "武器",
	CardSubType.ARMOR: "护甲",
	CardSubType.LIANNU: "连弩",
	CardSubType.ZHUGE_LIANNU: "诸葛连弩",
	CardSubType.QINGLONG_BLADE: "青龙偃月刀",
	CardSubType.ZHANGBA_SPEAR: "丈八蛇矛",
	CardSubType.CHIXIONG_SHUANGGU: "雌雄双股剑",
	CardSubType.ICE_SWORD: "寒冰剑",
	CardSubType.QINGGANG_SWORD: "青釭剑",
	CardSubType.GUDING_BLADE: "古锭刀",
	CardSubType.GUANSHI_AXE: "贯石斧",
	CardSubType.QILING_BOW: "麒麟弓",
	CardSubType.POFENG_SPEAR: "破风枪",
	CardSubType.FANGTIAN_HALBERD: "方天画戟",
	CardSubType.FATE_BLADE: "命运之刃",
	CardSubType.GOU_LIAN_CLAW: "勾镰爪",
	CardSubType.BLOODTHIRSTY_BLADE: "噬血之刃",
	CardSubType.CALAMITY_SWORD: "灾厄剑",
	CardSubType.HEAL_STAFF: "治疗权杖",
	CardSubType.RAGING_AXE: "狂暴战斧",
	CardSubType.SOUL_BLADE: "摄魂刀",




	CardSubType.RENWANG_DUN: "仁王盾",
	CardSubType.BAIHUA_SKIRT: "百花裙",
	CardSubType.QIXING_PAO: "七星袍",
	CardSubType.SILVER_LION: "白银狮子",
	CardSubType.SHENGGUANG_BAIYI: "圣光白衣",
	CardSubType.BAGUA_ZHEN: "八卦阵",
	CardSubType.TENGJIA: "藤甲",
	CardSubType.ZHANQI: "战旗",
	CardSubType.LIEHUO_SHIELD: "烈火盾",
	CardSubType.QINGGANG_SHIELD: "青釭盾",
	CardSubType.THORN_ARMOR: "荆棘战甲",
	CardSubType.CALAMITY_ROBE: "灾厄袍",
	CardSubType.SAGE_PROTECTION: "贤者的加护",
	CardSubType.MOUNT_PLUS: "+1马",
	CardSubType.MOUNT_MINUS: "-1马",
	CardSubType.MULE_MINUS: "-1劣马",
	CardSubType.MULE_PLUS: "+1劣马",
	CardSubType.HIDDEN_EQUIPMENT: "一件装备",
}

# 卡牌效果描述（详情弹窗显示）
const CARD_DESCRIPTIONS = {
	CardSubType.STRIKE: "出牌阶段，对攻击范围内的一名角色使用，对其造成 1 点伤害（每回合限使用一张）",
	CardSubType.FIRE_STRIKE: "出牌阶段，对攻击范围内的一名角色使用，对其造成 1 点火焰伤害（每回合限使用一张；触发铁索连环传导）",
	CardSubType.THUNDER_STRIKE: "出牌阶段，对攻击范围内的一名角色使用，对其造成 1 点雷电伤害（每回合限使用一张；触发铁索连环传导）",
	CardSubType.DODGE: "响应牌：抵消【杀】或【万箭齐发】对你造成的伤害",
	CardSubType.PEACH: "出牌阶段或濒死时使用，回复 1 点体力",
	CardSubType.WINE: "出牌阶段使用，令本回合下一张【杀】伤害+1（不可叠加）；濒死时使用回复 1 点体力",
	CardSubType.BARBARIAN_INVASION: "出牌阶段，对所有其他角色使用，每名角色需打出【杀】，否则受到 1 点伤害（从你起顺时针结算）",
	CardSubType.VOLLEY_OF_ARROWS: "出牌阶段，对所有其他角色使用，每名角色需打出【闪】，否则受到 1 点伤害（从你起顺时针结算）",
	CardSubType.DUEL: "出牌阶段，对一名角色使用，由目标开始轮流出【杀】，无法打出者受到 1 点伤害（距离 2 内，每回合限两张）",
	CardSubType.IRON_CHAIN: "出牌阶段，对一至两名角色使用（可含自己），横置/重置其连环状态；连环角色受到属性伤害时传导",
	CardSubType.PEACH_GARDEN: "出牌阶段使用，所有存活角色回复 1 点体力（满血无效，每回合限一张）",
	CardSubType.HARVEST: "出牌阶段使用，每名角色摸「已损失体力值」数量的牌（最多 3 张，满血摸 0 张；每回合限一张）",
	CardSubType.DISARM: "出牌阶段使用，所有有装备的角色弃置所有装备牌，然后摸相同数量的牌",
	CardSubType.SNATCH: "出牌阶段，对距离 1 内的角色使用，获得其一张牌（与过河拆桥合计每回合限两张）",
	CardSubType.DISMANTLE: "出牌阶段，对任意角色使用，弃置其一张牌（无距离限制，与顺手牵羊合计每回合限两张）",
	CardSubType.BURNING_CAMP: "出牌阶段，对距离 1 的角色使用，其与其左右相邻角色各受 1 点火焰伤害，并在其左右相邻角色的判定区各生成一张【火烧连营】",
	CardSubType.NULLIFICATION: "响应牌：抵消一张锦囊牌的效果（不能主动打出，可连续响应）",
	CardSubType.SACRIFICE: "响应牌：其他角色将要受到伤害时打出，代替其承受等量同属性伤害（不能主动打出，受伤者本人不能用）",
	CardSubType.LIGHTNING: "延时锦囊：判定阶段判定（必定生效），受到 3 点雷电伤害（无伤害来源，触发铁索传导）",
	CardSubType.INDULGENCE: "延时锦囊：判定阶段判定（必定生效），跳过出牌阶段",
	CardSubType.SUPPLY_SHORTAGE: "延时锦囊：判定阶段判定（必定生效），摸牌阶段少摸一张牌",
	CardSubType.LIANNU: "每回合内可以额外打出一张【杀】",
	CardSubType.ZHUGE_LIANNU: "每回合内使用【杀】无次数限制",
	CardSubType.QINGLONG_BLADE: "每回合第一次打出【杀】时，摸一张牌",
	CardSubType.ZHANGBA_SPEAR: "每当你使用【杀】造成伤害后，你可以流失X点体力（X至多为3），令该角色额外受到X点伤害（流失体力不算受到伤害；额外伤害与基础伤害合并结算一次）",
	CardSubType.CHIXIONG_SHUANGGU: "当你使用【杀】指定一名异性角色为目标后，你可以令其选择一项：1.弃置一张手牌；2.令你摸一张牌",
	CardSubType.ICE_SWORD: "当你使用【杀】对目标角色造成伤害后，若该角色有手牌，你可以防止此伤害，改为依次弃置其两张手牌",
	CardSubType.QINGGANG_SWORD: "当你使用【杀】指定一名目标角色后，你无视其防具",
	CardSubType.GUDING_BLADE: "当你使用【杀】将要对目标角色造成伤害时，若该角色没有手牌，此伤害+1",
	CardSubType.GUANSHI_AXE: "当你打出的【杀】被目标角色使用【闪】抵消后，你可以弃置你装备区的一张坐骑牌，令此【杀】依然对其造成伤害",
	CardSubType.QILING_BOW: "你的【杀】无距离限制",
	CardSubType.POFENG_SPEAR: "每当你造成一点伤害后，你的手牌上限+1（失去此武器后加成清零）",
	CardSubType.FANGTIAN_HALBERD: "你的【杀】可以指定你攻击范围内的任意数量的角色为目标",
	CardSubType.FATE_BLADE: "当你将要受到一次致命伤害时，你可以弃置此武器，防止本次伤害",
	CardSubType.GOU_LIAN_CLAW: "每当你对一名角色造成伤害后，你可以获得其装备区里的一张坐骑牌",
	CardSubType.BLOODTHIRSTY_BLADE: "每当你造成一点伤害后，你可以与受到伤害的角色进行一次拼点（猜拳），若你赢，则你回复 1 点体力",
	CardSubType.CALAMITY_SWORD: "你造成的所有伤害-1；当你造成一次伤害后，你可以将本装备移至一名其他角色的装备区中",
	CardSubType.HEAL_STAFF: "每个回合内（含其他玩家的回合），你使用的第一张【桃】额外回复一点体力",
	CardSubType.RAGING_AXE: "你打出的【酒】的伤害+1效果可以叠加，且你的【酒】状态不会因回合结束而消失",
	CardSubType.SOUL_BLADE: "激活：当你对同一名玩家连续且累计造成 3 点伤害后，此装备激活。当你使用【杀】对目标角色造成伤害后，可以与其进行拼点两次：如你全赢，令其武将牌翻面；赢一输一，可弃两张手牌令其翻面；全输，可弃四张手牌令其翻面（可使反面的武将牌翻回正面）",




	CardSubType.RENWANG_DUN: "南蛮入侵和万箭齐发对你无效",
	CardSubType.BAIHUA_SKIRT: "当你体力值为 1 时，你不会受到任何伤害",
	CardSubType.QIXING_PAO: "你不会受到任何属性伤害（火/雷）",
	CardSubType.SILVER_LION: "你受到伤害最多为 1 点；当你失去装备区里的白银狮子时，回复 1 点体力",
	CardSubType.SHENGGUANG_BAIYI: "你的手牌上限+2",
	CardSubType.BAGUA_ZHEN: "你每使用或打出一张【闪】时，摸一张牌",
	CardSubType.TENGJIA: "你不能成为【杀】的目标",
	CardSubType.ZHANQI: "你不能成为【决斗】的目标；你受到来自【杀】的伤害至多为 1 点",
	CardSubType.LIEHUO_SHIELD: "当你将要失去一张牌时，你可以流失 1 点体力代替；当装备【寒冰剑】的角色对你使用【杀】时，双方弃置各自的【寒冰剑】与【烈火盾】，再进行之后的结算",
	CardSubType.QINGGANG_SHIELD: "当你成为一个效果的目标时，你无视使用效果者的武器；当装备【青釭剑】的角色对你使用【杀】时，双方弃置各自的【青釭剑】与【青釭盾】，再进行之后的结算",
	CardSubType.THORN_ARMOR: "每当你受到一点伤害后，你与伤害来源进行一次拼点（猜拳），若你赢，则你对其造成 1 点伤害",
	CardSubType.CALAMITY_ROBE: "你受到的火焰伤害+1；当你受到一次伤害后，你可以将本装备移至一名其他角色的装备区中",
	CardSubType.SAGE_PROTECTION: "激活：出牌阶段，你可以弃置一张手牌，与一名角色进行拼点。若你赢，则你获得一个贤者标记。当你拥有三个贤者标记时，将所有贤者标记弃置并激活此装备。激活后：当你即将死亡时，你可以弃置所有牌，然后复原你的武将牌至游戏开始时的状态，之后摸四张牌",
	CardSubType.MOUNT_PLUS: "其他角色计算与你之间的距离时 +1（防御马）",
	CardSubType.MOUNT_MINUS: "你计算与其他角色之间的距离时 -1（进攻马）",
	CardSubType.MULE_MINUS: "进行距离判定时，其他玩家视作额外装备了 1 匹 -1 马（攻击距离缩短，你更容易被打到）；当你受到伤害后，你可以将一匹 -1劣马移至一名其他角色的装备区中",
	CardSubType.MULE_PLUS: "进行距离判定时，其他玩家视作额外装备了 1 匹 +1 马（被攻击距离增加）；当你造成伤害后，你可以将一匹 +1劣马移至一名其他角色的装备区中",
}

# 卡牌类型 -> 所属大类 映射
const CARD_TYPE_MAP = {
	CardSubType.STRIKE: CardType.BASIC,
	CardSubType.FIRE_STRIKE: CardType.BASIC,
	CardSubType.THUNDER_STRIKE: CardType.BASIC,
	CardSubType.DODGE: CardType.BASIC,
	CardSubType.PEACH: CardType.BASIC,
	CardSubType.WINE: CardType.BASIC,
	CardSubType.BARBARIAN_INVASION: CardType.STRATAGEM,
	CardSubType.VOLLEY_OF_ARROWS: CardType.STRATAGEM,
	CardSubType.DUEL: CardType.STRATAGEM,
	CardSubType.IRON_CHAIN: CardType.STRATAGEM,
	CardSubType.PEACH_GARDEN: CardType.STRATAGEM,
	CardSubType.HARVEST: CardType.STRATAGEM,
	CardSubType.DISARM: CardType.STRATAGEM,
	CardSubType.SNATCH: CardType.STRATAGEM,
	CardSubType.DISMANTLE: CardType.STRATAGEM,
	CardSubType.BURNING_CAMP: CardType.STRATAGEM,
	CardSubType.NULLIFICATION: CardType.STRATAGEM,
	CardSubType.SACRIFICE: CardType.STRATAGEM,
	CardSubType.LIGHTNING: CardType.STRATAGEM,
	CardSubType.INDULGENCE: CardType.STRATAGEM,
	CardSubType.SUPPLY_SHORTAGE: CardType.STRATAGEM,
	CardSubType.WEAPON: CardType.EQUIPMENT,
	CardSubType.ARMOR: CardType.EQUIPMENT,
	CardSubType.LIANNU: CardType.EQUIPMENT,
	CardSubType.ZHUGE_LIANNU: CardType.EQUIPMENT,
	CardSubType.QINGLONG_BLADE: CardType.EQUIPMENT,
	CardSubType.ZHANGBA_SPEAR: CardType.EQUIPMENT,
	CardSubType.CHIXIONG_SHUANGGU: CardType.EQUIPMENT,
	CardSubType.ICE_SWORD: CardType.EQUIPMENT,
	CardSubType.QINGGANG_SWORD: CardType.EQUIPMENT,
	CardSubType.GUDING_BLADE: CardType.EQUIPMENT,
	CardSubType.GUANSHI_AXE: CardType.EQUIPMENT,
	CardSubType.QILING_BOW: CardType.EQUIPMENT,
	CardSubType.POFENG_SPEAR: CardType.EQUIPMENT,
	CardSubType.FANGTIAN_HALBERD: CardType.EQUIPMENT,
	CardSubType.FATE_BLADE: CardType.EQUIPMENT,
	CardSubType.GOU_LIAN_CLAW: CardType.EQUIPMENT,
	CardSubType.BLOODTHIRSTY_BLADE: CardType.EQUIPMENT,
	CardSubType.CALAMITY_SWORD: CardType.EQUIPMENT,
	CardSubType.HEAL_STAFF: CardType.EQUIPMENT,
	CardSubType.RAGING_AXE: CardType.EQUIPMENT,
	CardSubType.SOUL_BLADE: CardType.EQUIPMENT,




	CardSubType.RENWANG_DUN: CardType.EQUIPMENT,
	CardSubType.BAIHUA_SKIRT: CardType.EQUIPMENT,
	CardSubType.QIXING_PAO: CardType.EQUIPMENT,
	CardSubType.SILVER_LION: CardType.EQUIPMENT,
	CardSubType.SHENGGUANG_BAIYI: CardType.EQUIPMENT,
	CardSubType.BAGUA_ZHEN: CardType.EQUIPMENT,
	CardSubType.TENGJIA: CardType.EQUIPMENT,
	CardSubType.ZHANQI: CardType.EQUIPMENT,
	CardSubType.LIEHUO_SHIELD: CardType.EQUIPMENT,
	CardSubType.QINGGANG_SHIELD: CardType.EQUIPMENT,
	CardSubType.THORN_ARMOR: CardType.EQUIPMENT,
	CardSubType.CALAMITY_ROBE: CardType.EQUIPMENT,
	CardSubType.SAGE_PROTECTION: CardType.EQUIPMENT,
	CardSubType.MOUNT_PLUS: CardType.EQUIPMENT,
	CardSubType.MOUNT_MINUS: CardType.EQUIPMENT,
	CardSubType.MULE_MINUS: CardType.EQUIPMENT,
	CardSubType.MULE_PLUS: CardType.EQUIPMENT,
	CardSubType.HIDDEN_EQUIPMENT: CardType.EQUIPMENT,
}

# 获取所有可选卡牌类型（不含装备占位）
static func get_playable_sub_types() -> Array[CardSubType]:
	return [
		CardSubType.STRIKE,
		CardSubType.FIRE_STRIKE,
		CardSubType.THUNDER_STRIKE,
		CardSubType.DODGE,
		CardSubType.PEACH,
		CardSubType.WINE,
		CardSubType.BARBARIAN_INVASION,
		CardSubType.VOLLEY_OF_ARROWS,
		CardSubType.DUEL,
		CardSubType.IRON_CHAIN,
		CardSubType.PEACH_GARDEN,
		CardSubType.HARVEST,
		CardSubType.SNATCH,
		CardSubType.DISMANTLE,
		CardSubType.BURNING_CAMP,
		CardSubType.NULLIFICATION,
		CardSubType.SACRIFICE,
		CardSubType.MOUNT_PLUS,
		CardSubType.MOUNT_MINUS,
		CardSubType.MULE_MINUS,
		CardSubType.MULE_PLUS,
		CardSubType.LIANNU,
		CardSubType.ZHUGE_LIANNU,
		CardSubType.QINGLONG_BLADE,
		CardSubType.ZHANGBA_SPEAR,
		CardSubType.CHIXIONG_SHUANGGU,
		CardSubType.ICE_SWORD,
		CardSubType.QINGGANG_SWORD,
		CardSubType.GUDING_BLADE,
		CardSubType.GUANSHI_AXE,
		CardSubType.QILING_BOW,
		CardSubType.POFENG_SPEAR,
		CardSubType.FANGTIAN_HALBERD,
		CardSubType.FATE_BLADE,
		CardSubType.GOU_LIAN_CLAW,
		CardSubType.BLOODTHIRSTY_BLADE,
		CardSubType.CALAMITY_SWORD,
		CardSubType.HEAL_STAFF,
		CardSubType.RAGING_AXE,
		CardSubType.SOUL_BLADE,
		CardSubType.RENWANG_DUN,
		CardSubType.BAIHUA_SKIRT,
		CardSubType.QIXING_PAO,
		CardSubType.SILVER_LION,
		CardSubType.SHENGGUANG_BAIYI,
		CardSubType.BAGUA_ZHEN,
		CardSubType.TENGJIA,
		CardSubType.ZHANQI,
		CardSubType.LIEHUO_SHIELD,
		CardSubType.QINGGANG_SHIELD,
		CardSubType.THORN_ARMOR,
		CardSubType.CALAMITY_ROBE,
		CardSubType.SAGE_PROTECTION,
		CardSubType.LIGHTNING,
		CardSubType.INDULGENCE,
		CardSubType.SUPPLY_SHORTAGE,
	]

static func get_type_name(sub: CardSubType) -> String:
	return CARD_NAMES.get(sub, "未知")

static func get_description(sub: CardSubType) -> String:
	return CARD_DESCRIPTIONS.get(sub, "")

static func get_type_category(sub: CardSubType) -> CardType:
	return CARD_TYPE_MAP.get(sub, CardType.BASIC)

static func get_category_name(ct: CardType) -> String:
	match ct:
		CardType.BASIC: return "基本牌"
		CardType.STRATAGEM: return "锦囊牌"
		CardType.EQUIPMENT: return "装备牌"
	return "未知"
