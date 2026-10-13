# 架构与后续开发约定

## 依赖方向

main 组合 GameSession、ArcheryWorld、AudioService、SaveStore、PageRouter 与 GameHUD。core 不依赖 UI；界面只发 action 请求，不直接发金币或改成长。GameSession 持有永久 PlayerProfile 与局内 RunModel。

最新交接为 handoff-t16.md，下一轮 T09-A 完整流程与反馈验收。扩展计划见 expansion-plan.md，旧交接保留为历史，以最新接口为准。

## 统一击倒结算

T12-A/B已接入六类精通、18特性有限强化与Boss免费强化，当前封套v21（含神器背包、补给/消费、难度快照与T14-B排行榜事务）；下文早期任务的版本说明保留为迁移历史。精通不参与金币或得分发放，不改变整次家族结算入口。

Arrow 扫掠 collision_volumes → Target.receive_contact 扣血 → Arrow.struck → World._on_hit 保存命中事件并立即显示伤害。普通靶的 receive_contact 委托原 receive_hit；Boss按部件处理。World 为每次拉弓分配 shot_id、每箭分配 source_id，按拉弓编号顺序等待该次所有箭结束，再发 shot_settled → main → GameSession.settle_shot。后发的箭先结束时等待前面的拉弓，避免连击顺序错乱。

会话按 hit_id 去重，有有效命中才增加一次连击，整次落空清零。broken 才调用 record_defeat，按此前连击和最后一击靶心计算金币；RunModel 用 slot+generation 去重并应用全局金币效率，更新局内分数/金币/难度，会话同步永久经验。击倒与有效暴击按 run.rng 概率回复机会，共享 data/talent_rules.tres 的每次拉弓上限。last_settled_shot 阻止整次结算重复。defeat_recorded 兼容钩子仍保留，但新天赋回复集中在 settle_shot。

靶子补充时增加 generation，采样 FieldRules，固定生命最大血量/护甲/奖励。已有目标不因难度增长改变。死亡计时到期且该生命的击倒已入账才补靶，保证成长来源一致。World 在全部箭矢和待结算拉弓清空后判定耗尽，奖励/回复先执行，pending_encounters 延迟终结，最后一箭可先选择回复奇遇。长反弹箭会推迟这次拉弓的收益和补靶，T09 需评估这项体验。

## 属性计算和技能

RunSkillData、SkillCatalog、data/skills 独立定义六类局内技能，永久天赋与奇遇不得写入这里。RunModel.rebuild_stats 从 talent_snapshot 派生 talent_effects；calculate_raw_stats(levels,picks) 复制基础、加天赋伤害/穿甲/金币，再兼容旧档加成、累加普通奇遇与技能，最后数量伤害乘数，得到未改写的原始来源。evaluate_stats / _evaluate_raw 产生 StatEvaluation：raw → linked → converted → effective，各为独立快照。先按 1–32 的原始发射箭数联动（每支额外箭 +0.02 暴击率，子箭不参与），再依次归一、暴击率转穿甲、额外暴伤转反弹，最后 clamp。preview_skill_evaluation / preview_skill / preview_encounter 与实际重建同源，禁止分散累乘。

归一使用 source_arrows=N：发射数=1、伤害×pow(N,unity_damage_exponent)、尺寸×pow(N,unity_size_exponent)，当前参数 1.0/0.5。数量技能的伤害乘数在原始阶段保留。暴击来源为 clamp(linked.crit_chance,0,1)，每0.02换1穿甲，暴击率清零；额外暴伤来源为 clamp(linked.crit_multiplier,1,10)-1，每0.20换1反弹，倍率回1。两个转换相互独立，可与归一/数量联动叠加。_conversion_units 比值加1e-9后向下取整，稳定十进制阈值，不将明显不足的余数向上凑。

StatEvaluation 保存 source_arrows / crit_source / extra_crit_source 与实际新增穿甲/反弹，仅为推导值不写存档；raw、linked、converted 保留超上限来源/中间值，effective 才限制伤害100万、尺寸6、反弹32等边界。stat_explanations 用于历史和技能悬停；skill_comparison / encounter_comparison 显示有效收益，归一时不误报箭数1→1，转暴击时不误报升级无收益。

TalentData/TalentCatalog 与 data/talents 定义36个永久节点。根三阶、早期分支两阶、专精一阶、各路径进阶两阶及终极一阶；只在同树专精组互斥。PlayerProfile.invest_talent 校验目录、前置、互斥、满级和精确成本；真实花费另存 talent_spending，免费重置返还账本。恢复按树的拓扑顺序移除未知/孤立/冲突节点。GameSession 的购买/重置入口限大厅，新局复制天赋并只在开局设置初始次数；当前局重算和读档不补箭、不读取后改的永久树。

Arrow.stats 是发射时副本。新购买/奇遇选择的箭矢属性只影响之后的箭，金币倍率统一影响之后结算的击倒，GUI 打开时暂停世界，包括已飞行的箭。SHOP 是手动技能状态，CHOICE 是待领取奇遇；close_skills 不重建目标或补充弹药；WON 数字仅供旧档兼容。

## 奇遇队列与候选

EncounterData / EncounterCatalog / data/encounters 独立于旧原型 UpgradeData。现代已选次数保存在encounter_picks；旧encounters列表独立兼容。六种普通分别加0.25金币倍率、1箭数、即时回复3次拉弓、12基础伤害、3穿甲、每层5%伤害加成。用户要求原快手搭箭改为箭势渐盛，保留内部quick_nock ID，group改damage_percent，与基础伤害分组独立。damage_bonus通过资源汇总，calculate_raw_stats将基础/天赋/技能/普通加法伤害总和乘(1+各普通damage_bonus×层数总和)，再同源计算数量减伤及后续归一/封顶；两层为10%，不递归累乘。category_label供卡片/历史分类，encounter_comparison显示累计增伤及有效伤害，stat_explanations显示来源。即时回复只在领取时执行，重算/恢复不重放。

