# T10-C交接：胜利补给、战利品与三倍Boss血量

2026-10-09。本包完成，下一轮仅 **T11-A：三种普通奇遇扩展与目录说明**。T01–T08、T10-A/B/C已完成；T11–T13和T09尚未完成。Godot4.7.2标准版/类型化GDScript，Play.cmd启动，Test.cmd回归，不需要新依赖。旧交接保留为历史，当前接口以此文件为准。

## 用户调整和实际数值

用户最新要求“boss血量太低了，血量x3，然后下一轮”。已将BossRules及data/boss_rules.tres的基础HP960改2880，全轮基数同比扩大：第一轮2880、第二轮4608、第三轮6336；仍每轮增加首轮60%，采样HP取整防止浮点尾数被HUD向上显示多1。护甲仍20/+6，弱点×1.75/甲−12、护板甲+8以及50%转第二阶段不变。

已有旧档Boss也按最大HP和剩余HP同时×3处理，保留剩余比例，不重置阶段或运动。例如400/960→1200/2880；已死亡仍0。health_revision=2防止重复扩大，不修改已经发射的箭矢属性/位置/命中排除或RNG。旧v8静态combat_schema=0继续静态原机制，血量仍按此次授权调整。

Boss首轮1200分/经验、240基础金币，之后每轮增加首轮50%，金币仍读取当前金币倍率/连击/靶心加成。整次箭族结束才沿bossN账本入账一次。额外胜利回复默认3次拉弓，每两轮增加1次，最多6次：轮次1/2为3，3/4为4，5/6为5，7以后6；规则在BossRules.draw_reward和tres三个参数中。全局拉弓上限100000，日志记录实际获得数量，天赋每次拉弓最多一次的回复独立叠加。

每次胜利再追加一次Boss战利品三选一，当前仅原三普通：丰收之风、箭雨初临、再挽弓弦，全部无代价；选择再挽弓弦可另回复3次。没有新特性或免费强化档位，T12-B再增加已选特性强化。Boss不增加普通击倒/经验解锁用的普通累计击倒，不触发十次门槛或占用未展示特性池。

入场每100普通靶、逐次更强、清场无收益、Boss期间不补普通靶的规则保持。胜利补给和选择先处理，领取后才重新生成普通靶继续同局，难度不重置。最后一发致死可以先被胜利补给救回；待选时即使次数为0也不结束，真正全部领取且无箭/无收益/无次数才结束并清空局内金币。

## 共用来源队列与一次性奖励

RunModel新增reward_queue:Array[Dictionary]和boss_reward_log:Array[Dictionary]，boss_reward_schema=1。

- 普通门槛向队尾追加{kind:ordinary,round:0}；Boss胜利追加{kind:boss,round:N}。
- pending_encounters现在是全来源待领取总数，encounter_rewards_generated仍只记录普通十次门槛，不能把Boss奖励混入下次普通门槛。
- reward_source读取队首；普通按原ALL草拟，Boss取无负面普通池，仍复用EncounterCatalog.draft、choices、encounter_offer_id和choose_encounter。Boss显示不会移出未展示的特性。
- 已得普通队列排在Boss来源前，领取一项后自动开放下一来源，offer编号递增。来源与固定候选一起存档，不重抽。
- Boss选择检查安全普通项，消费队首，将对应记录choice更新为id；token和phase校验阻止重复选择。发奖依旧由bossN/credited_defeats和last_settled_shot去重，不再造第二套奖励系统。
- _sync_reward_queue仅兼容旧pending计数，补为ordinary来源；正常record_defeat/record_boss_defeat已主动添加来源。新增代码不要仅手改pending而遗漏来源，别把同步工具当撤销或丢弃奖励的方法。

record_boss_defeat仍在PLAYING中扣实账；按真实倍率记score/gold，回复时仍是PLAYING，再追加log/来源，最后GameSession.settle_shot完成所有命中/天赋回复后调用offer_encounter暂停。不要在每个部件命中或BossHP首次0时直接发补给，穿甲三箭/子箭族必须等完整结算。

World._advance_boss原有全部箭/全部pending/全部选择等待条件保持；CHOICE期间保留0HP实体，不提前补普通靶。领取后退出磁盘即使尚未重新补靶，也保存0HP+已记账状态；下一physics只重新开放，不重领奖。新普通靶继续用field_generation避免已入账slot-life重复。

## 记录、页面和反馈

boss_reward_log每项round、score、gold、draws、choice，draws为胜利供给实际获得数，choice尚未领取为空。boss_reward_totals累计已有记录，GameSession.last_run_summary保存记录和总量；历史旧Boss胜利数保留，但不伪造未知旧收入或已选记录。

EncounterPanel复用同一个选择页：普通仍“林间奇遇”，Boss显示“Boss战利品”，副标题显示本次已入账分/金币/补给。奇遇历史顶部显示Boss战利品与所选增益；HUD普通靶场显示Boss胜利次数，结算页新增Boss次数/收入/补给。继续原候选和来源；返回大厅/主页面再继续会自动回到相同暂停选择页。

