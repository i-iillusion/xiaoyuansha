# 本地无窗口回归（Windows）

使用与 CI 一致的 Godot 4.7.2，在仓库根目录运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File Test/run_headless.ps1 -GodotPath 'C:\path\Godot_v4.7.2-stable_win64.exe'
```

脚本不下载引擎、不启动交互游戏、不提交或推送。它将当前工作区的
`Scripts/Scenes/Test/project.godot`（含未提交和未跟踪的非忽略文件）复制到
Git 元数据目录的 `local-ci/<唯一运行号>/project`；保留源文件哈希、基线提交、
工作区状态、引擎哈希、导入和七组测试各自的标准输出、标准错误及 `results.json`。
不复制 `.godot` 缓存、PDF 或个人文档；未来增加其他资源目录时须同步扩充复制清单。
源项目存在 `override.cfg` 时拒绝运行，避免静默忽略已有自定义配置。

只有隔离副本使用 `headless_override.cfg`：关闭 stdout 的逐条强制刷新，正常退出
仍保存全部输出，stderr 始终刷新。Godot 官方说明该调试版默认设置可能影响大量
输出时的性能，见 [ProjectSettings](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-property-application-run-flush-stdout-on-print)。
被强制终止时 stdout 尾部可能未刷新，因此超时始终判失败，即使已经出现成功 RESULT。
不改正式 `project.godot`、生产逻辑或 Linux CI。

Windows 本地捕获通过 `ProcessStartInfo` 启动无窗口进程，并行将 stdout/stderr
原字节流异步复制到缓冲日志文件，退出后等待两条流写完，再检查退出码与日志。
不经过 PowerShell 逐行管道，也不直接将引擎输出句柄指向磁盘文件。
[WindowsTerminalLogger 源码](https://github.com/godotengine/godot/blob/master/platform/windows/windows_terminal_logger.cpp)
显示调试输出逐条调用 `FlushFileBuffers`；仅关闭上面的普通 stdout 刷新设置仍不足以
避免直接文件句柄的磁盘刷新成本。2026-10-04 同机诊断中，200次独立print从约1.4秒
降至约1.9毫秒，标签更新约9毫秒；完整七组核心从超时恢复为19.240秒、3399断言通过。
日志内容、七组、错误规则和120/60秒限制保持，退出及流写完的耗时均计入原限额。
历史超时日志保留；此测量不承诺任意主机的固定耗时。

验收门槛不变：导入 120 秒，每组 60 秒；退出码为 0、每组唯一且正断言数的
`RESULT: N asserts, 0 failures`、无脚本错误/ERROR/Parse Error/FAIL、没有超时。
导入失败不启动测试；某组失败仍记录后续各组，整体退出 1。脚本保留所有隔离副本
和日志，不自动删除历史证据。使用含 `%` 或双引号的引擎/仓库路径会明确拒绝。