record_defeat 以 floor(defeated_count / kills_per_reward) 比较 encounter_rewards_generated，差额累加 pending_encounters，但不在击倒中途改变 phase。GameSession.settle_shot 处理完同次所有命中、经验和回复后调用 offer_encounter，生成固定至多三项并进入 CHOICE；没有安全普通收益时固定为显式确认。World 在推进时钟/目标前先结算已完成的拉弓；进入 CHOICE 后立即返回，剩余队列不删除，保存边界与目标移动位置一致。

draft 使用 run.rng，先保留一张非特性/无 debuff且有收益的普通项，再按不重复 ID/组选择其他槽位，随机排列；展示过的特性立即加入 seen_encounters，未选也移出本局池。六种普通资源补足耗尽池；可选pool指定实际特性，fallback只带常驻普通，同样受eligible回调过滤。原T07时ALL包含三普通、三联动（piercing_split / ricochet_haste / swarm_precision）和三含代价的持续转化（unified_arrow / critical_forging / critical_ricochet）。不足三项时停止填充；没有安全普通项时直接返回空数组，不消费RNG/未展示特性。

每次生成offer将encounter_offer_id加一。领取请求携带卡片捕获的offer ID，选择时校验当前CHOICE/大厅权限/待领取数/候选身份/实际收益/offer ID，防止连点旧按钮领取下一份。领取消耗一份队列，记次数、清旧候选、应用效果；仍有待领取则立即生成下一组，全部选完才恢复PLAYING。空候选保存offer_exhausted=true，can_skip_encounter检查当前组是否缺少有收益的安全普通项，skip_encounter同样校验权限/编号并消费一份来源；旧固定普通卡全部封顶也可确认，不改其候选/RNG或强迫代价。奇遇按钮不能创建门槛收益。

CombatMath 先拉力/暴击，后减未抵消护甲，最低 1，最高剩余 HP。贯穿资格严格为 penetration > armor，和是否致死无关，不消耗原型贯穿次数。

## 碰撞与坐标

逻辑靶场 640×360，世界 scale=2，UI 1280×720。实际反弹边界 Rect2(8,54,624,254)，箭头半径参与缩小可移动区域。每箭圆形头部为碰撞体（半径 2×尺寸），杆和羽毛不参与伤害；可见圆形箭头对应碰撞体。

SweepMath 对圆与轴对齐矩形做连续扫掠，分别求边与圆角的最早接触；不使用离散偏移射线或仅扩大矩形。当前目标不能旋转，统一父节点坐标下支持目标尺寸缩放。Arrow 按接触时间混排目标和边界，贯穿/反弹后继续本帧剩余时间。天赋数量/尺寸生成右侧网格，最多 15 靶或 2.3 倍尺寸；每个靶保存 anchor/target_scale，补靶沿用尺寸，移动靶限制在场内。血条和护甲文字保持可读大小。

反弹翻转法线分量，角落同时翻转两轴并消耗一次；借壁生风在反射后乘 1.25 并限速 2000，继续剩余帧时间。不赠反弹次数。每支箭用 hit_slots 防同次飞行重复伤害，保存后仍有效。每步上限 64 次接触，每箭寿命 12 秒，超过即结束。120 Hz 运动采用解析位移，碰撞在单步位移弦线上求解。

ArrowEffects 存发射时 split_count / split_damage / split_degrees / bounce_multiplier / speed_limit 数值，永不读取后来的已选特性。一箭生枝首次满足贯穿时消费 split_spent，并设置 split_pending 与该次撞击的扩张矩形；箭头离开远侧才发 split_requested，退出接触也与其他接触按时间排序。移动靶采用撞击瞬间体积；极端重叠靶会先处理更早碰撞，停止箭不再分裂。

World._on_split 给母箭保留本体，新增两支 ±12° /50% 伤害子箭，共享 shot_id、独立 source_id 并记录 parent_source_id。子箭复制发射属性与特性、母箭 hit_slots /剩余反弹/ elapsed，设置 split_count=0，不能递归或延长寿命。各子箭可独立击中尚未被该来源命中的靶；同一生命由 RunModel 去重收益。projectile_ledger 为每次拉弓保存 next_source / children，上限 64 子箭（32 主箭，共 96），结算清除账本；已过期子箭仍占用本次预算。pending_volleys 等待整族结束，再按拉弓顺序结算。

## 页面与时间

CosmeticData/CosmeticCatalog 位于data层，只包含ID/类别/名称/解锁条件/三配色/装饰样式，不含战斗字段。PlayerProfile.record_defeat 调 refresh_cosmetics 按永久level/total_defeats派生资格；恢复忽略供应的解锁列表，按真实进度重建，错类别/未知/锁定选择回默认。equip_cosmetic拒绝锁定和重复选择；main仅接受装扮页/营地状态的装备action，不收费、不重建RunModel。

CosmeticsPage 独立显示九张状态卡和当前搭配，CosmeticPreview/CosmeticDrawing 共用世界和箭矢的像素形状。ArcheryWorld.apply_cosmetics复制三个类别ID，更新现有根/子箭绘制资源，并在_attach_arrow对未来发射/分裂/读档箭应用同一外观。Arrow.cosmetic只参与_draw，不进snapshot；箭头仍以stats.collision_radius绘制，碰撞圆半径不受装饰影响。角色衣服/弓装饰/箭杆羽毛与轨迹改色不改输入、position、速度、伤害或RNG。

GameSession.save_payload 独立合并equipped_cosmetics；unlocked_cosmetics资格跟随战斗checkpoint中的经验/累计击倒，不混入较新收益。读档重建资格后应用装备到整个世界，包括旧在途箭。教程只复制装备到临时世界，重玩沿用，不拿临时等级解锁正式装扮。沿用v7，无新增持久化字段或Projectile schema。

