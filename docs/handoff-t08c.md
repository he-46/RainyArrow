# T08-C 交接：纯外观装扮

T01–T08 全部完成；下一轮仅 T09-A 集成流程与反馈验收，数值试玩和压力/桌面收尾另开轮。2026-10-09：782自动断言0失败（本轮新增79），16装扮窗口断言0失败；七张画面检查完成。本文件为最新入口，旧交接保留。

## 实际内容

大厅装扮页九套：每类别三套，默认直接拥有；月白银弓Lv3、霜蓝羽箭Lv4、赤霞行者Lv5；余烬长弓25累计击倒、金翎猎箭50、夜幕猎手100。点击免费装备，已装备/未解锁禁用，预览所有样式与当前组合，标注等级/次数条件。仅换配色和装饰，不花金币，不改伤害/箭数/初速度/尺寸/碰撞/快照。

当前角色/弓/待发箭/在途主箭与子箭即时应用，下一发和分裂同一外观；新局/继续/教程使用当前搭配。默认可随时换回。解锁资格按永久进度重建，未达条件/未知/错类别外观回默认；教程收益不得解锁正式内容。

## 模块与持久化

scripts/data/cosmetic_data.gd：Resource，id/slot/title、required_level/required_defeats、primary/secondary/accent、style。eligible为两个条件都满足（实际目录每个新样式只提高一种）；condition用于中文条件说明。CosmeticCatalog.ALL与data/cosmetics九资源，find/default_for/equipped检查ID/类别。数据仅视觉，无战斗字段。

PlayerProfile.refresh_cosmetics按level/total_defeats生成unlocked列表，保留资格已满足的装备，其余回默认；record_defeat在升级后刷新，from_dict从实际XP和击倒重新推导资格，不信任存档供应的unlocked列表。equip_cosmetic拒绝未知/锁定/重复。T01原bow_test虚构样本更新为真实Lv3已达条件bow_moon，保存加载语义继续回归。

CosmeticsPage独立Control：左侧组合预览/当前三样式名称，右侧三类别各三张预览/条件/装备按钮；9预览无需构建战斗世界。CosmeticPreview与CosmeticDrawing共用像素形状，后者static archer/bow/arrow只调用CanvasItem.draw方法。世界_draw角色/弓与Arrow._draw复用；角色衣服/饰条，弓颜色/握把/端部装饰，箭杆/头/羽毛/轨迹改色。

ArcheryWorld.appearance是复制的三ID字典，apply_cosmetics更新当前所有箭的Arrow.cosmetic并queue_redraw；_attach_arrow对未来发射/子箭/读档箭共用。Arrow.cosmetic不进snapshot，装饰仅绘制；圆形箭头绘制半径仍stats.collision_radius，旋转/position/velocity/伤害/bounces/hit_slots/effects/RNG保持。apply_cosmetics支持重复传入world.appearance，不因别名清空选择。

main仅在router.route=cosmetics且session.in_lobby接收cosmetic_equip，更新世界绘制并保存，刷新页面；_create_world读档后应用装备；教程start额外可选loadout参数只复制外观，restart继续用复制，不参考练习profile的解锁资格。

GameSession.save_payload独立合并equipped_cosmetics；unlocked列表仍跟随战斗checkpoint的XP/击倒，避免保存新解锁而丢掉其来源。正常装备页进入前已保存当前世界/永久进度，所以合法选择可以读回；读档仍按保存的进度重建资格。字段原已存在，封套v7/Projectile schema不变，旧档不主动重写/迁移。

## 验证

tools/run.ps1 -Mode Test：782/0，tests/test_cosmetics.gd79新断言。目录与解锁边界、资格恢复与非法选择、金币/永久成长不变、独立checkpoint、真实装备按钮/组合预览、真实贯穿分裂的2根+2子族即时换色/整族快照精确磁盘恢复、未来发射、教程独立与重玩、lazy Continue/默认回退均覆盖。

非headless --script res://tests/test_cosmetics_window.gd -- --test-mode：16/0，.tools/cosmetics-window.log。逐项实际按钮装备，弓/箭/角色区域像素改变，原箭world.snapshot与9次剩余拉弓不变。七张 artifacts/t08c-{cosmetics-locked,cosmetics-unlocked,cosmetics-equipped,cosmetics-small,flight-default,flight-cool,flight-warm}.png已查看；1280×720/960×540布局正常。全部测试user://tests、不改玩家档，捕获进程已退出。未重复扩大T08-A/B窗口检查。

## 下一轮 T09-A：集成流程与反馈

只做完整流程和可区分反馈，不顺手做所有数值/压力/正式导出。T09按A完整流程/反馈→B数值试玩→C压力和桌面收尾拆轮，均未开始。

串起首次主页面、教程、正式打一局、技能/奇遇、耗尽结算、天赋、再开局、退出/读档继续。已有782断言包含很多分散路径，新增完整场景检查应验证实际组合边界和收益去重，避免复制原测试。

现音效仍AudioService合成占位，draw/release/hit/bullseye/break/coin，VOICES10，Bow/Impact/UI/Music（暂无曲目）。命中/击倒已有浮字与震屏，暴击仅“!”和命中音高；回复“+1 DRAW”，永久等级/技能/奇遇多处共用coin。让命中、击倒、暴击、回复、技能购买、永久升级、奇遇出现/选择可区分，检查大量同帧命中时声音/浮字可读性。保持声音随机与战斗RNG分开。

收益仍按拉弓编号等待整族结束，长反弹可能推迟入账/补靶，勿未经T09-B数值体验评估随意改结算语义。主箭最多32、子箭预算64、箭寿命12秒、每步接触最多64，单机实际压力T09-C再做；当前测试通过不代表平衡或长期性能完成。必要UI/音效修复与窗口实玩后记录手感、限制、下一包接入点。
