# T11-D 交接：二十四种奇遇与子箭收益

2026-10-09。T01–T08、T10、T11全部完成，下一轮只做 **T12-A：六类技能精通**。工程D:\AzVGames，Godot4.7.2标准版，Play.cmd可玩。先读本文、expansion-plan.md、tasks.md及game-design-v2.md；不要提前展开T12-B特性强化、T13金币补给或T14难度排行榜。

## 本包交付

EncounterCatalog.ALL=24：6普通、18特性，其中5项含代价；无新增互斥。原展示移出（未选也移出）、有效安全普通保底、短候选/保持构筑、固定offer/token/RNG与Boss仅安全普通池继续有效。

| ID / 名称 | 默认效果 | 边界 |
| --- | --- | --- |
| branch_harvest / 枝上丰收 | 子箭直击或回响击倒金币+50% | 母箭不加，基础分数和击倒数不加，同靶奖励只一次 |
| branch_ricochet / 继枝借壁 | 子箭继承余下反弹后+2次 | 最多32次，母箭不加，子箭不再分裂 |
| slender_gale / 瘦箭疾风 | 尺寸×0.7、初速度×1.25 | 真实碰撞随尺寸变，最终尺寸0.5–6、发射速度200–1000 |
| heavy_draw / 慢弦重箭 | 伤害×1.4、装填时间×1.35 | 最终伤害最多100万、装填时间0.15–3秒 |

新资源在data/encounters，六个系数在EncounterRules/data/encounter_rules.tres，是开发默认值。EncounterData.requires_trait对两种子箭项指定piercing_split；RunModel.encounter_has_gain供抽取和领取共用。未取得分裂不得出现或绕过按钮领取；已经展示但没选的分裂仍移出，子箭项不提前记为已见。瘦箭/重箭预览比较完整有效速度/伤害，已封顶就不进新候选，不能只给负面代价。已选历史解释仍保留效果。

## 属性与母子快照

RunModel.calculate_raw_stats先合成基础/天赋/旧加成/技能/普通奇遇、数量减伤与普通伤害百分比，再应用两种代价因子各一次；随后按原联动→归一→转穿甲→转反弹→有效上限。基础资源不修改，重复重算或读档不复利；之后技能继续从来源重算。卡片显示真实尺寸/速度或伤害/装填得失，历史增加四项解释，大小技能仍显示尺寸与广锋正中的条件增伤。

ArrowEffects增加child_gold_bonus（默认0）和child_bounces（默认0）。RunModel.projectile_effects按发射时已选项冻结；World._on_split令child.remaining_bounces=min(32,parent.remaining_bounces+parent.effects.child_bounces)。母箭预算/角色反弹不增加；旧母箭在新选择之后才分裂仍使用旧参数。子箭保留原半伤害、拉力、剩余寿命、速度、已命中/范围排除与局部状态继承，不复制未完成出口；总预算仍32主箭+64子箭，整次最多96来源，不能递归分裂。

## 收益来源与结算

World._on_hit仅在broken且arrow.parent_source_id>=0且冻结child_gold_bonus>0时，给待结算事件加parent_source_id/child_gold_bonus。直接击倒和子箭回响击倒均可；母箭、非致死和护板不加。目标基础reward_gold不变；GameSession.settle_shot在既有金币收益因子上乘(1+child_gold_bonus)，继续由event_id/credited_defeats去重，整次家族结束才结算。分数、经验、普通击倒进度和天赋回复沿用原入口。

实际测试：两个8金币/40分靶，被子箭直击及回响分别击倒；两层丰收之风=×1.5、枝上丰收=×1.5，每靶18金币，两靶36金币/80分/2普通击倒。母箭未致死不获额外收入，重复事件不加奖；最后一发等所有家族，结果保留收入36而局内金币清零。浮字附“枝丰”，回响比直击上移18逻辑单位，避免相邻奖励文字重叠；浮字/圈等瞬时表现继续不重播。