TutorialController 仅拥有一次性 GameSession/PlayerProfile/RunModel/ArcheryWorld，不持有正式 session/SaveStore；TutorialPage 复用 GameHUD 与技能/奇遇卡，加四步指导。World.draw_released 是成功发射后的观察信号；真实 shot_settled 经临时 session 结算，再判断靶心击倒。练习单靶12血/100经验/24金币/1.4倍尺寸，失败刷新易靶并补回拉弓次数。瞄准阶段预标记已消费的奇遇门槛，防止大量未中靶心击倒卡进CHOICE；购买后明示补齐到下次十次门槛前，再真实击倒生成实际候选，所有演示只在练习 run。

main 进入教程先保存并 suspend 正式局，将正式 world.process_mode 置 DISABLED；仅隐藏不足以阻止其在教程解暂停时运动。教程临时 world PAUSABLE、页面与控制器 ALWAYS，升级指导/SHOP/CHOICE/完成或手动暂停冻结练习。modal 先 reset_shake，避免短震动被冻结在屏幕上。离开销毁临时 world/page，恢复原正式 process_mode、路由和历史开关，range 直接恢复同一对象（含结束页面，不自动新开局）。Arrow 连续碰撞已按父 world 过滤靶，练习不能击中正式靶。

完成事件只把正式 profile.tutorial_completed 置 true，GameSession.save_payload 与 settings 一样独立合并此既有字段；练习奖励、箭/RNG不写正式存档，保留v7。未完成跳过不标记，重玩不清已完成记录；退出程序保留正式冒险，练习进度不续存。失焦暂停教程，Esc 暂停/取消拉弓、M 共用设置与音频。

SettingsPage 独立构建三 HSlider 和四 CheckButton；发 setting{key,value}，main 使用 PlayerProfile.set_setting 严格校验并通过 _apply_settings 唯一入口应用/同步，set_value_no_signal/set_pressed_no_signal 防止循环。静音快捷键不重建页面。PageRouter.settings_return_route 独立记录入口，不覆盖 pause 的 range 返回，支持设置→暂停→靶场。设置也可从大厅直接进入。

AudioService.apply_settings 保留原总线 trim（Master−4/Bow−2/Impact−3/UI−5/Music−8dB）再加线性音量的 dB；零音量用有限下限且总线 mute，静音 flag 与音量零分开。project.godot 修正为 audio/buses/default_bus_layout，实际载入五总线。音乐暂无曲目，试听直接走现有 Bow 声部。

ArcheryWorld 在命中/击倒时产生短暂视觉震动，_update_shake 平移 viewport.canvas_transform，CanvasLayer HUD 不受影响；不改 Node2D.position/箭/靶/快照或战斗 RNG。_aim_position 抵消视觉偏移后映射输入，震屏关闭、离开靶场及销毁世界恢复 rest_canvas。轨迹只控制拖拽中的预览点，拉力条和弹道保持。设置字段原已存在，仍 v7；拖拽期间 save_payload 只合并最新设置，避免混入新收益。

PageRouter 同时只保留一个非战斗页面。首次进入靶场才创建世界，回大厅隐藏并暂停；继续复用原对象，磁盘恢复才 build_field。UI ALWAYS，World PAUSABLE。main._refresh 在 SHOP / CHOICE / 奇遇历史面板暂停 SceneTree，暂停页或大厅返回保持原 SHOP / CHOICE 状态。EncounterPanel 独立绘制三张卡或已选记录；Esc 从历史返回战斗，从选择页进入暂停而不放弃奖励。

## 存档 v16（兼容 v1–v15）

永久档案、局内资源和整个世界原子保存，包括目标生命/anchor/尺寸、采样数值/补靶计时、所有在途箭矢位置/速度/发射属性/寿命/命中过的槽位/剩余反弹/拉弓与来源编号、装填、pending_volleys 命中队列、shot_sequence/last_settled_shot/combo 和精确 RNG。恢复先目标后箭矢；角色拖弓取消而不扣次数。待结算命中只存明确的奖励字段，避免表现数据或数值类型混入恢复。

现代奇遇用 encounter_schema=1 区分旧祝福，保存 encounter_picks / encounter_rewards_generated / encounter_offer_id / pending_encounters / choices / seen_encounters 与 RNG，恢复过程不生成新候选。SaveStore 校验门槛计数、候选数/组/身份、普通保底和 CHOICE 条件；弃局清空候选与待领取，不能把终局保存为选择页。

main 在非拖弓状态可捕获完整快照；返回大厅、正常退出、购买、齐射结算、奇遇弹出与选择写入。弹出时取消未消耗的拖弓。不能混用旧箭矢和新金币/经验。异常退出只承诺最后一次成功保存。

v2/v3 首次升级前保存 .legacy-v2/.legacy-v3 原字节。RunModel.skill_schema=2 区分新六类与原型，旧节点放 legacy_skill_levels 按原数值保留；旧 pierce 1:1 转 armor_penetration，旧 critical 与新 critical 不混淆。GameCatalog.upgrades 仅用于旧档，所有新购买由 SkillCatalog 管理。

v4 首次升级保存 .legacy-v4 原字节。旧箭缺编号时归入 0 号拉弓，按恢复顺序分配 source_id，保留 hit_slots，不补建旧命中奖励；后续新拉弓编号从 1 开始。缺少 geometry 字段沿用旧 3/4 靶布局。未来版本保护与损坏恢复保留。

v5 首次升级保存 .legacy-v5 原字节；缺 encounter_schema 的旧击倒建立已处理门槛基线，不补发奇遇，之后到下一整十获得新奖励。旧原型 CHOICE 清除未选原型奖励并回到 PLAYING；已选旧祝福继续生效。

projectile_schema=1 保存效果数值、母子来源、已分裂/待离靶状态与出口矩形、每次生成账本；校验来源唯一、预算范围、子箭无递归能力、效果数字及唯一特性只能选一次。v6 原字节另存 .legacy-v6，旧固定候选与 RNG 原样保留。GameSession 通过 ArcheryWorld.upgrade_snapshot 为无 schema 的旧箭补无特性效果、根来源和账本；不把本局后选特性施加给旧箭。恢复账本数字转为整数，保持内存/磁盘快照一致。

