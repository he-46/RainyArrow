# T11-C 交接：二十种奇遇与有限范围命中

2026-10-09。T01–T08、T10、T11-A/B/C完成；下一轮只做 **T11-D：枝上丰收、继枝借壁、瘦箭疾风、慢弦重箭，20→24项**。先读本文、expansion-plan.md、game-design-v2.md、tasks.md。工程D:\AzVGames，Godot4.7.2标准版，Play.cmd可玩；不展开精通、金币补给或难度排行榜。

## 当前四项与资源

EncounterCatalog.ALL=20，6普通/14特性，无新增互斥。新data/encounters四个资源都is_trait=true/无debuff；展示移出、普通保底、短候选/保持构筑、Boss仅安全普通、固定offer和队列保持。

| ID / 名称 | 默认参数 | 边界 |
| --- | --- | --- |
| charged_breach / 蓄势穿甲 | floor(pull×8)，半拉4/满拉8 | 本箭局部穿甲，和反弹加甲/超甲组合，仍严格大于才贯穿 |
| bullseye_wave / 靶心回响 | 半径140逻辑单位，最多6靶/脉冲，主命中effective×40%再减自身甲 | 每箭每靶一次，总范围槽最多16；不暴击、不连锁、不触发出口/分裂 |
| critical_flow / 锋锐回流 | 后续伤害每层+12%，最多5层（+60%） | 真实有效暴击之后叠层，当前不提前增伤，暴击转换归零不触发 |
| broad_precision / 广锋正中 | max(size−1,0)×15%，连续计算，最高+75% | 箭头中心靶心条件，与Boss核心共享判定；大箭擦边无加成 |

配置在EncounterRules/data/encounter_rules.tres。ArrowEffects新增八字段charged_penetration、bullseye_radius/damage/targets、critical_damage/limit、size_bullseye/limit；默认未选全0，RunModel.projectile_effects只为已选冻结系数。新四项不改变BowStats来源/原始→联动→归一→穿甲→反弹→clamp。卡片预览、历史解释和大小技能靶心增伤预览已接入；描述压缩为三行，避免压数值区。

## 接触与奖励接口

Arrow.contact_stats复制发射属性，加floor(clamped_pull×charged_penetration)与bounce穿甲，仍限100万。非盾伤害依次乘穿靶层数、已有暴击层数、当前超甲、待用回声、中心尺寸因子；Target/Boss继续负责拉力、Boss弱点、暴击、目标护甲、实际HP封顶。真实暴击的effective>0结果才叠critical_stacks，回声照旧有效命中消耗，原穿靶出口同边界先叠层再分裂保持。

新的Arrow.area_requested(arrow,primary,global_point,damage,penetration)在主struck之后发出，damage为本次实际HP伤害×40%（过量伤害不会增大回响），penetration为本次charged/wall后的穿甲。World._on_area按同world稳定目标顺序/活体/中心距筛选，排除primary和已area_slots，不消耗战斗RNG。Target.receive_area以pull1、crit0、bullfalse、自身本体甲结算，最低1沿用CombatMath，标damage_kind=area/piercedfalse/can_splitfalse，直接World._on_hit绕开Arrow触发管线。

普通靶保留各一次实际箭头接触和范围接触，area_slots不占普通hit_slots；因此以后真正命中邻靶仍可产生一次新的脉冲，已范围受伤槽不会再次受伤。子箭继承母箭已得critical_stacks/area_slots/拉力/冻结参数和旧动态状态，不继承未完成出口；不同子箭可影响尚未范围受伤的目标，预算仍原32主/64子、无递归分裂。

次级账本hit_id为shot:source:area:event，主接触保持原shot:source:event。基础击倒按event_id和credited_defeats一次结算，非击倒不给分/金币；次级critical/bullseye=false，不能制造暴击回复或靶心金币。真正范围击倒可触发正常击倒回复，仍整次拉弓一次回复上限/连击结算。最后一箭等全部家族与收益后结束。

