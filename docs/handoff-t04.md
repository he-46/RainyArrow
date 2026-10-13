# T04 交接：六类技能、护甲、体积碰撞与反弹

已完成；下一轮只执行 T05 四棵永久天赋树。T01–T03 交接保留为历史记录，本文件描述当前状态。

## 当前功能

六类独立可重复购买技能为数量、暴击、伤害、穿甲、弹射、大小，无前置锁。每类有独立初价/上限，价格每级乘 1.5 向上取整。UI 显示实际生效前后值、金币不足和满级。

数量每级 +1 箭、单箭伤害乘 0.85；暴击每级同时 +5 个百分点率和 +0.25 倍率；伤害 +8；穿甲 +2；反弹 +1 次；尺寸倍率 +0.35。数据在 data/skills/，规则类型为 RunSkillData，目录 SkillCatalog.ALL。

RunModel.calculate_stats(levels) 从基础资源复制，先兼容旧档加成，再累加新技能，最后计算数量伤害乘数并限制边界；预览和购买调用同一个计算函数，不依赖购买顺序。T05 的天赋快照效果应在此建立明确的基础/加法/乘法顺序。不要直接修改共享 BASE_BOW。

## 护甲与箭矢

CombatMath.resolve_hit 增加 armor 参数：先计算拉力/暴击伤害，再减 max(armor - armor_penetration, 0)，最低 1，上限为剩余 HP。返回 pierced = armor_penetration > armor，击倒不会额外授予贯穿，贯穿后不衰减。

BowStats 使用 armor_penetration 与 bounces，旧 pierce 次数字段不再用于新箭矢。旧资源中 stat=pierce 仅在 _apply_legacy 中转换。

Arrow 用 SweepMath 对圆形箭头扫掠轴对齐矩形目标，半径为 2 * arrow_size；箭杆/羽毛为外观。侧边与圆角分别求接触时间，避免扩大包围盒导致圆角假碰撞。当前不支持旋转靶子，T05 的靶子大小必须保持 collider 与可见尺寸一致。

场地为逻辑 Rect2(8,54,624,254)，在靶场绘制边线。按最早接触顺序处理目标或场边，贯穿/反弹后继续本物理步剩余时间。反弹只反转法线对应速度分量，墙角同时翻转 x/y 并消耗一次预算；同次飞行不再命中同一 slot（即使期间该槽位补靶）。重力每段按消耗时间更新，位置碰撞在 120 Hz 步的位移弦线上处理。

每箭最多飞行 12 秒，每步最多处理 64 次接触；超预算结束箭矢，避免极端连锁卡住。Arrow.bounced(point, normal) 为后续反弹联动保留事件；struck 的 hit 字典含 pierced/critical/bullseye/broken，T05 可据此接暴击回复，T07 可接穿透分裂。

## 飞行中技能与存档 v4

技能面板现在可以在箭矢飞行时打开。main._refresh 根据 SHOP 暂停 SceneTree；UI ALWAYS，世界/箭矢 PAUSABLE。回大厅或暂停页继续保留 SHOP，回靶场后仍显示技能面板；close_skills 才解除暂停。取消拉弓不扣次数。

购买只重建 RunModel.stats；在场 Arrow.stats 是发射时副本，不可回写。Arrow.snapshot/restore 保存位置、速度、拉力、已飞行时间、原属性、剩余反弹次数、命中槽位。World.snapshot 还包括 reload_left、waiting_for_settle、direction、所有目标和箭矢；恢复共享 run.rng，目标先恢复，再恢复箭矢。低于 0.1 秒的补靶倒计时也必须原样恢复。

main._save_checkpoint 在非拖弓状态下捕获完整世界，不再只允许已结算。正常退出先取消拖弓，再保存。购买、返回大厅、正常退出、齐射结算保持永久经验/金币/箭矢原子一致；异常终止恢复最后一次成功写入。不要将“在途精确恢复”误写回上一轮的回退语义。

SaveStore VERSION=4，读取 v2/v3 先原字节备份 .legacy-v2/.legacy-v3，v1 保留原机制。RunModel.skill_schema=2：旧 skill_levels 转入 legacy_skill_levels，保留旧加成；旧贯穿次数按 1:1 转穿甲，新六类从 0 级开始。这样旧 critical（只加倍率）不会错误变成新 critical（率和倍率一起加）。旧奖励仍由 GameCatalog 兼容，不出现在新技能面板。新局清空两种账本。

T06 的待选奇遇与触发事件仍未实现；本轮只提前完成其依赖的在途箭矢基础快照。

## 验证

命令 tools/run.ps1 -Mode Test，结果 221 项断言、0 失败。tests/test_skills.gd 验证六类预览/购买/上限/重算、穿甲相等边界、护甲最低伤害、暴击结算顺序、斜撞/墙角/一帧多次反弹、贴墙起步、反弹后同帧命中、同靶去重、高速大箭擦边、靶心公平、真实 UI 购买、飞行中暂停及重载旧箭属性、恶意结构拒写、v3 原字节迁移和幂等加载。T01–T03 连续靶场/永久成长/导航/最终结算回归保留并更新新规则。

实际 OpenGL 查看 artifacts/t04-play.png、t04-shop.png、t04-pause.png。已检查六类卡片布局与文案；未声称完成长时间压力测试、旋转目标支持、正式平衡或音效听感验收。沙箱环境仍有系统根证书读取错误，不影响离线测试和渲染。

## T05 起步

先做独立 TalentData/TalentCatalog 与树规则验证，再替换 page_router 的天赋准备页。复用 PlayerProfile 的消费/真实支出退款账本；在大厅更新只改变 profile，当前局坚持使用 run.talent_snapshot。新局统一套用容量、伤害/穿甲、金币、目标数量/尺寸。

击倒回复连接 GameSession.defeat_recorded 并在最后箭矢结算前调用 restore_shots；暴击回复需从实际 struck 有效命中接入，不能仅凭 RNG 或箭数发放。金币树需要在统一击倒入口加入拉弓级连击和最后一击靶心信息；目前 World.target_defeated 只传 ID/分数/金币，扩展事件时保留去重。目标数量/大小需与生成布局、圆头扫掠和快照一致。