T07-B 的持续转换只依赖已保存的技能/天赋/奇遇来源，不新增持久化状态，封套仍为 v7。旧 v7 的固定候选和在途 Arrow.stats 原样保留；未来发射才获取转化快照，子箭直接继承已转化母箭而不再次计算。SaveStore.write 使用 JSON.stringify(...,full_precision=true)，避免乘法生成的高精度伤害在磁盘中截断；已有旧字节不会由加载主动重写或补造丢失精度。

T10-A 新增 boss_schema=1 和封套 v8。RunModel 保存 boss_round/bosses_defeated/boss_next_defeats/boss_active，boss_due 由普通击倒数与下一门槛推导。旧档缺 boss_schema 时以 floor(defeated_count/100) 建立轮次基线，下一门槛为下一整百，不补战斗和胜利。v7 原字节另存 .legacy-v7；v8必需boss_schema，写入亦校验，不接受活动Boss没有实体或同时存在普通靶的事务。

ArcheryBoss 继承 ArcheryTarget 的连续碰撞接口，实体slot=-1、event_id=bossN；BossRules独立采样生命/护甲/基础奖励，不经过普通靶成长。World.targets只含普通靶，World.boss独立对象但同属archery_targets。boss快照与普通targets/全部箭/命中队列一起保存，目标先恢复再恢复箭；死亡未入账时保留0HP实体直到整次箭结束，不能读档回血或提前领奖。

T10-B 增加 collision_volumes() → [{slot,part,rect}] 和 receive_contact(stats,pull,point,roll,part)。普通靶仅有原slot的body；Boss有body=-1、shield=-2、weak=-3。Arrow按实际各矩形的最早扫掠接触排序；核心/本体命中返回excluded_slots=[-1,-3]，护板只排除-2，穿过护板仍可命中生命。分裂出口用实际接触部件的rect；can_split=false的护板不分裂。母子箭继承已命中部件，避免贯穿/反弹再次扣同一共享生命。

Boss 第一阶段无护板，半血仅切换一次到阶段2；活体tick按phase_clock驱动本体与护板，死亡冻结。核心按箭头中心是否在金色带内判断，不随箭头尺寸放宽；复制发射stats做局部伤害×1.75，护甲减少12，不改原箭属性。护板贯穿条件为penetration>body armor+8，没有伤害/暴击/回复/奖励。pending_volleys可保存boss_part用于命中语义，excluded_slots/can_split为碰撞即时结果，不入账。

v9要求Boss快照携带combat_schema/battle_phase/phase_clock/parameters/body_position/shield_position，参数在入场采样并随该战保留；SaveStore验证数值范围、HP与阶段关系、按保存参数重算位置一致性。combat_schema=0用于旧静态战：World.upgrade_snapshot补默认字段但保留HP/奖励/箭排除，receive_contact继续旧receive_hit，不引入新弱点或护板。v8原字节另存.legacy-v8，下一新Boss才combat_schema=1；版本迁移不改projectile_schema=1、不改变老箭快照和RNG。

到门槛停止补靶/新拉弓，先结清在途家族和已得奇遇，World._advance_boss在PLAYING且无箭/无pending_volleys/无待选时清除所有普通靶并创建Boss。清场只发cosmetic_rng碎片，不调用record_defeat。field_generation取旧靶最大generation+1；胜利后新普通靶用此编号和当前difficulty采样，避免新slot-life与旧已入账ID冲突。Boss期间不运行普通spawn，也不召唤普通靶。

待结算命中额外可选is_boss=true，Session.settle_shot转到record_boss_defeat。Boss入账使用同一credited_defeats和金币余数，不推进defeated_count/difficulty/十次奇遇；profile.record_score授予经验/等级而不增加普通靶累计击倒。原kill/crit天赋仍共享每次拉弓一次回复上限。入账后等所有在途箭结束才撤Boss/build_field重新生成靶，不发免费初始次数。切换立即发changed与volley_settled保证HUD及存档一致。教程world.boss_enabled=false，不改变正式Boss状态。

## T10-C 奖励队列、记录与血量调整

RunModel.record_boss_defeat沿原bossN/credited_defeats去重，记录实际乘算后的gold、得分和有限回复，再将{kind:boss,round:N}追加到reward_queue。普通门槛追加{kind:ordinary,round:0}；pending_encounters现在是所有来源的待领取总数，encounter_rewards_generated仍只计普通十次门槛。reward_source返回队首；普通走原目录，Boss仅用无负面普通项。offer_id、choices、choose_encounter和seen规则仍共用一套，Boss不移除未展示特性。选择消费队首并更新boss_reward_log.choice。基础奖励与回复在整次拉弓结算完成后发放，胜利选择未领取前World保留死亡Boss并禁止补靶。

boss_reward_log每次含round/score/gold/draws/choice，draws为按全局上限实际获得量，boss_reward_totals用于结果和summary。GameSession.end_run清空未领取队列但保留记录，主动放弃允许未选choice为空；旧胜利计数保留且无需伪造记录。UI显示安全战利品标题/实际收入，日志复用奇遇页面；AudioService提供6种独立合成Boss/护板提示，World碰撞反馈与main胜利入账反馈分开。

v10新增boss_reward_schema=1、reward_queue、boss_reward_log，Boss health_revision=2。v9源原字节备份.legacy-v9，旧普通pending合成为ordinary来源，不重抽固定choices/RNG；历史已入账Boss不生成补给/选择。ArcheryBoss.upgrade_state对缺health_revision的旧实体仅一次将hp/max_hp×3，保留剩余比例、阶段、部件位置与箭排除，新Boss采样2880基数。旧静态combat_schema=0继续原机制，兼容处理不再意味着旧血量不变。

