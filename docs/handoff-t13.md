# T13 交接：有限补给与金币循环

2026-10-09。T01–T08、T10、T11、T12-A/B、T13完成。下一轮仅实施 **T14-A：普通、困难、地狱三模式**，之后T14-B本地前三榜，再执行T09-A/B/C。工程D:\AzVGames，Godot4.7.2标准版，Play.cmd可玩。先读本文、expansion-plan.md、tasks.md。本轮没有实现难度或排行榜。

## 本轮交付

技能页新增拉弓补给：每段最多购买2次，每次回复1次拉弓，与齐射支数无关。初始段从开局开始，后续段从每次真实Boss胜利开始。价格按本局累计购买次数计算：ceil(24×1.6^次数)，前四次24、39、62、99金。胜利仅恢复段额度，价格继续递增；回大厅、设置、教程、继续存档、开关面板均不恢复额度或降低价格。默认可调，长期平衡仍待T09-B。

无拉弓机会时先结清所有母子箭、命中收益、天赋回复和普通/Boss奖励。如果奖励恢复了拉弓则正常继续；否则有额度且买得起时暂停，显示“购买补给 / 结束本局”。买入回复1次，恢复当前世界；拒绝立即结束。缺钱或额度耗尽直接结算，不提供不可用按钮。终局清空钱包，不能通过补给或回复复活。

技能页和结果页分别显示本局累计收入和消费，补给行显示段余量/本局总购买次数，悬停显示精确当前/下一次价格。基础技能、精通、特性强化、补给共用消费账本；结束摘要保留账本与总购买次数，剩余金币记录为丢弃，不算消费。显示金额可缩写万/亿。钱包发放统一遵守既有恢复上限10亿，累计收入仍记录实际奖励，避免超上限钱包无法保存。

无限练习教程隐藏正式补给行，避免无用按钮；复用技能/消费显示，正式局收益保持隔离。从教程返回也保留原补给选择。

## 接口与保存

- `SupplyRules` / `data/supply_rules.tres`：limit=2、draws=1、first_cost=24、growth=1.6。`parameters()`在新局复制到Run，旧局继续不重新采样资源。价格限10亿，达到上限前判断指数，避免溢出；保存参数限定limit/draws1–10、first_cost1–10亿、growth1.01–10。
- `RunModel.Phase.SUPPLY=5`追加，原PLAYING/SHOP/CHOICE/WON/LOST数字不变，`is_finished`仍只看WON/LOST。Main在SUPPLY暂停世界，阻止发射/技能/历史变更，导航和独立设置可用。
- `supply_total_bought`本局总次数，`supply_segment_bought`本段次数，`supply_segment`当前Boss胜利基线，`supply_offer_id`末箭选择身份。`record_boss_defeat`在生命ID首次入账时重置段额度；重复/历史胜利不刷新。
- `supply_price/remaining/available/token/can_buy_supply/buy_supply/decline_supply`。购买需SHOP或SUPPLY、非暂停、无待选奖励、足够金币/余量/容量；token含total/segment/offer_id，旧点击拒绝。SHOP购买保留暂停，SUPPLY购买改回PLAYING；不改stats、RNG、在途属性或装填。
- `_spend_gold`用于四类局内支付；`gold_spent`与`gold_spending={basic,mastery,traits,supplies,legacy}`同步。Boss免费强化不记消费。
- `settle_volley`由World在所有家族清空后调用：先offer_encounter，再决定SUPPLY或自然LOST。选择收益和天赋回复仍走原入口，不能绕过生命/命中/整族去重。
- `ArcheryWorld.build_field`恢复SUPPLY不因零箭重新设置waiting_for_settle；原PLAYING零箭恢复仍会补做结算。此修复保证继续补给选择后能立即再次保存；旧母子箭恢复逻辑保持。