Boss仍只有共享生命，每箭最多扣一次，母箭命中过的Boss生命部件由子箭继承排除。子箭不能靠从该Boss出生后再击倒同一个Boss来刷加成。新测试的Boss奖励边界用接触前构造的合法子箭做真实击倒，只验证来源账本能正确结算Boss基础奖励×系数、只发一次且不推进普通门槛，不代表正常Boss战可以反复分裂刷共享生命。百次出现、血量×3、两阶段、护板、战利品队列和有限补给保持。

## 存档接口

SaveStore.VERSION=15，Arrow.combat_schema=3；world.projectile_schema仍1，Boss.combat_schema仍1/旧0、health_revision仍2。旧v14先保存.legacy-v14原字节，箭schema2→3补两个中性字段；原八参数、暴击/贯穿/反弹层数、待用回声、范围排除/待出口/分裂、位置/速度/属性、装填、奖励来源队列、旧固定choices/token和RNG保持。旧schema1及更早沿原迁移链再升3，不再次放大Boss血量或补历史奖励。

当前写入要求两字段齐全且有限、child_gold_bonus在0–2、child_bounces与remaining_bounces整数0–32。带子箭奖励标记的事件必须同时有合法母来源和正系数、致死且effective>0，不能是护板；母编号须小于命中来源且来源在该次预算中。World.build_field还原JSON母编号为int，保证来源身份稳定。缺字段、NaN、越界、分数反弹、伪造母编号/非致死加成拒写，保留好档。

新家族磁盘测试中elapsed的0.07+0.04经Godot JSON可由0.11000000000000001变成0.11。测试只对elapsed允许≤1e-12误差，其余快照字段严格一致，继续后的物理与RNG一致；旧v14迁移快照逐值保留。不要把JSON声明为所有浮点均逐位相同。

## 验证与画面

- tools/run.ps1 -Mode Test：**1325断言，0失败**，本包净增88项；.tools/test.log。
- tests/test_branch_traits.gd覆盖24/18/5目录、240种seed的分裂前置/安全池、18特性展示一次、无安全收益不消费RNG；来源因子/后续升级/转换/上限、真实小箭擦边和发射装填、余下预算0/8/31/32及实际反射/既有反弹机制、96来源、不递归；直击/回响来源去重、Boss边界、最后一发、磁盘继续/固定候选/RNG、冻结旧箭/v14原字节迁移及损坏拒写。
- tests/test_branch_traits_window.gd：**51断言，0失败**，.tools/branch-traits-window.log。四项真实按钮领取、旧箭/装填不变、真实分裂/击倒/额外反射、磁盘Continue、技能条件预览、历史、整次结算和结果正确。
- artifacts/t11d-{child-choices,child-choices-small,cost-choices,cost-choices-small,children-born,child-kills,continued-family,child-bounced,cost-skill-preview,history,history-bottom,history-small,premium-settled,result,result-small}.png，共15张逐张检查；1280×720/960×540卡片说明、数值与按钮可读，12项卡片布局及相邻直击/回响浮字分行断言通过。
- 全部使用--test-mode与user://tests隔离，未读写玩家进度，捕获进程已退出。长期平衡、声音听感、极限同屏与正式桌面导出仍待T09。

## 下一轮T12-A

基础六类技能满级后出现独立精通层，不直接无限拉高基础等级。独立配置成本、有效收益和递减曲线；数量先改善减伤效率，暴击100%及箭数/尺寸/反弹封顶后提供明确分支补益。保留归一和两种暴击转化的来源；购买预览与实际属性同源，无收益或不可负担不扣钱。旧基础等级与旧箭保持，精通只影响后续发射；新增持久化状态推进当前v15并备份迁移。

其后T12-B全部18特性有限强化/Boss免费强化，T13有限金币补给；T14-A困难普通靶HP×1.5、Boss×2、得分×1.5，地狱继承HP倍率/更高成长（开发默认+10%）且总得分普通基准×2；T14-B三模式共用本地正单局分前三，保留3条、结束入榜、暂停/零分/教程不入榜及同局去重。上述后续包均未实现。
