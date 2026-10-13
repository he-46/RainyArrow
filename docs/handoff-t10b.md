# T10-B 交接：两阶段、移动护板与弱点

2026-10-09。本包完成，下一轮仅 **T10-C：Boss奖励与反馈**。当前 T01–T08、T10-A/B 已完成，T10-C、T11–T13及T09尚未实现。使用Godot4.7.2标准版和类型化GDScript，入口Play.cmd；本轮无需新依赖。

## 实际玩法和参数

沿用用户规则：每100普通靶击倒出现Boss，逐次更强，入场普通靶自动碎裂且不发收益，Boss活着不刷普通靶，胜利后同局重新生成普通靶。Boss仍不计普通击倒/十次奇遇。首轮960HP/20甲，后续血量增加首轮60%、甲+6；基础1200分/240金币，后续增加首轮50%。

第一阶段本体静止；金色核心宽50、高24逻辑像素，箭头中心在带内才算弱点，大箭擦边不扩大资格。弱点伤害×1.75，再计算暴击、护甲和剩余生命，护甲=max(本体甲−12,0)。复制stats作本次计算，不修改母箭或局内属性。首轮本体甲20、弱点甲8。

活体HP≤最大HP50%仅一次切换第二阶段，不回血：本体上下sin(clock×1.7)×24；护板位于本体左52，相对本体上下sin(clock×2.3)×48。护板12×46、本体46×124，全部轴对齐，绘制和实际扫掠一致。护板甲=本体+8，穿甲严格高于它才能穿过；等于也阻挡。护板不扣BossHP、不暴击、不触发分裂/金币/经验/回复；整发只打护板属于无有效命中。玩家可以等护板移开，用低穿甲箭直接打弱点。

参数全部在BossRules/data/boss_rules.tres，入场保存parameters快照；以上为可调开发基线，未完成长期平衡和音效听感验收。移动边界参数限制在SaveStore，改配置范围时同步验证规则。

## 接口和命中去重

ArcheryTarget.collision_volumes()返回Array[Dictionary]，每项slot/part/rect；receive_contact委托原receive_hit。ArcheryBoss同属archery_targets，World.targets仍仅普通靶，boss独立nullable。

Boss实体slot=-1；碰撞部件body=-1、shield=-2、weak=-3。Arrow按每个实际rect最早接触排序，保存命中slot；核心/本体的excluded_slots=[-1,-3]保障同一箭共享生命只扣一次，护板只排除-2，因此贯穿后可命中核心。弱点矩形外侧突出2像素，先于本体接触；擦边中心不满足弱点时按本体伤害处理。

分裂出口依据实际接触部件rect；护板can_split=false。主箭穿过有生命的部件时仍可分裂，两支子箭继承母箭排除，不能再打同一Boss生命，子箭不再分裂。反弹不清除命中排除。六原特性可一起使用、无新互斥。死亡实体保留到整族在途箭和待结算收益结束，胜利仍由原record_boss_defeat沿整次拉弓结算一次。

World._on_hit将is_boss和可选boss_part存入pending_volleys；shield事件零伤害/零收益，SaveStore拒绝伪造护板收益、暴击或击倒。excluded_slots和can_split只是即时碰撞结果，不作为奖励字段保存。共享生命event_id仍bossN，护板bossN:shield，但护板无奖励。

ArcheryBoss.phase_changed发2一次；World显示蓝色提示并复用现有音效，HUD显示阶段、弱点倍率/甲、第二阶段护板甲。伤害浮字在巨靶左侧，护板文字再上移18逻辑像素避免同次贯穿文字重叠；阶段提示与入场文字错开。完整视听反馈仍由T10-C处理。

## v9与旧战兼容

SaveStore.VERSION=9。Run boss_schema仍1，world projectile_schema仍1。新增Boss字段combat_schema、battle_phase、phase_clock、parameters、body_position、shield_position，与HP/奖励、在途箭/部件排除、pending、ledger、RNG原子保存。保存参数避免后续平衡修改悄然改变正在打的Boss。

SaveStore要求新封套Boss有combat_schema，校验阶段与活体HP阈值一致、有限计时、参数范围，以及按保存clock/参数重算的本体与护板位置。死亡允许一阶段瞬杀或二阶段死亡，tick死亡冻结，不能读档回血、发奖或补普通靶。

World.upgrade_snapshot在处理旧projectile_schema之前升级Boss。v8源原字节保存.legacy-v8；已开始的静态Boss补combat_schema=0、phase1/clock0，保持原HP/甲/奖励、普通靶规则、旧箭hit_slots与原RNG。旧战使用原receive_hit，包括原靶心资格，无新弱点增伤/护板；HUD明示旧版静态。击败后下一次新Boss使用schema1两阶段。不重复迁移或重写同版档。旧v1–v7路径、未来版本保护与损坏恢复保持。

## 验证

tools/run.ps1 -Mode Test：**908断言/0失败**，新增tests/test_boss_combat.gd62项。覆盖弱点/暴击/护甲、一次阶段切换、真实护板接触/阈值/分裂、六特性整族与反弹去重、移动/穿过护板的在途继续、非法位置/阶段/参数拒写、v8原字节与老箭续战、实际HUD/技能/大厅/教程隔离。tests/test_boss.gd体部测试改为中心+40避免新弱点；v7迁移封套期望使用SaveStore.VERSION。

非headless --script res://tests/test_boss_combat_window.gd -- --test-mode：**21断言/0失败**。实际箭命中960→443切阶段，穿甲28阻挡、29通过弱点HP268；护板移开后0穿甲打到HP101。磁盘Continue保存HP268/7次、第二阶段与两部件原位置。日志.tools/boss-combat-window.log。

artifacts/t10b-{phase-one,phase-two,shield-blocked,shield-passed,weak-exposed,continued,small}.png七张已检查，1280×720/960×540无裁切或遮住拉弓区域。最后提示位置调整后重新捕获并复验。窗口fixture冻结物理，用真实Arrow扫掠控制接触；一般鼠标拉弓由此前test_boss_window覆盖，本包不声称完成持续鼠标操作平衡试玩。全部使用user://tests，未改玩家存档，无遗留窗口。历史T10-A窗口16/0和先前各包记录留存validation.md。

## 下一轮T10-C入口

先读expansion-plan.md T10-C，只做胜利有限拉弓回复、安全构筑奖励、反馈/音效和局内记录。复用已有奇遇目录、固定候选与奖励队列，明确普通十次与Boss奖励来源，不再造第二套去重系统；未选奖励必须阻止终局，最后一箭致死先发奖励/回复/选择再判断耗尽。T12-B再扩展已选特性强化，T13才做金币购买补给。

奖励扩展要沿整次拉弓与bossN去重，不能让本体/核心/护板各发一次。保留母子箭生命排除、死后族等待、暂停运动时点、旧静态战兼容与胜利补靶generation规则。新增保存字段需更新版本/验证和迁移；不能默认为v9已包含完整Boss选择。不开新奇遇、精通或补给包，完成C后停止并交接。