SaveStore要求v10字段完整，校验队列长度、Boss记录的单调轮次/胜利身份/有限补给、每个未领取记录的唯一来源、Boss候选全为安全普通项；已入账的活动Boss必须0HP。候选/已选总量允许普通entitlement+本版Boss奖励数，不改变普通门槛计算。pending/来源/记录/世界/箭/收益账本一起原子保存；同版反复读取不调整血量或补发奖励。

## 数值和验证边界

T11-B：RunModel.projectile_effects 在发射时采样四种新系数/上限；Arrow.stats 始终保存原始发射有效值。contact_stats 复制 stats，先计算此箭穿甲=min(1000000,基础穿甲+反弹层数×加甲)，再乘 (1+穿靶层数×增伤)×(1+min(多余穿甲×系数,余势上限))×(1+待用回声)。Target.contact_armor 提供当前部位护甲，现代Boss按同一中心弱点条件降甲，旧静态Boss保留本体甲，护板只用局部穿甲判定通过而不产生伤害或消耗回声。伤害结算之后有效HP命中消耗回声；角色原始属性不改。

Arrow.penetration_exits 为每次有效贯穿捕获 {slot,rect}，支持重叠靶子；按本帧最早出口与目标/墙/分裂出口统一排序。命中时不加层，箭头完全离开捕获矩形才增加 penetration_stacks；同边界先加层后 split_requested。hit_slots 保持生命部件去重，护板无有效HP所以不入出口队列。bounce_stacks 在真实边界反射时增加，角点只计一次；echo_ready 只刷新，不跨反弹累乘。分裂子箭继承已应用层数/回声与冻结参数，不继承母箭尚未完成的穿靶，也不再分裂。表现标记 trait_boosted 仅用于浮字，不入奖励账本。

v13 为箭新增独立 combat_schema=1（与Boss同名但不同实体）、penetration_stacks/bounce_stacks/echo_ready/penetration_exits；projectile_schema 仍为1，原来源/预算规则不改。参数存 ArrowEffects 的七个新字段。升级旧箭补中性参数与零状态，保留原五参数和旧stats/分裂出口/排除/队列/RNG；ArcheryWorld.upgrade_snapshot 在早返回前逐箭升级。v12原字节归档.legacy-v12，后续不会重复补字段或改Boss血量。当前封套和写入必须有完整箭状态；校验有限参数/整数计数/上限、待用回声资格、出口正面积/唯一槽位/已命中来源且不为护板，拒绝损坏事务并保留好档。JSON恢复出口slot转int，使真实模拟snapshot保持一致。

T11-A首版采用v11封套，保存offer_exhausted无收益确认标记，Boss记录choice可为NO_GAIN（_no_gain），表示已确认保持构筑。SaveStore要求字段为bool、CHOICE空候选须显式exhausted且重新计算全部安全普通项确认确实无收益；短候选校验唯一组/普通保底，旧固定封顶卡允许保留。已消费Boss确认记录不能仍在奖励队列内。v10源字节归档.legacy-v10，再由已有字段恢复构筑/固定候选/来源/token/RNG和在途世界；health_revision=2的Boss不会再次扩大血量。

百分比增伤修订使用v12封套，不新增run或Arrow字段；v11原字节归档.legacy-v11，旧quick_nock次数改为每层5%伤害，未来reload回到基础与其他来源。固定choices/token/RNG保留；world中旧Arrow.stats和正在进行的reload_left原样，不因全局效果定义改变而追溯重算。迁移提示明确替换。反复读同版不累乘增伤，也不重复调整Boss血量。

encounter_has_gain对普通项比较evaluate_stats当前有效值与preview_encounter有效值，必须经过联动、归一、转换和最终上限；draws按100000拉弓上限独立计算。特性保留未来构筑承诺，不因当前无穿甲/弹射就筛掉。选择后的rebuild与预览同源；Arrow.stats和world.reload_left不改，下一次_release才采样新的装填时间。普通叠层恢复上限扩大到10亿以保留达到百万穿甲/伤害所需的超过十万次历史，实际属性上限没有提高。

FieldRules：每击倒新靶血量 +6%、奖励 +8%，每 5 击倒 +1 护甲，1.4 秒补靶；ProgressionRules 累计经验 100/250/450……，每级 1 点。技能成长见 data/skills，各上限与价格已配置，T09 才统一平衡。

## T11-C：条件伤害与有限范围来源

当前ArrowEffects额外冻结charged_penetration、bullseye_radius/damage/targets、critical_damage/limit、size_bullseye/limit八个字段。默认未选择为0；RunModel.projectile_effects只为已选项采样配置。contact_stats局部穿甲加入floor(clamp(pull,0,1)×charged_penetration)，再限100万；非护板伤害乘穿靶层数、已获得暴击层数、超甲、待用回声和条件尺寸因子。尺寸因子=min(max(size−1,0)×系数,上限)，仅target.is_bullseye(point)时生效。此方法与Target/Boss实际中心判定共享，圆形碰撞半径不扩大靶心区，角色来源管线不变。

真正HP命中后消耗回声；如果result.critical且effective>0，再增加critical_stacks供后续命中使用。当前暴击不提前加自身层数，护板与次级伤害不叠层，暴击转穿甲归零也不触发。Arrow.inherit_combat追加继承已得暴击层数和area_slots，仍不继承未完成出口。原同出口先叠穿靶层再分裂的顺序不变。

主命中先struck入账，再area_requested(arrow,primary,global_point,effective×系数,此次局部穿甲)。World._on_area在相同world内按稳定目标顺序筛活体中心距离，排除primary，最多6靶/脉冲，area_slots总上限16。ArcheryTarget.receive_area用pull=1、crit=0、bullseye=false、目标本体甲结算，最低伤害1沿用CombatMath；不重新应用母箭增伤/拉力。返回damage_kind=area、pierced=false、can_split=false，直接World._on_hit，不回到Arrow接触/暴击/出口/分裂/回响流程，无额外战斗RNG。area hit_id为shot:source:area:event，物理接触仍用原ID，credited_defeats仍按目标生命ID去重。

