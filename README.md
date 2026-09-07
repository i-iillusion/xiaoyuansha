# 校园杀

基于 Godot 4.7 的自定义规则卡牌游戏。目前为本地原型，完整知识手册中的武将和规则尚未全部实现。

## 规则与讨论

- [开发 QA：问题编号、待讨论事项、确认答案及实现状态](docs/QA.md)
- [规则确认与待讨论记录](docs/规则确认与待讨论.md)
- 根目录《校园杀完全知识手册 初版 V2.pdf》为规则正文；负责人明确补充的裁定优先于相应旧文字。

## 运行与测试

使用 Godot 4.7.x 导入 `project.godot`，运行主场景。美术资源当前不在开发范围内。

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . --script test_rule_settlement.gd
godot --headless --path . --script test_confirmed_rules.gd
```

Windows 可将 `godot` 换成 Godot 控制台程序的完整路径。根目录的 `test_*.gd` 包含规则断言测试和部分诊断脚本；只有出现完整 `RESULT` 汇总、失败为零且没有脚本错误，才可计为对应断言测试通过。
