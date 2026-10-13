# T11-A 交接：十二种奇遇、实际收益筛选与安全继续

2026-10-09。T01–T08、T10-A/B/C、T11-A已完成。下一轮只实施T11-B（四种贯穿/弹射特性），不展开T11-C/D、T12精通/强化或T13金币补给。工程D:\AzVGames，Godot4.7.2标准版，双击Play.cmd可玩。

同日最新修订：用户要求将快手搭箭替换为增伤+5%，现已改名箭势渐盛，同类层数相加（两层10%），v12备份旧v11并沿用已选层数；未来发射使用新效果，旧箭与正在装填不变。当前1046/0自动、30/0百分比窗口，十二张t11a-percent-画面已检查。下方旧v11及初版截图数字是历史，最新效果与存档以本修订为准。

后续追加已记入计划但未实现：T14-A困难/地狱模式，T14-B单局本地前三排行，排在T13后、T09前。困难普通靶HP×1.5、BossHP×2、得分×1.5；地狱继承血量倍率、提高普通靶血量成长（开发默认6%→10%），用户明确地狱总得分按普通基准×2。默认三模式共用总共3条的榜并标注模式。详见expansion-plan.md和game-design-v2.md新增节；当前下一轮仍T11-B，不把追加计划当作已上线功能。

## 当前实际内容

EncounterCatalog.ALL从9扩到12：6普通+原6特性。新增独立可重复无代价资源：

| ID/名称 | 当前可调默认值 | 计算位置 |
| --- | --- | --- |
| steady_power / 弦劲渐长 | 基础伤害+12 | additions累加后，再数量减伤、归一、最终封顶 |
| tempered_tip / 淬锋箭簇 | 穿甲+3 | 与天赋、技能和暴击转换叠加，仍须严格高于护甲才能贯穿 |
| quick_nock / 箭势渐盛 | 每层伤害加成+5%，两层10% | 保留内部ID兼容历史；基础伤害加总后乘(1+0.05×层数)，与数量减伤、归一同源计算 |

