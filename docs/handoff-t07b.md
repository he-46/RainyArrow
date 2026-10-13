# T07-B 交接：持续属性转化

T01–T07 已完成；下一轮只做 T08-A 设置，T08-B 互动教程与 T08-C 装扮另开轮。验证日期 2026-10-09；598 项断言、0 失败，新 T07-B 91 项。历史交接保留，本文件为当前入口。

## 实际可玩内容

目录现有三普通、三联动和三含代价的唯一转化：

- unified_arrow / 万箭归一：主箭数1，按原箭数N（最多32）伤害×N、尺寸×√N，保留数量技能伤害代价与分裂。后续普通增箭/数量升级都参与，不把来源数抹掉。
- critical_forging / 锋芒换运：暴击率全清零，数量联动之后的暴击来源每2个百分点换1穿甲（最多100%来源）；不足单位不兑换，余数仍在原始来源中供后续升级重新计算。
- critical_ricochet / 舍锋借势：暴击倍率回1，扣掉普通100%伤害基线，每20个百分点额外暴伤换1反弹（来源最多额外900%）；200%倍率恰好换5次。仍有暴击率时，事件可以为暴击但不会额外增伤，可继续参与暴击回复天赋。

三者分别唯一组，可与所有联动一起使用；含代价明示，每组仍有安全普通，不强迫玩家选择。展示即移出、未选择也移出、耗尽普通补足不变。

## 属性接口

calculate_raw_stats(levels,picks) 仍为基础→开局天赋→旧加成→普通奇遇→六技能加法→数量伤害乘数；返回原始来源，无覆盖/累加。

evaluate_stats(levels,picks) / _evaluate_raw(raw,picks) 返回 StatEvaluation：raw、linked、converted、effective 互相独立。固定流程是原始→数量暴击联动→归一→暴击率转穿甲→额外暴伤转反弹→有效上限。source_arrows 为1–32的原箭数，联动读取归一前箭数，不读结果1；crit_source 为联动后0–100%暴击；extra_crit_source 为倍率1–10扣基线1。来源边界不抹掉 raw，converted 保留应用后的未限制值。

新增规则位于 data/encounter_rules.tres：unity_damage_exponent=1、unity_size_exponent=0.5、crit_per_penetration=.02、extra_crit_per_bounce=.20。_conversion_units(value,step) 使用 floor(value/step+1e-9)，修正2.2等小数边界而不把显著不足单位的余数上取整。输出按 BowStats 现有伤害100万、尺寸6、反弹32等上限。归一仍保留原数量单箭减伤，高箭数数量升级的伤害收益可能减缓，尺寸与数量联动继续增长，最终平衡待T09。

preview_skill_evaluation / preview_skill / preview_encounter 与真正重建共用管线；skill_comparison 提供归一后的伤害/尺寸、转化后的穿甲/反弹，避免显示1→1或0→0而忽略收益。stat_explanations(StatEvaluation) 返回完整阶段，历史顶部与技能悬停共用；selected picks 从当前 RunModel 读取，阶段用于当前/技能升级，奇遇候选用独立 comparison。

## UI 与截图

EncounterPanel 卡片增高20像素，比较 Label 在填文本前设置宽度/自动换行；归一卡描述缩短为三行，避免压住比较。历史顶部七行计算用紧凑 VBox，可在222高区域同时阅读；历史说明会自动换行，列表仍可滚动查看全部已选。

已实际渲染查看 artifacts/t07b-conversion-{unity,crit,next,shop,log,flight}.png。next 是已转换后再拿普通箭数的实际预览；技能展示原箭4→5、发射1、伤害69.4→73.7、尺寸2→2.24；暴击升级显示原20%→25%、倍率2.5→2.75、有效穿甲15→17/反弹8→9。flight 展示归一大箭与分裂子箭。

## 存档与运行箭

没有新增持久化字段，继续 v7，不为目录扩充或推导值引入无意义迁移。原始来源仅保存技能/旧加成/开局天赋/奇遇 picks，加载统一重算；StatEvaluation 不保存。旧 v7 已展示卡片和 RNG/待选原样保留，旧在途 Arrow.stats 不追溯转化；未来发射才获取新快照，子箭继承已转化母箭，不再次计算转化。

SaveStore.write 改为 JSON.stringify(envelope,"",true,true)，完整输出浮点精度。乘数量和归一产生69.359999999…等值，默认序列化会截到69.36，破坏严格箭矢快照相等；完整精度后母子族磁盘快照精确相同。已有旧存档丢失的精度不补造，也不因read主动重写。旧v1–v6备份迁移、未来版本保护与损坏恢复回归继续通过。

三转化继承原 shot_id/source_id/parent_source_id 族群与64子箭预算；最终零次数等待整个族结束、按拉弓顺序结算、击倒去重/回复/奇遇优先保持。转化后的穿甲能触发分裂，转化后的反弹能使用增速。原箭/子箭在途购买后的数值不改变。

## 验证

tools/run.ps1 -Mode Test：598 项断言、0 失败，tests/test_conversions.gd 新91项：20组取整阈值、单项/持续购买/原始不改、全六特性/插入顺序/40次重建/来源输出上限、普通保底/含代价标记、真实末箭转换/贯穿/分裂/半伤害/反弹/击倒结算、精确磁盘族群、真实三卡/技能/下一发/大厅/历史暂停、旧v7固定组不迁移及非法全含代价组拒写。

T07-A 真实池测试按目录统计唯一特性数（现6），不再硬编码3；T06 普通样本仍显式标记特性已见，真实新池由T07覆盖。所有测试/捕获仅 user://tests，不触碰玩家档。尚未长期压力或完整音效听感，不把测试通过当最终平衡完成。

## 下一轮 T08-A：设置

只实现完整设置并停止，下一轮再做互动教程，然后装扮。设置不应重置当前局、消耗/补发拉弓、重抽奇遇或改变在途箭。

1. PlayerProfile.settings 已有 muted/master_volume/music_volume/sfx_volume/fullscreen/screen_shake/trajectory_guide 默认值，并持久化；现在只有静音实际接通。检查 from_dict 的类型/边界校验，提供设置页组件，避免再扩大 PageRouter._feature。
2. main._ready 当前仅设置 audio.muted/主总线mute，M/HUD静音走 _toggle_mute；完整设置应共享唯一应用入口，启动、UI改变和快捷键都一致，不在每次refresh重置滑块/播放状态。
3. AudioService 当前是合成音效，使用 Bow /Impact /UI 总线，VOICES=10；没有正式音乐，音乐音量可保存但应说明目前暂无曲目，不伪称已有音乐。master和sfx需要实际影响现有声音，0音量妥善处理dB。
4. World._draw 的轨迹预览目前始终绘制，需读取设置并实时开关；震动可接命中/击倒反馈，避免只保存flag不产生体验。纯视觉设置不能改变碰撞坐标/物理snapshot，关震动后复位。
5. 全屏需要实际 DisplayServer 窗口模式，退出/继续与失焦暂停不互相触发循环；无窗口测试应规避不支持的窗口调用，窗口渲染下做实际开关验证并恢复测试窗口状态。
6. GameSession.save_payload 已把最新 settings 放入战斗 checkpoint；保持独立设置更新不混入旧击倒XP/箭矢边界。测试设置读档、值约束、实际音量/轨迹/震动、主菜单/大厅/暂停页返回以及 CHOICE/在途箭保存。

T08-B 的临时教程世界必须与正式 run/profile 收益隔离，学完只更新教程记录；T08-C 纯外观按等级/累计击倒解锁，局内金币不带回。两包这轮尚未实现。
