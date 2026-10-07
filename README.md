# 校园杀

基于 Godot 4.7 的自定义规则卡牌游戏。目前为本地原型，完整知识手册中的武将和规则尚未全部实现。

## 规则与讨论

- [当前开发交接与下一任务](Docs/Agent/开发交接.md) · [唯一开发执行计划](Docs/HumanAgent/开发执行计划.md) · [现行裁决索引](Docs/HumanAgent/现行裁决索引.md)
- [首版开发前检查：预大习最终顺序、远端同步与首批修复门槛](Docs/HumanAgent/首版开发前检查-2026-09-12.md)
- [历史合并记录：PR #7 基线与当时局部阻塞](Docs/HumanAgent/合并dev后开发交接.md)
- [待裁决具体案例：按编号讨论，不阻塞无关开发](Docs/HumanAgent/待裁决具体案例.md)
- [校园杀完全知识手册：规则正文、游戏模式和武将说明](Docs/Original/校园杀完全知识手册.md)
- [开发 QA：问题编号、待讨论事项、确认答案及实现状态](Docs/HumanAgent/QA.md)
- [规则确认与待讨论记录](Docs/HumanAgent/规则确认与待讨论.md)
- [里程碑计划与短期目标](Docs/HumanAgent/里程碑计划.md) · [开发看板](https://github.com/i-iillusion/xiaoyuansha/issues/5)
- [项目架构设计：代码模块、三阶段与规则时序](Docs/HumanAgent/项目架构设计.md)

仓库中的《校园杀完全知识手册》Markdown 文档为规则正文；负责人明确补充的裁定优先于手册中的相应旧文字，详见规则确认记录与开发 QA。

## 项目目录

- `Scenes/`：游戏和 UI 场景。
- `Scripts/`：游戏规则、数据和 UI 脚本。
- `Test/`：规则断言测试、UI 冒烟测试和诊断脚本，附带对应 `.gd.uid`。
- `Docs/`：[文档分类索引](Docs/README.md)，分为 `Original/` 原始文档、`Agent/` Agent 内部文档、`HumanAgent/` 人与 Agent 的交互记录。

移动 Godot 脚本时应同时保留对应 `.uid` 文件。测试仍属于项目资源，不在 `Test/` 中添加 `.gdignore`。

## 运行与测试

[源码试玩基础包：下载、启动、操作与人工验收清单](Docs/HumanAgent/试玩基础包.md)。需要 Godot 4.7.2，不是免安装 EXE；当前为单人控制玩家0、其余AI的本地原型，无网络联机。

使用 Godot 4.7.x 导入 `project.godot`，运行主场景。测试模式当前可进入 2/3 人无身份乱斗和 5 人标准身份局；6～10 人模式与正式单人/多人入口仍未开放。美术资源当前不在开发范围内。

里奥·普利威尔现进入自选菜单和八名非占位武将的随机池，基础5体力（经典五人主公另加1）；丑态、预习、预大习已接现有真实流程。选将列表可滚动，技能详情保留完整牌文；AI目前保守选择不替换锦囊，这属于策略，不限制真人合法替换。开放范围与未覆盖组合见[F03验收记录](Docs/HumanAgent/F03执行与开放验收-2026-10-07.md)，不表示其他23名资料将或未来玩法已实装。

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . --script Test/test_rule_settlement.gd
godot --headless --path . --script Test/test_confirmed_rules.gd
godot --headless --path . --script Test/test_bill.gd
godot --headless --path . --script Test/test_hand_payment.gd
godot --headless --path . --script Test/test_card_transfer.gd
godot --headless --path . --script Test/test_identity_victory.gd
godot --headless --path . --script Test/test_free_for_all_victory.gd
```

以上命令在项目根目录执行，`--path .` 始终指向包含 `project.godot` 的目录。Windows 可将 `godot` 换成 Godot 控制台程序的完整路径。`Test/test_*.gd` 包含规则断言测试和部分诊断脚本；只有出现完整 `RESULT` 汇总、失败为零且没有脚本错误，才可计为对应断言测试通过。

## GitHub Actions CI

[Godot CI](.github/workflows/ci.yml) 在推送、Pull Request 和手动触发时运行，使用 Ubuntu 24.04 与 Godot 4.7.2 标准版（不安装 .NET 或导出模板）。

CI 先以 headless 模式导入项目，再依次执行 `Test/test_rule_settlement.gd`、`Test/test_confirmed_rules.gd`、`Test/test_bill.gd`、`Test/test_hand_payment.gd`、`Test/test_card_transfer.gd`、`Test/test_identity_victory.gd` 和 `Test/test_free_for_all_victory.gd`。每组测试限时 60 秒，必须正常退出、输出非零断言数且零失败的完整 `RESULT`，并且没有脚本或引擎错误。某组失败后仍继续收集其余各组结果；导入失败则不进入测试步骤。

运行日志通过 `godot-ci-logs` artifact 保存 7 天。只有导入及七组测试全部成功，CI才打包该提交的 `playtest-source` 源码试玩下载物（保存14天），不导出独立程序或发布 Release。其余测试和诊断脚本尚未纳入 CI；增加测试时需确认它可无人值守运行，并满足相同的结果汇总约定。
