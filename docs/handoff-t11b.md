# T11-B 交接：十六种奇遇与箭矢局部构筑状态

2026-10-09。T01–T08、T10、T11-A/B 已完成。下一轮只实施 **T11-C：蓄势穿甲、靶心回响、锋锐回流、广锋正中**，16→20项。先读本文、expansion-plan.md、game-design-v2.md；不展开T11-D、精通、金币补给或T14难度/排行榜。工程D:\AzVGames，Godot4.7.2标准版，双击Play.cmd可玩。

## 新特性与配置

EncounterCatalog.ALL=16，6普通+原6特性+新增4特性，无新增互斥。展示就移出、普通安全保底、短候选/无收益确认、Boss仅安全普通、固定offer与来源队列全部保持。新的独立资源在data/encounters，参数在EncounterRules/data/encounter_rules.tres：

| ID / 名称 | 默认值 | 触发边界 |
| --- | --- | --- |
| piercing_edge / 越靶越锋 | 后续伤害每层+15%，最多5层（+75%） | 有效HP命中且实际贯穿；完全离开捕获体积才叠层，护板不触发 |
| armor_surplus / 破甲余势 | 每点超甲+2%，最多+100% | 每次命中当前部位独立计算，无永久累乘，Boss弱点使用降甲后的护甲 |
| echo_strike / 回声重击 | 反弹后下一次伤害+50% | 真实反弹刷新一次待用状态，连续反弹不叠加；有效HP命中消耗，护板不消耗 |
| wall_forging / 借壁破甲 | 此箭每反弹穿甲+3，最多5层（+15） | 墙角一次，局部穿甲总值仍限100万，不改角色原始或发射属性 |

效果采样在RunModel.projectile_effects；未选择的参数为0。新四项不改变BowStats来源和转换管线，卡片Comparison显示配置系数，Description解释上限/护板/继承/需要反弹，History复用现有滚动布局。命中实际受到动态伤害加成时浮字带“强化”，该表现字段不入奖励账本。

## 真实接触时序

Arrow.stats保持不可变发射快照。contact_stats复制后计算局部穿甲，再乘穿靶层数、此次穿甲余量、待用回声；Target.receive_contact继续负责拉力/弱点/暴击/护甲/HP封顶。不同动态机制相乘，同类层数相加；伤害增幅受各系数/层数上限约束，不修改角色100万基础伤害上限。原始→数量联动→归一→暴击转穿甲→暴伤转反弹→clamp保持。新一次拉弓从零局部状态开始，暂停选择不改老箭。

ArcheryTarget.contact_armor(point,part)默认本体甲；ArcheryBoss覆盖，用同一箭头中心弱点判定降甲，shield返回shield_armor，combat_schema=0静态旧战用本体甲。护板结果effective=0，因此不消耗回声、不排穿靶出口、不分裂，也不增加生命收益/暴击。Boss的[-1,-3]共享生命排除保持，-2护板独立排除。

每次有效贯穿捕获penetration_exits=[{slot,rect}]。重叠靶子各自保存体积；每步把所有待出口与目标接触、边界、原split_exit一起排序。接触时不加层，完全离开捕获矩形才增加penetration_stacks；同边界优先增加层数，再发split_requested。即使击倒使实体消失，也按捕获矩形等箭头穿出。hit_slots避免返程和Boss别名重复叠层。

真实反射同时更新bounce_stacks/echo_ready，先扣一次剩余反弹，角点两个法线只触发一次，原借壁生风速度提升继续生效。继承函数Arrow.inherit_combat只复制已获得层数和待用回声，未完成的母箭出口不交给子箭；子箭仍为半基础伤害、继承冻结参数/命中排除/剩余反弹/寿命，无递归分裂。此实现没有额外消耗RNG，原每次接触一次roll保持。

## 存档 v13

SaveStore.VERSION=13；projectile_schema仍1，Boss combat_schema/health_revision不变。箭矢新增自己的combat_schema=1、penetration_stacks、bounce_stacks、echo_ready、penetration_exits，ArrowEffects新增七参数。World.upgrade_snapshot先逐箭Arrow.upgrade_state，再处理原早返回/旧projectile来源迁移。

升级v12先归档.legacy-v12原字节，再为缺箭combat_schema的旧箭补零层/未待用回声/空出口和七个中性参数。旧五效果、stats、速度/位置、split状态、命中排除、账本/队列/装填、Boss实体/已发奖励与固定choices/token/RNG都保留，新目录只用于后续抽取。旧v11的箭势渐盛转换提示仍保留，旧Boss×3迁移继续只执行一次。重复读当前版不迁移、不复利、不发新奖励。

当前封套和write要求新箭状态齐全；_valid_arrow_combat校验版本、有限参数/整数上限、层数<=冻结上限、echo待用资格、出口数量+已用层数<=上限、唯一且已命中槽位、不为护板、正面积且有限矩形。旧版无该状态允许读取后补中性；有状态但损坏不会静默修复。拒写不覆盖好档。JSON出口slot恢复时转int，模拟快照保持数值身份；测试对未实例化JSON世界做数字类型归一比较，真实模拟快照仍直接逐值比较。

## 验证与产物

最终 **1142/0自动断言**（比T11-A净增96），**31/0原生窗口断言**，十二张画面逐张检查，无脚本错误。新增测试tests/test_penetration_traits.gd及原生tests/test_penetration_traits_window.gd。测试用user://tests隔离，不改玩家档，捕获进程已退出。覆盖真实重叠出口/首次未增强/第二靶增强/七靶五层封顶、返回同槽位不重复、实际反弹/角点/速度联动/回声消费、借壁加甲真正穿过但相等仍停、Boss核心/本体/护板/旧静态甲、原六持续转换与十特性实际Boss家族、同出口母子顺序/半基数/不继承未完成出口、冻结旧箭/未来新箭、磁盘中途继续与后续确定性、v12原字节归档和固定选择/RNG保持、损坏参数/层数/出口/回声拒写。详见validation.md。

窗口日志.tools/penetration-traits-window.log，截图12张artifacts/t11b-{penetration-choices,penetration-choices-small,surplus-echo-choices,bounce-choices,bounce-choices-small,pending-exit,continued-exit,split-inheritance,bounce-combination,history,history-bottom,history-small}.png。覆盖实际原生按钮、四效果共存/旧箭不变、待出口磁盘恢复、分裂继承/真实反弹、历史与1280×720/960×540排版。长期平衡、正式音效听感、压力和导出仍留T09。

## 下一轮注意事项

T11-C增加蓄势穿甲时，必须使用保存pull/发射系数，先参与当前局部穿甲与余势判定；后续购买不得改老箭。锋锐回流根据实际有效暴击结果叠层，穿甲转换把暴击率归零时不伪造触发。广锋正中不扩大中心弱点判定。靶心回响使用独立有限范围来源，不能递归调用自身，也不能让Boss核心/本体/护板重复扣同一生命或制造盾收益。明确范围伤害与回声/穿靶/分裂的触发边界，扩展新的局部状态必须版本化并备份旧档。

T14-A/B仍待T13后：困难普通HP×1.5、BossHP×2、分数×1.5；地狱继承血量倍率、更高靶子成长（初版默认10%对比6%），用户已确认总分按普通基准×2。默认三模式总共3条本地单局榜，标注模式、正得分终局入榜、同局去重，不能用永久总分替代。此轮未实现。
