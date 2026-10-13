# T06 交接：奇遇基础系统

已完成；下一轮只执行 T07-A 联动特性，T07-B 转化另开一轮。T01–T05 交接保留为历史，本文件描述当前接口。验证日期：2026-10-09。

## 当前可玩内容

每累计 10 击倒获得一份奖励；一次拉弓的全部命中、金币、经验和回复先结算，再暂停三选一。跨多门槛依次领取，不能略过待选直接结束本局。三种当前实际资源为 windfall（丰收之风，金币倍率 +0.25）、rainfall（箭雨初临，每次箭数 +1）、second_wind（再挽弓弦，立即回复 3 次拉弓）。三种都无负面，可跨次叠加；目前只有这三种，所以每组三种全有，顺序随机。

左上奇遇按钮显示已选/待选次数。没有待领取时查看本局记录和下个击倒门槛，并暂停箭矢；有奖励则领取，按钮不会自行刷奖励。Esc 从历史返回射击，从三选一进入暂停页而不放弃奖励；回大厅或退出继续保留候选与飞行。正式失焦暂停保留。

## 数据与候选规则

新增 EncounterData、EncounterCatalog、EncounterRules，资源在 data/encounters/，门槛配置 data/encounter_rules.tres。资源含 id/title/description/group/is_trait/has_debuff/additions/draws/color。additions 为持续加法，draws 只在选择时即时给予；特性联动和转换需要 T07 的专用字段与运行规则，不能仅填普通 additions。

EncounterCatalog.draft(rng,seen,pool) 总是先保留一个非特性且无 debuff 的普通项，其他槽位排除重复 ID/组，再随机排列。常驻三种普通作为耗尽填补，目录资源优先于可选池的重复 ID。展示过的特性立即追加 seen，未选也移出本局池；普通不会加入 seen，可跨轮重复。实际特性尚未加入，tests/test_encounters.gd 用 8 个样本验证同组/含 debuff/未选择/池耗尽等规则。

## 权威状态与领取

RunModel.record_defeat 按 floor(defeated_count / kills_per_reward) 与 encounter_rewards_generated 比较，差额累加 pending_encounters；只入队，不立即改变 phase。GameSession.settle_shot 在整次拉弓所有命中、永久经验、金币、概率回复结束后 offer_encounter。World._settle_shots 随后看到 CHOICE 停止，保留后面的 pending_volleys。

offer_encounter 仅 PLAYING、非 suspended 且 pending>0 时可用。choices 为空才 draft，并递增 encounter_offer_id；当前组不再重抽。choose_encounter(id,offer_id) 校验 phase/权限/队列/候选/当前 token，记录 encounter_picks[id] 次数并扣一份、清旧 choices、应用即时 draws、重算持续效果；有下一份立即再次进入 CHOICE，否则 PLAYING。

EncounterPanel 卡片闭包捕获本组 token；主界面传 {id,offer_id}，防止快速连点旧按钮在下一组再次领奖。结束或放弃冒险时 GameSession 清 choices/pending，避免终局被保存成选择页。旧原型 encounters 列表仍仅用于 UpgradeData 兼容，现代 encounter_picks 独立，不要混写。

属性顺序：基础 → 开局天赋 → 旧档技能/祝福 → 新奇遇 additions → 六类新技能加法 → 数量技能伤害乘数 → clamp。普通 +1 箭不追加数量技能的 0.85 代价；六类技能各自规则保持。即时回复只在领取执行，读档/重算不重复。Arrow.stats 为发射快照，选择不会改变在场箭；金币倍率由 RunModel.record_defeat 在之后的结算统一应用，包含已在飞行但未结算的击倒。

## 暂停与存档 v6

main._refresh 在 SHOP/CHOICE/奇遇历史暂停 SceneTree，UI ALWAYS，世界 PAUSABLE。World._physics_process 在推进 clock/reload/目标前结算已完成拉弓；若进入 CHOICE，立即返回，保证保存时目标位置与 clock 一致。主界面 _settle_shot 在弹出时取消未扣次数的拖弓并立即捕获完整世界。

v6 / encounter_schema=1 保存 encounter_picks、encounter_rewards_generated、encounter_offer_id、pending_encounters、choices、seen_encounters 和精确 RNG，连同上一版所有在途箭矢与命中队列。选择、弹出、大厅、购买与退出均保存；恢复不生成新候选。World 同时等待在途箭矢、pending_volleys、pending_encounters：零次数在领取完成后才终结，选择回复可以继续；已完成但尚未结算的后发拉弓继续按编号处理。

SaveStore 校验数字类型/非负整数门槛计数、已选+待选不超过生成份数、固定候选身份/组/安全项和 CHOICE 状态。v5 先原字节另存 .legacy-v5；缺 schema 的旧击倒建立已处理门槛基线，25 击倒继续到 30 只发一份，不补发以前两份。v1–v4 的备份、旧技能祝福和在途迁移保留。旧原型 CHOICE 清未选祝福并回 PLAYING，已选加成不丢。

## 验证

tools/run.ps1 -Mode Test：449 项断言、0 失败。新 tests/test_encounters.gd 覆盖门槛/多份队列、候选保底与展示去重、旧 token 拒领、实际效果叠加、23 击倒一次完整结算、真实在途暂停与移动靶时钟、固定候选保存/恢复、真实卡片选择与历史、最后一箭回复/不回复、终局清理、非法存档拒写及 v5 迁移；T01–T05 保留。

实际渲染并查看 artifacts/t06-choice.png、t06-encounter-log.png、t06-play.png。choice 预览现在显示真正三选一，result 才显示结果页；预览不改变玩家档。卡片说明在添加文本前设置换行/宽度，避免 Label 单行最小尺寸溢出。没有声称完成长时间压力或完整平衡/音效听感。

## T07-A 接入建议

1. 在 EncounterCatalog.ALL 加实际特性资源：贯穿分裂、反弹增速、箭数提升暴击率。配置 is_trait/group/has_debuff，继续遵守普通保底和展示移出；不要开放尚未实现的卡片效果。
2. 箭数提升暴击率从原始来源统一重算，不在射击事件里累改共享资源。为 T07-B 保留原始属性 → 联动 → 转换 → 有效属性的明确顺序。
3. 在场箭矢使用发射时特性快照；Arrow 当前只有 BowStats 快照，需新增运行效果和对应 snapshot/restore，选择新特性不能回写旧箭。
4. 分裂子箭归属同 shot_id，但需独立 source_id/来源链、每次拉弓/每箭的生成预算与分裂次数限制。World.pending_volleys 必须等待子箭，hit_id 不能与母箭冲突，不允许无限递归。现有 hit_slots 防同次飞行重复靶位，子箭继承范围需明确定义。
5. Arrow.struck 返回 pierced，Arrow.bounced(point,normal) 可接增速；不要在普通金币/经验结算里再发一遍击倒奖励。若在 signal 中追加/删除箭矢，核对 Physics 遍历与保存边界。
6. 有新运行数据时升级存档并保留 v6 精确迁移，特别是 CHOICE 固定候选、待结算队列和 RNG。卡片比较目前 EncounterData.comparison 适用普通加法；联动/转换需要统一的实际预览而非简单在有效值上加一。
7. 本轮停止在 T06。T07-B 的箭数归一、暴击率转穿甲和额外暴伤转反弹留另一轮；完整设置/教程/装扮仍待 T08。
