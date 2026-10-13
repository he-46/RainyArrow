# T07-A 交接：三种联动特性

已完成；下一轮仅执行 T07-B 持续转换，T08 设置/教程/装扮另开一轮。验证日期 2026-10-09，507 项断言、0 失败。本文件替代 handoff-t06 的当前接口，历史交接保留。

## 玩家可见内容

EncounterCatalog.ALL 现含三种普通与三种唯一特性。piercing_split（一箭生枝）每支主箭首次贯穿并离开远侧后生成 2 支伤害 50% 的 ±12° 子箭；ricochet_haste（借壁生风）每次反弹乘 1.25、限速 2000；swarm_precision（雨密锋锐）每支额外发射箭 +2 个百分点暴击率。前两种不赠穿甲/反弹次数，卡片明确前置条件；分裂子箭不增加发射箭数暴击加成。

现有候选保底、展示即移出（不论是否选中）、固定 offer 和 ordinary 可重复规则保留。draft 的 fallback 只放常驻普通，可选 pool 自己提供特性；正式 offer 传 ALL，测试样本不会无意混入实际特性。

卡片使用 RunModel.encounter_comparison / preview_encounter，普通 +箭数也展示联动后的暴击；技能数量卡购买前后暴击额外一行。历史中显示 swarm 原暴击 +额外箭数×2% =有效值（上限100%）。已查看五种真实渲染截图 artifacts/t07-trait-{choice,linkage,shop,flight,log}.png，日志无错误。

## 原始属性与有效属性

calculate_raw_stats(levels,picks)：基础 → 开局天赋 → 旧档加成 → 普通奇遇 additions → 六技能加法 → 数量伤害乘数；返回未经联动/转换/clamp 的新 BowStats。

_effective_stats(raw,picks)：复制 raw → swarm 使用 clamp(raw.arrow_count,1,32) 的额外发射箭数 → **T07-B 转换插入此处** → 最终 clamp。calculate_stats 与 preview_skill / preview_encounter 都走同样流程；不回写基础 Resource 或永久抹掉原始值。projectile_effects() 返回独立 ArrowEffects 数值快照，发射时按箭复制。

数值在 data/encounter_rules.tres（分裂数量/角度/伤害、速度乘数/限速、每箭暴击）中；World.MAX_SPLIT_CHILDREN=64 是硬限制。EncounterData.trait_key 为特性标识（`trait` 在当前 GDScript 是保留字，不要用作变量）。转换资源可沿用 trait_key，但仅完整实现后才加入目录。

## 分裂与事件来源

Arrow 首次 pierced 消费 split_spent 并保存 split_pending 与撞击时的扩张矩形 split_exit_rect。SweepMath.boundary 求离开体积的事件，与靶子和边界接触按最早时间排序；远侧出口才 signal split_requested。若未离靶就暂停/退出，恢复继续待触发一次。撞击矩形是移动靶瞬间快照，不跟随后续移动；重叠靶仍按更早碰撞处理，提前停止的箭不再分裂。

World._on_split 保留母箭、添加两支同 shot_id 子箭，递增独立 source_id 与 parent_source_id；子箭继承 stats（伤害×0.5）、pull、hit_slots、elapsed、remaining_bounces、增速效果，但 split_count=0 /split_spent=true。不同子箭可以各自命中尚未在其排除列表中的靶；同靶击倒只由 RunModel 的生命 ID 入账一次。

projectile_ledger 每个 pending draw 保存 next_source 与累计 children。单次最多 32 主箭+64 子箭=96，已经结束的子箭仍消耗预算；整次结算后删账本。Arrow 各自物理执行，回调追加箭不遍历同一 Array；测试手动步进时用 arrows.duplicate。待结算拉弓等待所有主/子箭结束，再按 shot_id 顺序交 GameSession，天赋回复仍共享单次上限，子箭不多扣拉弓机会。

反弹后才乘速度/限速，同帧余下运动继续；墙角双轴翻转只消耗/增速一次。ArrowEffects 数值和当前速度均持久化，选择/购买不会改变在途箭和后续产生的子箭。

## v7 存档

新增 projectile_schema=1、projectile_ledger 与箭的 effects /parent_source_id /split_spent /split_pending /split_exit_rect。保存来源/预算、待出口和已消费状态，恢复不重复生成或重置预算。SaveStore 校验唯一来源、0–95 source（旧无编号箭归组 0 允许更大来源范围）、64 子箭预算、子箭禁递归、数值类型、唯一特性选择一次并已见。build_field 将 JSON 的账本数字转为 int，保证精确快照一致。

GameSession.from_dict /from_legacy 调用 ArcheryWorld.upgrade_snapshot，无 schema 的世界补无特性 ArrowEffects 与根来源/预算；空世界保留空，缺 shot_id 的更旧箭归 0。v6 原字节备份 .legacy-v6，已显示普通卡片原样保留，RNG/资源/已见状态不重抽/补发。v1–v5 原迁移回归保留。

## 验证与范围

tools/run.ps1 -Mode Test：507 项断言、0 失败，新增 tests/test_traits.gd 的 58 项。覆盖真实池、数量持续联动、前后预览、离靶前后恢复、半伤害/扇角/继承/不递归、真实母子击倒80XP/16金币只发一次、最终耗尽、96族群预算、反弹即时/限速/墙角/加速命中、相等护甲与无反弹预算、实际 UI 卡片/下一发快照、非法保存及 v6 精确迁移。

原 T06 的普通效果测试先标记实际三特性为已见，保持固定普通样本；测试真实池另在 T07，不能拿这种样本当玩家真实池。此前简单预览 EncounterData.comparison 已移除，统一用 RunModel，不要另写加一公式。

没有完成 T07-B 转换、T08、完整平衡/性能压力/正式音效听感。反弹与子箭仍按同次全部结束才收益结算，长飞行可能延迟购买与补靶，T09 评估。

## 下一轮 T07-B

1. 添加箭数归一换伤害/大小、暴击率全转穿甲、额外暴击伤害转反弹资源；含代价标记，保留普通保底与展示去重。不要抢做 T08。
2. 在 _effective_stats 联动之后插入转换，明确一次性固定顺序；联动读取归一前的受限发射箭数，使原始箭数升级仍有收益。完整的 raw → linkage → conversion → effective 解释用于奇遇与技能预览/历史。
3. 每 2 个百分点暴击率换 1 穿甲，转换后暴击率为0；每 20 个百分点超出普通100%的暴伤换1反弹，200%倍率额外100%必须为5次，转换后倍率回1。注意浮点下取整误差。
4. 归一的伤害与大小系数尚未在用户设计中定数，可用合理可调默认值继续；保留数量技能原伤害代价与现有有效上限，明确 rawcount 超32时只按32处理，避免积累无限换算。
5. 同时持有联动与转换、后续购买、重复重建、子箭继承已转换快照、存档与旧固定 offer 必须验证。新增资源不改原在途箭，是否升封套取决于新增运行状态，不为无字段变化盲目迁移。
