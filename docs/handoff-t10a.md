# T10-A 交接：Boss 出现与生命周期

2026-10-09。T01–T08、T10-A已完成。下一轮仅 **T10-B：阶段、护板与弱点**。自动846/0（新增64），真实窗口16/0，六张截图已检查。新增奇遇/精通/强化/补给、T10-C完整奖励和T09验收尚未开始。

## 实际行为与数值

按普通靶真实击倒在100、200、300……出现铁弦巨靶。门槛到达后停普通补靶和新拉弓；整族箭/待结算击倒/正常奇遇先处理。入场碎裂清除所有普通靶，取消旧补靶，只有Boss实体。清场不计击倒/金币/经验/回复。超过门槛的真实击倒保留，99→102入场后下一门槛仍200。

静态Boss在逻辑(470,205)，轴对齐46×124，slot=-1，视觉与矩形头部碰撞一致；中央带仍按Target原靶心判定，没有新增弱点增伤。首轮960HP/20护甲/1200基础得分与经验/240基础金币；之后每轮加首轮生命60%、护甲6、首轮奖励50%（第二轮1536HP/26甲/1800分/360金）。金币继续享受原倍率/连击/靶心。参数集中data/boss_rules.tres，尚未完整平衡。

击败按整次拉弓入账一次，增加run.score/defeat_score、profile.total_score/等级/点数和本局金币；不增加普通击倒数、普通累计击倒或难度/十次奇遇。已有击倒/暴击天赋仍共用每次最多回复一次。T10-A无额外免费拉弓或构筑奖励，T10-C接入；最后一发Boss死亡先领奖后耗尽，有天赋回复则继续。胜利后重新生成普通靶，不恢复旧目标，沿用当前难度/天赋布局与同局资源。

HUD左侧下个Boss进度或战斗限制，上方独立Boss名称/轮次/HP/护甲/血条。main._process更新健康条，不重建技能/奇遇面板。Boss伤害浮字放实体左侧，基本反馈复用现有声音。多阶段反馈仍待B/C。

## 接入点和顺序

RunModel.BOSS_RULES静态资源，字段boss_round（含旧档历史基线）、bosses_defeated（实际胜利）、boss_next_defeats、boss_active。boss_due()推导，begin_boss()只推进门槛和状态，不自己发changed；World在创建实体/清场完成后统一发changed/volley_settled。record_boss_defeat核对活动状态及bossN身份，用credited_defeats去重，仅发分与金币。普通record_defeat在Boss期间拒绝。

ArcheryBoss继承ArcheryTarget，同属archery_targets，所以Arrow父world过滤、圆形扫掠、严格大于护甲贯穿、离靶分裂、反弹与同槽排除继续生效。Boss配置创建独立TargetData、不调用普通成长数值；继承tick只维护flash/死后计时，没有普通spawn。restore先配置再继承恢复，最后重设46×124shape。snapshot保存round_number和Target采样数值。

World.targets只包含普通靶，boss为独立nullable ArcheryBoss。_advance_boss只在无箭/无pending_volleys/无pending_encounters且PLAYING时入场或回普通场。Boss已0HP但未结算必须保留，不提前移除。World.snapshot包含boss或null、field_generation。清场取所有旧靶generation最大值+1；胜利build_field沿此generation重建并以run.difficulty_step采样，防止复用slot-life导致新靶奖励被旧账本拦截。没有目标时_origins直接返回空。

World._on_hit仅在Boss命中加is_boss=true。GameSession.settle_shot选择record_boss_defeat，沿原金币/连击/回复路径；PlayerProfile.record_score抽出经验授予，record_defeat仍先增加普通累计击倒再调用它。终局摘要新增bosses_defeated。TutorialController创建world.boss_enabled=false，避免无限练习触发Boss；正式Boss练习期间DISABLED保留。

## v8存档与兼容

封套v8，Boss局内schema1；projectile_schema仍1，箭本体无新增字段。run保存轮次/胜利数/下一门槛/活动状态，world保存boss实际HP/护甲/奖励和field_generation，pending命中可含is_boss。全部与原在途族/ledger/固定奇遇/RNG原子保存。活动Boss必须有同轮实体且targets空；非活动Boss不能残留实体；门槛必须=(round+1)×100。v8读取及新写入要求boss_schema，避免缺字段导致重复入场。未来版本保护、损坏恢复不变。

v7升级前原字节另存.legacy-v7；缺boss_schema的旧局以floor(普通击倒/100)建立历史轮次，下一整百开始。例如250击倒下一门槛300、轮次基线2、实际胜利0；进入后第3轮强度。不会补历史Boss、补金币/经验/箭、重抽固定候选或施加特性到旧箭。v1–v6继续原迁移与备份。当前旧测试两处v7硬编码改为SaveStore.VERSION/当前封套读后不重写；真实v7迁移由新测试覆盖。

## 验证与文件

tools/run.ps1 -Mode Test：846/0；tests/test_boss.gd64新断言。真实射击100/200门槛、清场、99→102贯穿齐射、非致死与多箭胜利、受伤+在途精确磁盘恢复、死亡未入账+在途恢复、普通新靶ID、最后一次耗尽/天赋挽救、v7基线、非法事务、实际HUD/技能/大厅/继续/教程均覆盖。

非headless --script res://tests/test_boss_window.gd -- --test-mode：16/0。截图artifacts/t10a-{progress,boss-entry,boss-damaged,boss-continued,boss-small,field-returned}.png；实际鼠标真实命中960→820，磁盘继续保持820/9次，三箭胜利重新补三靶。1280×720及960×540画面检查通过，浮字遮挡修正后重新捕获。全部测试user://tests，玩家存档不变；进程已结束，无遗留窗口。

## 下一轮 T10-B

只加两阶段、移动护板与可命中的弱点，不生成普通靶，不做完整奖励/奇遇/精通/补给。当前Boss一个槽位-1；多部件必须设计独立命中身份与共享生命去重，不能简单给全部部件相同slot导致先碰护板后无法命中本体，也不能每个部件都发Boss奖励。同步调整待结算来源、母子箭已命中排除、范围伤害未来接入和保存验证。

优先轴对齐移动护板，视觉与实际扫掠一致；若加入旋转形状，应明确新碰撞实现及迁移，不能仅转绘制而仍当未旋转矩形。保存阶段、部件、计时/位置及在途箭。已有v8活动静态Boss读档要有明确兼容处理，不能升级后无声回血、重复奖励或重新发初始次数。

成长强度/可达100的节奏、后期金币/耗箭与音效听感尚未验收，由后续包完成。不要把首轮960/20作为最终平衡参数。
