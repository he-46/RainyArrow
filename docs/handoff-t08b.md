# T08-B 交接：互动教程

T01–T07、T08-A/B 完成；下一轮只做 T08-C 纯外观装扮，T09 另开轮。2026-10-09：703自动断言0失败（本轮新增64），12教程窗口断言0失败；七张教程截图已检查。历史交接保留，本文件为最新入口。

## 实际行为

主页面/大厅/暂停页进入教程，独立练习局完成四步：真实拉弓→靶心击倒→使用所得金币购买任意技能→再击倒一次，触发实际奇遇三选一并选择。练习次数不限，可暂停、失焦暂停、跳过、重新练习。未完成跳过不标记；完成立即写入教程记录，重玩不清记录，主页面显示「教程 · 重玩」。练习过程退出程序不续存，从第一步重玩；正式冒险保存正常。

练习为一个静止放大1.4倍的木靶，12血、100经验、24金币。真实收益在临时 session 结算，演示本局金币购买及永久等级/天赋点。失败会刷新易靶并补练习次数；大量非靶心击倒不提前弹奇遇。购买后明示将练习进度补齐到下次10次门槛前（通常9），再真实击倒生成真实池三选一，保留安全普通和含代价标记；不会影响正式run。

## 组件与边界

scripts/gameplay/tutorial_controller.gd 拥有独立 GameSession/PlayerProfile/RunModel/ArcheryWorld，无正式 session 或SaveStore引用。Step DRAW/BULLSEYE/UPGRADE/ENCOUNTER/COMPLETE；world.draw_released 为成功发射后观察信号，_settle 对实际 shot_settled 结算并判定靶心。_prepare_target 专用易靶，_refill 补练习次数，_prepare_encounter 只对临时run补演示进度。run.changed 调 _refresh；升级指导/SHOP/CHOICE/完成或手动暂停冻结世界，模态前复位震屏。

scripts/ui/tutorial_page.gd 用真实GameHUD技能/奇遇组件，coach在射箭时右上、卡片时下方，不覆盖购买/返回/选择按钮。底部明示教程收益隔离，完成页重述金币只本局、等级天赋永久。GameHUD新增 pause_button 引用，教程暂停时文字为「继续」。练习教程及音效应用正式设置；M同步当前教程。

main._start_tutorial 记录原router.route、正式 world.process_mode 和奇遇历史开关；取消未发射拖拽并保存正式世界，session.return_to_lobby，正式 world DISABLED且隐藏。仅隐藏不足以防止其在教程解暂停后运动。临时world PAUSABLE、控制器/UI ALWAYS。箭碰撞原已有按父world过滤，练习箭不会打正式靶。

main._stop_tutorial dispose临时场景/页面后恢复正式process_mode、原路由/历史状态。range直接 _show_range 同一对象（包含结束状态，不自动新开局），原SHOP/CHOICE/历史继续暂停；来自暂停先回暂停再继续。主页面/大厅/未实例化正式世界不因此生成新冒险。正式run的金币/经验/天赋/装扮/箭属性/快照/RNG/固定候选均保留。

main._tutorial_completed 只写正式 profile.tutorial_completed；GameSession.save_payload 将此已有字段与 settings 同样独立合并，不混入较新战斗XP或练习收益。没有新增持久化结构，仍v7。所有正式存档写入只引用main.session/world，从未引用教程session/world。

## 验证

tools/run.ps1 -Mode Test：703/0，T01–T08-A回归+64新断言。tests/test_tutorial.gd 包含真实viewport鼠标操作/落空/命中/技能卡/奇遇卡、完成标记独立保存/加载、暂停失焦/跳过/重玩、过期offer、21非靶心击倒不弹早期奇遇、正式在途箭/RNG/候选/SHOP/历史/原入口/懒加载快照保留。

非headless --script res://tests/test_tutorial_window.gd -- --test-mode：12/0，.tools/tutorial-window.log；actual箭弹道、真实卡片购买/选择和返回。artifacts/t08b-tutorial-{draw,bullseye,shop,encounter-field,choice,complete,small}.png均查看，1280×720/960×540无裁切、按钮不被指导覆盖。tests均user://tests，不修改玩家档，无残留进程。T08-A窗口13项结果继续留在此前交接，本轮未重复跑无关全屏/音量。

## 下一轮 T08-C：纯外观装扮

只做少量弓、箭、角色外观、解锁说明、选择应用与持久化，然后停在T09前。PageRouter._feature("cosmetics") 仍占位，替换独立组件；按永久等级/累计击倒解锁，不消费本局金币，不改战斗参数/碰撞半径/子箭伤害/在途stats。

PlayerProfile已有 unlocked_cosmetics（默认bow_default/arrow_default/archer_default）、equipped_cosmetics字典和from_dict解锁列表恢复；目录应校验类别、未知/不符合条件的外观，保存选择且退出重启仍保持。GameSession.save_payload 当前独立合并 settings/tutorial_completed；按需要把纯外观选择以独立档案字段合并，避免用新装扮覆盖旧战斗checkpoint。

现world用_draw手画角色/弓，Arrow._draw手画箭杆/箭头/羽毛，采用少量不同配色/造型即可先交付真实外观；大小/碰撞仍读原stats。HUD/教程可复用装备外观，但教程收益不得解锁正式装扮。最好共用外观配置和预览，避免为展示复制战斗模型或把界面逻辑塞进main。测试永久条件/未知类别/即时应用/存档/在途不改数值/教程不解锁正式内容，以及实际画面。