普通靶每支箭可以各受一次物理与范围命中；area_slots不占普通hit_slots，子箭继承母箭已范围命中的排除。Boss receive_area只按本体甲，无弱点倍率/暴击，返回生命别名[-1,-3]；World把它们加入hit_slots，避免次级与核心/本体重复扣共享HP，护板从不单独参与范围伤害。正式Boss场内无普通靶，自己的核心回响只产生视觉圈，不再扣自身血。击倒仍统一按整次家族结束给分/金币/回复，最后一箭不提前结束。瞬时area_rings与浮字不持久化，真正HP/排除/账本保存，继续不重放范围伤害。

封套v14，箭combat_schema=2（Boss仍1或旧0、health_revision仍2，world.projectile_schema仍1）。旧v13先原字节归档.legacy-v13，再把箭schema1升级2并补中性八参数、零critical_stacks和空area_slots；旧五参数和T11-B七参数/层数/出口/回声/分裂/属性/装填/来源/固定候选/RNG保持。T11-C版写入要求schema2和齐全字段；当前v16仍要求schema3（见下文）；检查非有限参数、上限/整数层数、唯一范围槽位（不能为盾/核心别名）、Boss范围槽位必须排除两生命部件，以及次级事件不得伪造暴击/靶心/盾/身份。损坏事务不覆盖好档。

重点回归：奇遇门槛与队列/候选保底/固定 offer/陈旧领取拒绝/最后一箭先选择/在途暂停和磁盘恢复、树约束/精确支出/开局快照、按拉弓计连击、大靶碰撞、购买预览一致、乘法顺序独立、穿甲相等边界、高速/圆角/墙角/同靶去重、条件中心/真实暴击/范围独立来源、未知版本保护。程序美术、合成音效和当前测试不代表正式发行性能与听感已完成。

## T11-D：来源因子、子箭预算与金币

本节为T11-D接口记录；随后T12-A精通接在来源合成阶段，当前完整接口见handoff-t12a.md。

当前EncounterCatalog.ALL=24（6普通/18特性/5含代价）。EncounterData.requires_trait供两种子箭项指定piercing_split；RunModel.encounter_has_gain在抽取及领取时统一校验。代价项比较完整来源推导的有效速度/伤害，无实际增益不抽；已选项仍在历史解释。安全普通保底、展示移出、Boss安全普通、固定候选/token/RNG保持。

calculate_raw_stats在全部来源加法、数量减伤与普通伤害百分比后，应用瘦箭尺寸×0.7/速度×1.25及重箭伤害×1.4/装填×1.35，各仅一次，再走联动/归一/两转换/clamp。预览、碰撞半径、发射和下次装填同源，基础资源不变；旧箭和当前装填不修改。

ArrowEffects增加child_gold_bonus与child_bounces，默认0、选择后发射采样0.5/2。World._on_split在继承母箭余下预算后加冻结child_bounces再限32；母箭不加，旧母箭随后分裂仍旧系数，子箭无递归，32主/64子上限保持。

World._on_hit只给真实子箭致死事件记录parent_source_id与正child_gold_bonus，基础reward_gold不改；直接或范围击倒都可，母箭/非致死/护板不记。GameSession.settle_shot在已有连击/靶心/普通金币系数上乘子箭系数，仍按生命ID去重及整次家族结算，不增加分数或击倒次数。Boss共享生命排除被子箭继承，不得绕过同Boss去重。build_field把JSON父来源转换回int，恢复身份一致。

T11-D交付封套v15，Arrow.combat_schema3，world.projectile_schema1、Boss.combat_schema1/旧0、health_revision2保持。v14先原字节备份.legacy-v14，schema2→3补中性两字段，旧参数/动态层/回声/排除/出口/分裂/装填/固定候选/RNG保持；更早沿原升级链。写入验证新字段有限且范围正确、剩余/额外反弹为0–32整数，子箭奖励的母编号小于合法命中来源且为真实有效致死，不允许护板；失败不覆盖好档。

JSON完整精度仍可能把elapsed的0.11000000000000001变成0.11；新测试仅该计时字段允许≤1e-12误差，其余快照严格一致，后续物理与RNG一致。瞬时浮字/光圈不恢复；回响浮字上移18逻辑单位以分开直击奖励。1325/0自动、51/0窗口、十五张画面检查通过，详见handoff-t11d.md。此为T11-D当轮记录；当前技能精通已接入，下一轮T12-B，特性强化/补给/难度榜待办。

## T12-A：独立技能精通来源

RunSkillData/data/skills定义六类精通的首价、价格增长/上限、累计递减权重、加法/整数来源及伤害百分比；RunModel保存mastery_levels与mastery_unlocks，基础skill_levels及永久档案不变。数量前6阶提高基础减伤因子并增伤，之后加受限原箭数而不追加基础减伤；其他方向各保留属性和副收益。百分比加到普通百分比同一来源，再走数量减伤、代价因子、联动/归一/转换/clamp，不复利。

evaluate_stats/calculate_raw_stats增加可选masteries（null使用当前），预览复制基础/精通字典只提高对应阶段；StatEvaluation.mastery_ranks用于前后解释。skill_is_mastery / skill_rank / skill_limit / skill_price / skill_has_gain统一供UI和buy。基础满级或下一基础级无有效正收益时开放精通；首次购买记本局资格，避免后续来源变化重新锁住。buy校验目录身份、SHOP/未挂起、金币、100阶上限和实际有效增益，原子记级扣款；不修改当前装填或旧在途母子箭。GameHUD六卡显示真实输出、两转换/中心增伤、无收益/缺钱/满阶，万/亿价标签的tooltip保留精确金额。

当前SaveStore.VERSION16，Run.mastery_schema1/skill_schema2；v15先原字节归档.legacy-v15，精通/资格从零起，原构筑/固定选择/token/RNG及旧箭/待结算收益保持。当前事务验证两个字段齐全、六ID、精通正整数1–100、开放与已购等级相互对应、基础整数原上限；旧无精通版本可读后升级。Arrow.combat_schema3/world.projectile_schema1/Boss规则保持。