三项都在data/encounters/*.tres，不加新SkillCatalog节点。EncounterData.category_label提供金币/箭数/补给/伤害/穿甲/增伤分类；箭势渐盛group=damage_percent，与平加伤害group=damage不同，可同组出现。damage_bonus=0.05是独立资源参数，在calculate_raw_stats汇总后与基础/天赋/技能/普通伤害加总及数量乘数同源计算；不能逐次对已计算stats累乘。卡片显示累计增伤和单箭有效伤害，历史记录说明加法层数。原6特性无互斥，raw→linked→unity→critical_forging→critical_ricochet→clamp不变；旧Arrow.stats/ArrowEffects/world.reload_left不改。

## 候选与保持构筑确认

RunModel.encounter_has_gain(reward)普通项通过evaluate_stats当前有效值和preview_encounter比较所有BowStats.FIELDS，经过联动、转换与上限；draws看shots_left<100000。特性保留未来构筑承诺，不因当前缺穿甲/反弹就排除。

EncounterCatalog.draft第四个可选eligible Callable同时过滤fallback和实际pool，保证封顶项不能从保底重新进入。先抽有收益的安全普通项，再按ID/group唯一补到最多三项，顺序随机、特性展示后移出（未选也移出）。不足三项就保留实际数量；完全没有安全普通收益时直接返回[]，不动RNG或seen。

普通和Boss共用筛选；Boss pool仍只含无代价普通项，不抽/移出特性。offer_encounter为零卡确认设置offer_exhausted=true，照常生成offer_id并进入CHOICE。EncounterPanel支持居中的一/二/三卡布局、零卡说明和“保持构筑 · 继续射箭”。旧固定卡片完全保留；无收益卡disable，不能领取浪费次数。旧组的普通项全部无收益时，即使还有可选特性，也可确认继续，避免强迫代价。

can_skip_encounter检查当前固定组是否缺少有收益的安全普通项。skip_encounter校验CHOICE、pending、suspended和offer编号，共用_consume_reward_source消费一份来源；不记虚构encounter_picks、不改构筑/金币/拉弓，不抽新RNG（后续有另一个来源才生成下一组）。Boss log.choice记录NO_GAIN="_no_gain"；已给得分/金币/有限补给保留，不重发。历史显示已跳过而不是待领取。全部消费后仍由世界结算判断真正耗尽/恢复补靶；GameSession.end_run清理offer_exhausted。

## v11存档

此节为初版历史。当前SaveStore.VERSION=12，仍使用原v11字段；v11源字节保存.legacy-v11，旧quick_nock层数转换为每层5%增伤，固定choices/token/RNG和完整在途快照不重抽或重算。未来reload_seconds回到基础及其他真实来源，既有world.reload_left保留。v11→12迁移提示说明替换；重复读v12不重新转换/累乘，Boss血量修订不变。

SaveStore.VERSION=11，旧v10原字节存为.legacy-v10，再由GameSession.from_dict恢复。新字段offer_exhausted为bool；旧固定choices、offer_id、来源queue、picks、RNG与完整世界不改。已有health_revision=2的Boss不再扩大血量，v10升级提示明确新目录用于后续选择。v9及更早缺health_revision的旧Boss仍沿T10-C一次性×3迁移。

SaveStore对CHOICE允许至多3项且至少安全普通卡；空choices必须exhausted=true并重新计算全部安全普通项确无收益。拒绝伪造空组、错误flag类型、非CHOICE exhausted等。Boss选择记录允许NO_GAIN哨兵，已确认记录不能留在队列。原来源去重/门槛/特性/世界一致性、未来版本保护、好档备份均保留。

RunModel.from_dict普通叠层解码上限从100000扩大到10亿，避免百万穿甲需要超过十万叠层时读档丢失历史；伤害/穿甲/箭数等有效上限没有提高。实际无收益筛选会阻止继续堆无意义层数。

## 验证和产物

最新修订：1046/0自动，比初版增加8项，新增同类百分比×所有基础来源/数量/归一、历史计算与v11字节迁移/旧两层转10%/再选为15%/oldflight与装填/RNG保持/反复恢复不复利；原封顶测试改测百分比伤害边界。原生窗口30/0，.tools/encounter-percent-window.log；十二张artifacts/t11a-percent-*，三新卡24→25.2/累计0→5%、两层历史+10%、实际按钮/旧箭/装填、短候选及耗尽继续全部通过。以下为初版记录。

- tools/run.ps1 -Mode Test：1038断言/0失败，比T10-C多78；tests/test_encounter_expansion.gd覆盖叠加、转换/部分封顶、100seed真实池、fallback/短候选/空候选、确认权限/去重、Boss保留供给、旧v10固定组/原字节/高叠层恢复、在途和未来发射、实际按钮。回归专测原三项的fixture固定旧组；真实新池另测，不假设随机组必有某卡。
- test_encounter_expansion_window.gd：30/0，.tools/encounter-expansion-window.log；artifacts/t11a-十二张截图（新三卡/小窗/实际领取、历史上下、一/二卡、旧封顶卡/小窗、零卡/磁盘继续/小窗）。选择quick_nock保留在途箭和既有装填，之后0.59秒；末级0.17→0.15与补给99999→100000准确。
- test_boss_rewards_window.gd本轮24/0，.tools/t11a-boss-rewards-window.log；--capture-prefix=t11a-boss-八张，真实2880HP最后一发整族胜利得到1200分/840金币/3次，扩展池展示/领取穿甲+3、磁盘继续不重发、普通靶重新生成、历史和结果保留。

20张实际OpenGL截图逐张检查，1280×720/960×540无裁切/重叠。全部user://tests，不修改玩家存档；捕获进程已退出。巨大击倒数/全上限是边界fixture，不代表自然长期平衡已完成。旧截图和交接保留为历史。

## 下一轮 T11-B

将12目录扩到16：越靶越锋（有效贯穿后增加后续伤害）、破甲余势（超护甲穿甲增加当次伤害）、回声重击（反弹增伤下一次命中并消费）、借壁破甲（反弹增加该箭局部穿甲）。具体默认系数独立配置，次数/收益封顶；不改角色原始stats，不增加同靶重复伤害。

先检查Arrow扫掠→receive_contact→struck与反弹/分裂出口顺序：穿透要在真实穿过目标后生效，墙角只计一次，Boss护板无生命/暴击/分裂收益，核心与本体共享一次HP结算。明确母子继承、发射快照和旧在途箭无新特性；新增箭局部状态/效果参数需要序列化、SaveStore校验和版本迁移，不默认现有v12字段可容纳。保留有效收益过滤、短候选/安全确认、百分比增伤同类相加、fixed choices/RNG、来源queue、Boss胜利去重、原六特性持续转化。仅完成B并留下可运行交接。
