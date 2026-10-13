# T01 交接：永久档案、局内状态与存档

状态：完成。下一任务为 **T02：品牌与导航外壳**，尚未开始。

## 交付范围

- `scripts/core/player_profile.gd`：累计击倒得分、等级、天赋点账本、天赋、装扮、设置与教程状态。
- `scripts/data/progression_rules.gd` + `data/progression.tres`：经验门槛配置。当前用于状态层验证，T03 再调平衡。
- `scripts/core/game_session.gd`：生命周期、永久/局内数据协调、世界快照、已结算检查点。
- `scripts/core/run_model.gd`：新增局 ID、初始次数、天赋快照、击倒计数与去重、难度步数、奇遇记录、暂停与结束状态。
- `scripts/core/save_store.gd`：v2 格式、结构校验、备份恢复、v1 迁移和未来版本保护。
- `scripts/main.gd`：现有原型接入会话；新开、继续、静音、保存和结束走新结构。
- `scripts/gameplay/archery_world.gd`：暂停的局不能继续消耗弹药或推进世界。
- `project.godot`：固定 `user://` 标识为 `AzVGames/ArrowsLikeRain`，显示标题留给 T02。
- `tests/test_session.gd`：T01 核心回归；`tests/test_runner.gd` 保留原型集成并加入新局保留档案检查。

## 可直接复用的接口

| 调用 | 行为 |
| --- | --- |
| `session.has_active_run()` | 判断是否有可继续的局，包括暂停局 |
| `session.start_run()` | 无活动局时新开；已有活动局返回 null，不偷偷重置 |
| `session.start_run(true)` | 明确替换旧局，保留档案，清空局内状态 |
| `session.resume_run()` | 恢复原局，返回同一 RunModel；不会补箭或刷新难度 |
| `session.return_to_lobby()` | 将局暂停；页面负责同步暂停场景树 |
| `session.end_run(reason)` | 结束并清空局内金币；重复调用不重复结算 |
| `session.record_defeat(event_id, points)` | 同时更新局内击倒和永久经验，按局内事件 ID 去重 |
| `session.capture_checkpoint(world_snapshot)` | 所有在场箭矢结算后，将档案和局内状态一起做快照 |
| `session.save_payload()` | 返回已结算快照；独立合入最新设置，不混入飞行中经验 |
| `profile.invest_talent(id, cost)` | 按真实成本记账；T05 的树服务负责先验证前置和互斥 |
| `profile.reset_talents()` | 返还真实投入，不按节点个数退款 |

`level` 和应得点数从永久累计得分派生；保存实际天赋投入账本，恢复时不重放升级事件。`grant_talent_points()` 重试不会重复发点。

天赋快照只复制已分配节点；本轮没有实现节点效果。T05 在开局时把快照解析为初始次数和属性。不能在局中直接引用可被大厅重置的 `profile.talents`。

## 当前玩法兼容

当前仍是原来的五关模式，规则标识为 `prototype_v1`。阶段分数保留 `score`，旧累计积分改名 `prototype_total_score`，旧关卡等级改名 `prototype_level`，局内购买记录改名 `skill_levels`，赐福改名 `encounters`。

永久档案不依赖这些旧字段，原型不会把命中得分发成永久经验。T03 接入 `record_defeat` 时，需要为每个目标生命周期生成稳定、可恢复的 ID，并为靶子配置击倒分值。不要把静态 slot 当成唯一 ID，否则重生靶不会重复计分。

击倒去重集合现在按局保存，满足原型规模；T03 的长局需要评估增长量，再决定是否改为有序事件序号。

## 存档与迁移

v2 payload 包含 `profile`、可为空的 `run`、`world`、`in_lobby`、`last_run_summary` 和 `migration`。

通过启动器运行时：`.tools/profile/Roaming/AzVGames/ArrowsLikeRain/save.json`。直接运行系统 Godot 时：`%APPDATA%/AzVGames/ArrowsLikeRain/save.json`。

新路径没有存档时检查同一 APPDATA 下的旧目录。v1 原文件与 `.bak` 保持原样，新路径另存原字节副本 `.legacy-v1`，迁移静音设置并保留可继续的旧局；旧积分不换经验。迁移过的新档优先读取，不再重复从旧档覆盖。

T03 切换连续玩法时必须显式处理 `prototype_v1`，不能把旧五关的 stage、金币和赐福当成新连续局直接解释。

写入使用临时文件和替换，保留上一份有效 `.bak`。结构损坏的原始文件在替换前另行保留；较新版本的主存档即使能读旧备份，也不允许当前版本覆盖。

飞行中的存档仍回到上一次齐射检查点。暂停可在内存保留飞行现场；本轮没有在途箭矢序列化。T06 实现奇遇中途退出时必须补足这一点。

## T02 接入要点

1. 页面导航只切换位置，不通过 new RunModel 伪造继续行为。
2. 首次启动的 `session.run` 可以为 null；大厅展示永久档案，去射箭才新开。
3. 暂停后继续复用当前世界；不要每次返回大厅后调用 `world.build_stage()`，否则会恢复靶子耐久。
4. 保存前仅在世界已结算时捕获新快照；其余情况写 `save_payload()`。
5. 读取 `saves.last_error` 和 `migration_notice`，新页面继续展示迁移/恢复说明。
6. 改显示名称时保留 `application/config/custom_user_dir_name`。

## 验证

命令：`powershell -ExecutionPolicy Bypass -File tools/run.ps1 -Mode Test`。

结果：**131 assertions, 0 failures**。包含鼠标按下/拖动/释放后的实射、商店/赐福/下一关，以及 UI 新开局保留档案的集成检查。

额外渲染并检查 `artifacts/t01-menu.png`。测试和截图分别使用独立的测试存档，不操作玩家档案。

当前受限执行环境偶尔输出无法读取 Windows 根证书存储的引擎日志；测试退出码为 0，当前单机游戏不使用网络功能。
