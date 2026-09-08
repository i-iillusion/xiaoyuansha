# 文档索引

| 目录 | 内容与用途 | 入口 |
| --- | --- | --- |
| `Original/` | 维护者提供的原始规则文档；排版修正不改变规则原意 | [校园杀完全知识手册](Original/校园杀完全知识手册.md) |
| `Agent/` | Agent 使用的代码导航、开发交接与实现说明，不作为规则裁定 | [开发交接](Agent/开发交接.md) |
| `HumanAgent/` | 人与 Agent 之间的问题、答复、架构说明、确认裁定、实施计划与待讨论记录 | [项目架构设计](HumanAgent/项目架构设计.md)、[里程碑计划](HumanAgent/里程碑计划.md)、[开发 QA](HumanAgent/QA.md)、[规则确认与待讨论](HumanAgent/规则确认与待讨论.md) |

规则以原始手册为正文，负责人明确补充的裁定覆盖相应旧文字。Agent 的实现建议和代码现状不自动成为规则；待讨论事项继续保留在交互文档中。

实施证据：[规则差异与五人身份局验收基线（ST-03/04）](HumanAgent/规则差异与五人局验收.md)。

卡牌专项：[牌流转审计第一批（ST-08/10 局部）](HumanAgent/牌流转审计.md)。

原始文档中的中文标点可能影响 GFM 对 `**` 的识别。紧贴正文的书名号、技能括号等加粗内容使用 `<strong>…</strong>`，避免插入空格或修改正文。参见 [GFM 强调规则](https://github.github.com/gfm/#emphasis-and-strong-emphasis)。