Boss.receive_area只用本体甲，没有核心×1.75或弱点降甲，返回[-1,-3]生命排除；World加入hit_slots，后续实际接触也不能再扣共享血。护板不是范围目标；正式Boss场内没有普通靶，自己的核心脉冲只显示圈，不额外命中自身或盾。Boss首轮仍2880HP、health_revision2，阶段/移动/奖励队列规则未变。

area_rings淡出0.45秒和“回响”伤害浮字仅表现，不保存；真正死靶/HP、范围排除和账本保存，继续不回放伤害或收益。没有增加新的正式音频素材，使用现有命中/击倒音效，听感仍待T09。

## 存档与兼容

SaveStore.VERSION=14，Arrow独立combat_schema=2，增加critical_stacks/area_slots；World.projectile_schema仍1，Boss combat_schema仍1/旧0、health_revision仍2。升级旧v13先保存.legacy-v13原字节；Arrow.upgrade_state把schema1转2，补八中性参数、零暴击层、空范围槽。原T11-B七参数、局部层数/回声/重叠出口、分裂出口、stats/速度/位置/拉力、装填/账本/队列、固定choices/token/RNG保持。旧更早缺schema先补原T11-B中性字段再转2，旧Boss×3迁移仍只一次。

_valid_arrow_combat允许旧schema1读取但当前封套/write要求2，必须齐全八参数，有限且在界；critical_stacks<=frozen_limit，范围槽最多16/整数/唯一/-1或非负，不能为盾-2或核心别名-3。非空范围要求启用radius/damage/targets，Boss−1要求hit_slots包含−1/−3。次级事件只能area/effective>0/noncrit/nonbull/noshield、独立:area:身份，拒绝损坏事务而保留好档。

## 验证与截图

自动 **1237/0**，比T11-B净增95；tests/test_precision_traits.gd，完整tests/test_runner包含。原生 **45/0**，tests/test_precision_traits_window.gd；所有12张截图已逐张检查。详见validation.md、.tools/test.log、.tools/precision-traits-window.log。覆盖真实蓄力阈值/动态穿甲组合、首次暴击与五层上限/分裂/归零、尺寸中心和Boss、有限范围/无递归/RNG/来源/护甲、最后一箭范围击倒和读档继续/一次得分金币进度、四真实按钮和冻结老箭、v13原字节归档/旧飞行保持/非法事务拒写。

截图artifacts/t11c-{charge-wave-choices,charge-wave-choices-small,crit-size-choices,crit-size-choices-small,wave-hit,continued-flight,critical-split,size-preview,history,history-bottom,history-small,boss-core}.png。1280×720/960×540卡片不压预览，历史滚动和按钮可用；真实首轮Boss核心暴击扣612.5，HP2267.5（显示2268），脉冲无额外生命事件。测试使用user://tests，不改玩家档；捕获进程已退出。未宣告长期平衡、压力、导出或完整音效验收。

## 下一轮注意

T11-D子箭增益需明确parent_source_id>=0，并且已具备piercing_split才进入候选；先查看EncounterCatalog.draft当前过滤只处理普通gain，不能仅新增资源而遗漏资格门槛。枝上丰收需明确实际子箭直击和子箭回响是否同享，基础击倒event依然一次；奖励来源标记需进入保存的明确账本，不把表现字段当依据。继枝借壁增加子箭remaining_bounces及预算，但不得再次分裂，保存和恢复后一致。瘦箭疾风/慢弦重箭在原始属性源或明确转化阶段推导一次，后续升级仍有有效预览，老箭/当前reload不追溯修改。新持久状态必须版本化、归档旧v14并保留所有T11-C冻结值/层数/范围排除/待出口。

后续顺序T11-D→T12-A/B→T13→T14-A/B→T09-A/B/C。T14困难普通HP×1.5/Boss×2/分数×1.5；地狱继承血量倍率、更高靶子成长（初版默认10%，普通6%）、总分按普通基准×2已确认；三模式默认共用总共3条本地单局榜，正分终局入榜/暂停零分教程不入/同局去重。仍未实现，不能当作本轮可玩内容。