封套 **v18**，Run `economy_schema=1`。当前写入必须有完整参数、购买计数、消费分类；校验整数/范围、段与Boss胜利一致、总次数历史界限、分类总和、补给累计实际价格。SUPPLY必须0箭、无待选、有效正token、未结束、有额度且买得起；世界必须无箭/无待结算族群/waiting=false。非法事务拒写，不覆盖好档。精通schema1、特性schema1、箭combat_schema3、world.projectile_schema1、Boss combat_schema1/旧0和health_revision2保持。

旧v17原字节先归档`.legacy-v17`再迁移。补给从当前Boss胜利基线开始，总购买0、本段0；旧构筑、固定候选、收益、RNG、实体、母子箭与装填保持，不重抽、不重发Boss奖励。旧活动局支出只能从floor(累计收入)−钱包重建，归legacy；旧终局使用同run_id摘要中清空前钱包推算，无摘要不伪造历史支出。旧终局仍终局。以前各版本的中性箭参数、生命比例迁移保持。重复读取v18不再次迁移，未来版本保护与完整事务备份回退保持。

## 验证与截图

`tools/run.ps1 -Mode Test`：**1874断言、0失败**，`.tools/test.log`无脚本错误。新增`tests/test_supplies.gd`覆盖交易/旧token/巨大钱包仍限2次、Boss额度一次重置/价格不重置、四类消费、上限、末箭购买/拒绝/缺钱/额度用尽、天赋回复/普通回复优先、全部家族结束后选择、旧箭与装填/RNG不变、真实世界恢复再保存、v18字段拒写/好档回退/未来保护、v17字节备份/在途恢复/旧终局不复活。

`tests/test_supply_window.gd`：**105/0**，`.tools/supply-window.log`。通过viewport鼠标事件点击购买/结束，检查双次购买、旧点击、回大厅磁盘Continue、六精通卡片、真实Boss末箭胜利与下一段62金、真实最后一箭过边界/购买续射/拒绝清钱、再存档、教程返回、缺钱/额度用尽。隐藏窗口的鼠标按下/松开同一输入批次，避免系统悬停事件打断测试；不是自动重试或补发购买。

精通窗口回归 **145/0**（含双转换、联动、代价、封顶、100阶和大价格），Boss奖励窗口 **25/0**，子箭窗口 **52/0**。原测试的“金币足够但箭耗尽直接结束”改为先显式拒绝补给再检查终局，保留所有收益/经验/去重断言。

`artifacts/t13-*.png`共 **17张**：skills-first/bought/limit、mastery-and-supply及small、boss-reward/new-budget、last-draw-choice及small/continued/rescued、second-choice、tutorial-skills、result-declined及small/poor/limit。1280×720与960×540已检查，六卡、补给状态/价格、消费说明、选择/返回按钮可读；教程实际返回按钮在教练框之上。旧精通/奖励/子箭窗口捕获也已更新。测试存档全部在user://tests，未读写玩家档，所有进程退出。

JSON把24次1/120累加的clock=0.19999999999999998写读为0.2（一ULP），窗口仅clock允许≤1e-12，其余世界/计数/钱包/token/参数/RNG严格比较；原T12伤害/尺寸序列化例外保持。没有放宽保存校验。

## 下一轮：T14-A

仅实现三模式选择、锁定、数值采样和版本化恢复，暂不做排行榜或T09。用户已确认：困难普通HP×1.5、BossHP×2、普通/Boss得分×1.5；地狱继承这两个血量倍率，提高普通靶成长，**总得分×2以普通模式为基准**。地狱普通HP线性成长先用每击倒+10%基础HP，普通/困难沿用+6%，该成长值是可调开发默认。金币、护甲成长、Boss逐轮成长、奖励频率和补给规则保持。

首普通木靶为48/40分，困难72/60，地狱72/80；首Boss普通2880/1200分，困难5760/1800，地狱5760/2400。模式在新局选择，本局回大厅/继续不改；永久经验使用同一已乘模式得分，不能双乘。独立mode_id和采样配置，不把difficulty_step击倒数变成枚举。旧档普通、不补历史收益、不放大现存实体；v18字节备份到下一版本，保留补给段/价格/选择、消费、精通/强化、固定Boss奖励、在途/受损状态。具体完整验收见expansion-plan.md的T14-A。
