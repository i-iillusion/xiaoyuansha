# 校园杀

基于 Godot 4.7 的自定义规则卡牌游戏。目前为本地原型，完整知识手册中的武将和规则尚未全部实现。

## 规则与讨论

- [校园杀完全知识手册：规则正文、游戏模式和武将说明](Docs/校园杀完全知识手册.md)
- [开发 QA：问题编号、待讨论事项、确认答案及实现状态](Docs/QA.md)
- [规则确认与待讨论记录](Docs/规则确认与待讨论.md)

仓库中的《校园杀完全知识手册》Markdown 文档为规则正文；负责人明确补充的裁定优先于手册中的相应旧文字，详见规则确认记录与开发 QA。

## 项目目录

- `Scenes/`：游戏和 UI 场景。
- `Scripts/`：游戏规则、数据和 UI 脚本。
- `Test/`：规则断言测试、UI 冒烟测试和诊断脚本，附带对应 `.gd.uid`。
- `Docs/`：知识手册、规则裁定和开发 QA。

移动 Godot 脚本时应同时保留对应 `.uid` 文件。测试仍属于项目资源，不在 `Test/` 中添加 `.gdignore`。

## 运行与测试

使用 Godot 4.7.x 导入 `project.godot`，运行主场景。美术资源当前不在开发范围内。

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . --script Test/test_rule_settlement.gd
godot --headless --path . --script Test/test_confirmed_rules.gd
```

以上命令在项目根目录执行，`--path .` 始终指向包含 `project.godot` 的目录。Windows 可将 `godot` 换成 Godot 控制台程序的完整路径。`Test/test_*.gd` 包含规则断言测试和部分诊断脚本；只有出现完整 `RESULT` 汇总、失败为零且没有脚本错误，才可计为对应断言测试通过。

## GitHub Actions CI

[Godot CI](.github/workflows/ci.yml) 在推送、Pull Request 和手动触发时运行，使用 Ubuntu 24.04 与 Godot 4.7.2 标准版（不安装 .NET 或导出模板）。

CI 先以 headless 模式导入项目，再依次执行 `Test/test_rule_settlement.gd`、`Test/test_confirmed_rules.gd` 和 `Test/test_bill.gd`。每组测试限时 60 秒，必须正常退出、输出非零断言数且零失败的完整 `RESULT`，并且没有脚本或引擎错误。某组失败后仍继续收集其余两组结果；导入失败则不进入测试步骤。

运行日志通过 `godot-ci-logs` artifact 保存 7 天。其他测试和诊断脚本尚未纳入 CI；增加测试时需确认它可无人值守运行，并满足相同的结果汇总约定。CI 不负责导出或发布游戏。