Godot JSON可能将新箭3.8+0.15尺寸写读为3.95（一ULP），家族测试仅该冻结尺寸字段允许≤1e-12，其余恢复/后续字段严格一致，来源等级/Run推导属性/RNG精确相同。1431/0自动、145/0窗口、17张画面检查通过。下一轮T12-B有限特性强化与Boss免费强化，金币补给/难度榜仍待后续。



## T12-B：特性强化来源与免费目标

TraitUpgradeData/data/trait_upgrades为18特性定义3阶/首价/1.8递增及原参数加法或转换分母权重。TraitUpgradeCatalog.derive复制原EncounterRules，仅按已选特性和trait_levels来源重建，不改变基线或encounter_picks。evaluate_stats/calculate_raw_stats的第4个可选upgrades用于纯预览，技能/精通和属性追踪均读同一来源。

RunModel.buy_trait校验已选、触发/有效正收益、阶数、金币、未挂起及SHOP或PLAYING历史暂停许可，expected_rank拒绝旧点击；Main再核验range/日志/树暂停。trait_shop_open是瞬时UI许可，不存为加载后购买能力。HUD刷新保存日志滚动位置，EncounterPanel展示当前/下阶/价格及拒购状态。ArrowEffects仍已有字段，全部发射冻结，旧母箭后生子箭仍用旧档位；箭combat_schema3与家族预算不变。

Boss复用原奖励队列。@upgrade/<id>/<next_rank>为固定免费目标，Catalog.find生成带upgrade_trait/upgrade_rank的显示资源，ALL仍24项；目标必须已选、有收益、未满，并与当前阶数相邻，来源必须Boss。领取只加该阶/消费一次队首/记录精确ID，不扣钱或多记普通奇遇；普通十次保底与seen不改变。新Boss通常一普通+至多两强化，不足补安全普通；没有强化回退普通，全部封顶可确认保持构筑。

v17保存trait_schema1和trait_levels，旧v16原字节归档，档位归零，原精通、旧固定普通Boss候选/世界/收益/RNG不重抽。SaveStore验证18已选ID正整数1–3、免费队首/相邻目标/完成等级/同阶重复与轮次顺序，拒写不覆好档；旧无字段版本可读后迁移。1735/0自动、113/0窗口、21张画面，浮点精度边界见handoff-t12b.md。

## T13：有限补给与消费事务

SupplyRules新局采样limit/draws/first_cost/growth，默认2/1/24/1.6；价格按累计购买次数而非段次数增长，最多10亿。SUPPLY追加枚举5，原数值保持。World完成所有族群结算、回复与奖励后Run.settle_volley决定固定购买/结束或直接LOST；Main暂停SUPPLY世界，buy_supply验证SHOP/SUPPLY权限、token总数/段/offer_id、金币/额度/容量，单次支付和+1拉弓。SHOP保持暂停，SUPPLY恢复PLAYING；decline_supply一次终结。record_boss_defeat在生命ID首次入账时更新段基线并恢复额度，历史胜利不重发，不降低价格。

_spend_gold集中basic/mastery/traits/supplies，gold_spent与五分类（含迁移legacy）同事务；结束丢弃剩余钱包，记录收入、消费和供给总数。真实奖励入账遵守钱包既有10亿恢复上限，累计收入仍保留实际奖励。教程无限拉弓隐藏正式供给按钮，正式局不受练习影响。

v18/economy_schema1要求参数整数/有限范围、段与胜利一致、合法购买历史/选择token、分类总和/补给价格累计吻合。SUPPLY必须零箭、无待选、未终结且买得起，世界无箭/待结算/waiting标记；旧v17字节归档后补本段0购买，旧支出可重建部分归legacy，不改构筑/固定候选/在途/装填/RNG，旧终局不复活。build_field恢复SUPPLY不因零箭重新设置waiting，立即再保存仍有效。具体接口、验证和下一包边界见handoff-t13.md。

## T14-A：难度锁定与一次采样

DifficultyData/Catalog三项normal/hard/hell，配置见data/difficulties。RunModel.new(mode_id)在新局复制四项参数，mode_id与mode_parameters只读，参数getter返回副本；GameSession.start_run(replace_existing=false, mode_id="normal")保留原bool调用兼容，未知模式在弃旧局前拒绝。Main的mode_select只允许无活动局的大厅，结果重开沿用原模式；活动局改模式先走已有放弃确认，再回大厅重新选择。

FieldRules.target_values/Target.configure与BossRules.values/Boss.configure_boss接受末尾可选mode字典。血量和奖励生成时采样一次，普通靶补充沿同run参数与真实击倒数；现存实体不改。普通HP为base×modeHP×(1+击倒×modeGrowth)，普通/困难6%，地狱10%；Boss普通2880基准按轮次成长后再×1或×2。普通/困难/地狱分数倍率1/1.5/2，普通原基准奖励取整后再乘一次，不在GameSession或record_defeat重复乘；困难可出现43×1.5=64.5分，实际run累计、经验、浮字/HUD/结果均保留。金币/护甲/门槛/胜利补给保持。Boss规则与普通成长仍独立。

v19/mode_schema1保存mode_id和mode_parameters={target_health,boss_health,score,health_growth}，字段恰好四项、数值有限；血量/分数倍率1–10，成长0–1。读取合法采样值，不强行替换为当前资源，避免更新配置改已有局。v18字节先归档.legacy-v18，再补普通参数；世界已有HP/最大HP/奖励/移动/在途快照保持，收益与经验不重放、不补倍率，旧终局不复活。世界、模式、固定选择、补给/消费同一事务。该段为T14-A交付记录；T14-B已接入v20，见下文。详见handoff-t14a.md。

## T14-B：有限永久榜与终局事务

PlayerProfile持有Leaderboard，仅保留3条，entries返回深副本；submit严格大分插在前，同分插在现有同分之后，超出前三不保存。记录run_id/score/mode_id/ended_at/reason/defeated_count/bosses_defeated；规范化数值类型，JSON读回不改变记录。时间为Unix UTC秒，排序不依赖系统时间先后。无全局已结束ID集合，没有额外历史库。

