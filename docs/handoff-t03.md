# T03 交接：连续靶场、击倒成长与永久等级

已完成；下一轮只做 T04 六类技能与箭矢机制。

## 本轮可玩变化

- 删除固定五关、积分达标过关、关末自动商店和旧等级赐福流程。没有固定胜利上限，拉弓次数耗尽且所有箭矢结清后结束。
- 命中只扣血，击倒才统一发分数、永久经验和本局金币，同时推进难度；靶子生命 ID 去重，读档也不会重复奖励。
- 死靶等 1.4 秒后补充；新生命采样当前难度，增加血量、护甲值、分数与金币，在场靶子保持生成时数值。
- 永久累计经验按 100/250/450……升级，每级 +1 天赋点；HUD 展示击倒、经验进度、得分和可用点数。
- 左上角技能可手动打开旧升级面板，齐射结束后才能进入；关闭不补箭、不重建靶场。奇遇显示待开放。
- 结果页显示本局击倒、得分、累计赚取金币、起止等级和获得天赋点；局内金币清空，永久档案保留。

## 关键接口

- `ArcheryWorld.build_field(snapshot)` 替代 build_stage，仅新局/首次恢复时使用。
- `ArcheryTarget.spawn(data, difficulty)` 在现有槽位补充下一生命，增加 generation，更新数值与碰撞体。snapshot 保存 kind/max_hp/hp/armor/reward_score/reward_gold/spawn_difficulty/generation/respawn_left。
- `defeat_id()` 为 slot + generation。Arrow → World.target_defeated → main → GameSession.record_defeat(id, points, coins)。coins 乘 RunModel.stats.gold_multiplier，分数为生成时固定奖励。
- GameSession.record_defeat 先校验并更新局内去重/资源，再更新 profile，发 `defeat_recorded(id)`，最后刷新 UI。后续回复天赋可连接此信号并调用 `run.restore_shots(amount)`。
- World 等全部 arrows 清空才 settle_volley。回复在耗尽判断前发生，pending_encounters 为后续奇遇保留暂停结束条件；零箭已结算存档加载后也会自动进入结果。
- `RunModel.open_skills / close_skills` 替代 continue_run/advance_stage/choose；main 负责确保世界已结算。T04 如果要允许在途购买，必须同时解决存档事务问题，不能混用旧箭矢快照和新购买。
- RunModel 的 stage/旧 WON/CHOICE 编号仅用于老档布局和终态兼容，连续流程不递增 stage。

## 数据和边界

`data/field_rules.tres`：每击倒新靶血量 +6%、奖励 +8%，每 5 击倒 +1 护甲，1.4 秒补靶。木环靶 48 血/40 分/8 金，铁箍 95/60/12（基础护甲 2），游走 38/50/10。已有目标不重采样。木环开局，5 击倒后补靶轮换现有种类。

T03 只配置护甲成长，**尚未用于减伤/贯穿**；`BowStats.pierce` 仍是原型次数，T04 要替换。六类技能、弹射/尺寸精确碰撞不在本轮。CombatMath 不再提供 score/gold_value；靶心是命中标记，后续金币天赋可以利用，但不能再把伤害当经验。

回复接口经测试可挽救最终一箭，但尚无玩家可选的回复天赋；T05 负责接入。天赋页文案已说明点数获得并保留。

## 存档 v3

v2 首次导入在写入前另存 `.legacy-v2` 原字节。保留永久档案、旧局剩余次数、金币、已选升级/赐福、旧靶血量与布局；旧商店/未选择赐福归一到 PLAYING，未领取旧候选移除。旧命中积分不变成永久经验。v1 仍原字节归档并同样转成连续规则，原文件不修改。

场景恢复优先读取目标快照中的生命代数和采样值；老快照缺字段时按旧 stage/kind 恢复原血量上限，再为后续补靶使用新规则。终态不复活。飞行中退出仍回到上一已结算检查点；不要提前标记为精确在途存档。

## 验证

`tools/run.ps1 -Mode Test`：181 项断言、0 失败。已移除旧五关验收断言，替换为连续流程，新增 `tests/test_continuous.gd`。

覆盖连续 60 次击倒不自动过关/结束、非致死命中不发金币经验、真实致死箭结算、补靶成长与在场靶不变、死亡检查点重载去重、生命代数/完整数值快照、真实最终多箭贯穿结清 3 个击倒、最后一箭跨级保存、同步回复挽救本局、空箭存档不挂起，以及 v2 迁移原字节备份/资源保留。

实际 OpenGL 渲染查看 `artifacts/t03-play.png`、`t03-shop.png`、`t03-result.png`、`t03-tutorial.png`，字体、布局正常。沙箱引擎日志仍有系统根证书读取错误，离线测试/渲染成功。没有做正式平衡、长期压力或音效听感验收。

## 下一轮建议

先实现六类独立技能数据和属性重建，再改 CombatMath、Arrow、ArcheryTarget 的护甲/穿透/反弹/尺寸逻辑，最后替换 HUD 技能卡片。保留本轮真实多箭、最终结算、去重、快照及导航回归；不要以击中次数代替击倒，也不要用技能面板打开/关闭刷新世界。