World分别发boss_entry、boss_phase、shield_block、shield_pass、boss_weak；main在真实胜利入账时发boss_victory。AudioService六种合成PCM各自有音高/时长/噪声/扫频区分，遵守静音与音效音量、现有10声部池。main回复浮字由硬编码+1改为实际恢复数量。胜利选择后的靶场重开提示保留。当前是合成占位声音，无正式素材或背景音乐；本包校验非空/不同波形与运行，不声称完成主观听感验收，T09-A/C处理。

## v10存档和迁移

SaveStore.VERSION=10；Run boss_schema仍1，world projectile_schema仍1，Boss combat_schema仍0/1。v10要求boss_reward_schema=1和完整奖励队列/日志，新Boss/已升级Boss快照要求health_revision=2；缺字段不能悄悄回退为历史奖励模式。其余战斗参数、两位置、运动时点和在途箭/子箭/收益账本继续原子保存。

SaveStore校验队列长度等于pending，记录轮次单调且已在credited_defeats入账、draws0–6、已选择id为真实安全普通项，未领取记录对应唯一队列来源。当前Boss安全候选不能包含特性/代价，选择总量允许普通entitlement+本版Boss日志数；活动Boss已经入账时实体必须0HP。拒绝重复来源/陌生轮次/伪造供给/缺schema，不覆盖好档。

v9原字节备份.legacy-v9；已有普通pending恢复ordinary来源，固定choices/token/RNG原样保留。Boss.upgrade_state一次性调整缺health_revision的hp/max_hp，新档字段标记防重放；旧动态Boss时点/部件/阶段和老箭保留，旧静态Boss只增加血量而保留原机制。已经记账的历史胜利无新补给/选择；死亡未入账及之后新胜利沿新奖励结算一次。兼容v1–v8、原字节归档、未来版本禁止覆盖与损坏恢复保持。

GameSession.end_run清空未领取来源和choices但保留日志，主动放弃允许choice未选为空。新局清空局内Boss日志/队列/收益和成长；金币依旧不能带出或兑换永久成长。永久分数/等级仍由会话同步，不因读档补发。

## 验证与产物

最终tools/run.ps1 -Mode Test：**960断言/0失败**。tests/test_boss_rewards.gd新增51项，旧test_boss增一项来源检查，共比908多52项。真实三箭致死在途恢复、一次奖励、最后一箭、待选退出继续、队列排序、供给上限、非法事务、v9归档/三倍比例仅调一次、历史胜利不补发、老箭/运动/RNG和固定普通候选、实际页面/结果记录均覆盖。旧T10-A/B数值与胜利边界断言已更新；纯战斗数学用固定960测试体不绑定生产平衡。

三个原生窗口脚本最终 **24+21+16=61断言/0失败**：

- test_boss_rewards_window.gd：最后一箭胜利得到3次/840金币/1200分，安全三选一；实际选择按钮、磁盘继续、历史/结果/缩放、六独立音效PCM。日志.tools/boss-rewards-window.log。
- test_boss_combat_window.gd：当前2880HP，真实弱点跨半血到1138，穿甲28阻挡/29通过到963，露弱点0穿甲后796；位置继续保持。日志.tools/boss-combat-regression.log。
- test_boss_window.gd：viewport真实鼠标拉弓2880→2608，损伤/消耗一次恢复，三箭胜利领取后普通靶重新开放。日志.tools/boss-input-regression.log。

本包八张artifacts/t10c-{health,reward,continued,reward-small,field-returned,history,result,result-small}.png，加七张t10c-combat-*和六张t10c-input-*，共21张已检查，1280×720/960×540无裁切或挡拉弓区域。旧t10a/t10b历史截图未覆盖，两个回归窗口支持--capture-prefix指定捕获前缀。窗口齐射fixture发射后重建未来stats，避免选择预览显示测试参数变化；在途箭仍保留原发射参数。

所有测试使用user://tests，未打开或更改玩家存档；捕获进程结束，无遗留窗口。完整100次自然推进可达性、后期金币经济和长期性能仍留待T09，不用这些断言代替平衡试玩。

## 下一轮T11-A

只增加三种可重复无代价普通项：基础伤害、穿甲、装填速度，将9种目录扩到12（6普通+6特性）。参数默认可配置，效果经calculate_raw_stats/evaluate_stats同源推导；不直接改有效stats或在途箭。更新通用encounter_comparison/description，当前非箭数普通项默认金币的分支需要扩展，不能把新增伤害/穿甲/装填预览误报金币。

普通和Boss来源都使用扩展安全池，过滤完全无收益的新候选（箭数/尺寸/伤害/穿甲/装填/次数接近上限的情况要看最终有效收益），保证安全选择；原固定三张候选原样继续，不能扩池后重抽或移走已展示未选特性。Boss池当前三普通，扩池后仍安全无代价并保留来源/token/胜利日志去重，T12-B才加免费特性强化。

选择与即时draws仍只执行一次，六原特性可并存、后续转化持续读取原始来源。不要同时实施T11-B/C/D的12新特性、精通或金币补给；完成A后停止并更新交接。