GameSession.end_run是唯一正式提交入口，使用已结算run.defeat_score，当前run保存ranking_processed/rank_at_finish/ended_at（ranking_schema1），包括零分/未入榜也标记处理。结束摘要带同字段，和榜及终局清钱同checkpoint；重复end、继续、显示页面不提交。start_run(true)先按原规则弃旧局并提交已结算正分，再新开清局。GameSession.new(false)用于教程，练习局也不提交临时榜。读取旧终局将其标记已处理，不从旧摘要或累计经验补分。

封套v20要求Profile leaderboard_schema1和完整Run ranking_schema1；榜必须有界/得分降序/ID唯一/模式已知/正有限分/合理整数时间及计数，活动局无结束标记，终局标记/名次/摘要/榜内该局字段一致。非法当前事务拒写，损坏主档回退整个好事务。旧v19先原字节归档.legacy-v19再空榜升级，模式/现存世界/收益/构筑/消费补给保持；旧活动局可在真正结束后入榜，旧终局不补录不复活。当前读取不重新结算或使用累计经验排序。

LeaderboardPanel复用于主页和大厅排行榜页，三行显示难度/分数/击倒/Boss，空位显示虚位以待；悬停含完整分数和UTC结束时间，大数文本省略不改原值。PageRouter的leaderboard导航暂停原世界，返回大厅或继续不入榜。结果显示本局名次、未进前三或零分；旧终局显示未补录。2339/0自动、190/0本轮原生、117/0难度回归，详见handoff-t14b.md。

## T15 天赋扩建

参见handoff-t15.md。TalentCatalog按五层拓扑恢复；原20节点不变，后排5/7/10点。RunModel原始来源加入新增BowStats天赋加法与固定/金币效率百分比；数量暴击联动在转换前，穿甲/数量/尺寸条件增伤在转换后相加统一乘一次，再做最终封顶。TalentRules导出四个联动上限；金币连击上限在GameSession结算时加进阶效果。预览和实际重建同源，均不改共享基础。TalentPage纵向滚动、按parent画线、固定详情并延后定位选中节点。v20结构不变，永久档与开局快照/发射副本独立；2649/0自动、201/0原生。

## T16 神器背包

RunModel保留encounter_picks作为当前生效来源，artifact_ids按目录取得已装备特性。artifact_capacity默认6，discarded_artifacts保存被移除神器的最终强化阶数供历史校验，不参与属性计算；artifact_revision在获取、付费/免费升级和丢弃时递增。背包丢弃要求PLAYING、无待选、未挂起及trait_shop_open；替换要求CHOICE、当前offer_id/revision和有效旧神器，全部预校验后一次消费奖励，一次发布状态。依赖校验阻止移除仍有子神器的父项及新神器替换自身前置。

EncounterPanel复用奇遇入口提供六格、升级、丢弃确认和满位替换页，普通增益/Boss记录/已丢弃记录在下方滚动；只发送action，不直接修改RunModel。替换页为临时视图，存盘仍是未消费的固定选项，读档返回同一组选择。Main保持暂停并在成功操作后保存整个会话与世界。冻结箭不受移除来源影响。

v21加入backpack_schema1、容量、修订号和弃置等级；校验容量/来源互斥/seen记录/已获奖励数量，Boss已免费强化的历史可由弃置等级证明。v20及更旧按已持有数量max(6,count)迁移；仅version<20清理历史排行榜字段，防止v20玩家丢榜。原字节备份先于迁移写入。


## T17：契约快照与分域得分（当前v22）

ContractCatalog定义8类、两档、三预设与版本1公式。RunModel构造参数contracts=null代表旧模式，{}代表新零词条局；GameSession.start_run在弃置旧局前校验组合。Main正式新局传入PageRouter.selected_contracts；ContractsPage只操作开局草稿，活动局查看时禁用。重新开局保留本局组合；旧局重试仍保留旧模式。

RunModel.challenge返回深拷贝；保存{version,selection,parameters,risk}。版本1应保持不可变，未来调整必须新增规则版本及兼容解析，不能直接改参数公式影响已有局。JSON会将整数转浮点，验证逐个校验合法数值后规范化selection/参数，不使用整份Dictionary的类型敏感相等判定。契约mode_parameters保留四字段，target_health/boss_health取契约、score=1、health_growth=.06；field_parameters增加target_armor/bullseye_scale供世界生成使用。

普通靶快照reward_score仍为基础分，RunModel.record_defeat才按普通靶倍率结算并累计contract_stage_base_score。Boss胜利按自身倍率+阶段额外分结算，累积contract_stage_bonus_earned并在boss_reward_log写contract_bonus，清空本阶段基础分；同一事件复用credited_defeats去重。GameSession按run.defeat_score前后差同步经验，避免基础分与奖励经验不一致。

skill_price统一涵盖基础/精通，trait_price统一供可购买校验、扣币和界面。供应limit允许契约0，backpack容量允许契约4/5；校验必须与challenge采样一致。缩小靶心在ArcheryTarget的命中与绘制同源，Boss重载弱点判定不变。

SaveStore.VERSION22，challenge_schema1要求challenge及两个阶段账本。合法性包括目录/档位/参数/风险对应、mode/容量/供给一致、基础分不大于实际得分、已发阶段分与Boss日志合计一致；无契约旧局账本须为0。v21迁移仅新增契约兼容字段，不能抹掉背包与排行榜：backpack清理仅version<21，ranking清理仅version<20。原字节先归档，整个世界与家族箭按原快照继续。

Leaderboard接受可选契约元数据，旧记录保持原形状，新记录规范化；终局摘要/本局榜条目与运行快照保持一致。LeaderboardPanel点击记录创建随页面销毁的详情层，结果页及背包Boss记录展示已获阶段分。验证2962自动/107窗口，详见handoff-t17.md。
