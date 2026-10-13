# T08-A 交接：完整设置

T01–T07、T08-A 已完成，下一轮仅 T08-B 互动教程，T08-C 装扮和 T09 另开轮。2026-10-09：639 自动化断言、13 实际窗口断言均0失败。历史交接不改，本文件为最新入口。

## 可用内容与接口

主页面、大厅、暂停页可进入独立 SettingsPage，三音量（总/音效/音乐）和静音/全屏/命中震屏/瞄准轨迹立即应用并自动保存，提供试听。音乐暂无曲目，页面明示保留音量。M/HUD/设置页静音一致，快捷键不重建控件或重置滑块。

PlayerProfile.set_setting(key,value) 检查已知字段，布尔严格类型、数字有限并 clamp0–1；from_dict 已有同等边界。main._apply_settings 启动/设置/快捷键共用：AudioService.apply_settings、world.apply_settings、非headless实际全屏、router.sync_settings、HUD刷新。设置仍在 profile.settings，无新增存档字段，继续 v7。

AudioService 把线性音量转 dB，加现有五总线 trim。音效控制 Bow/Impact/UI，音乐独立Music，Master mute 为全局静音或音量零；其他总线零音量也 mute，再升音量复位。项目原 audio/default_bus_layout 路径错误导致只有 Master，本轮修正为 audio/buses/default_bus_layout，实际五总线已验证。声音仍是合成占位，未完成正式听感验收。

PageRouter.settings_return_route 记录进入设置前页面；back_destination 返回它，不覆盖 pause→range。设置→暂停→靶场原阶段恢复，CHOICE/SHOP继续暂停。主页、大厅独立往返不创建新世界。

World._on_hit 调 _kick_shake，命中1.3/击倒3.0逻辑像素，_update_shake 短暂平移 viewport.canvas_transform，HUD CanvasLayer不受影响。rest_canvas 在 _ready 保存，离开靶场/reset_shake/禁用/退出恢复；_aim_position 抵消视觉平移后映射输入。箭/靶位置、碰撞、snapshot、战斗 RNG 不改。trajectory_guide 仅控制拖拽时的预览点，拉力条保留。后续教程若创建第二个临时世界，务必在隐藏正式世界时 reset_shake，销毁临时世界后恢复同一视觉设置，避免争用 viewport canvas。

_save_checkpoint 正常边界保存完整当前世界；拉弓期间不更新 combat checkpoint，GameSession.save_payload 只合并最新settings，不将新XP与旧世界混在一起。

## 验证与截图

tools/run.ps1 -Mode Test：639断言0失败，test_settings新增41。原T01–T07保留；类型/边界、真实控件/总线/静音同步、实际保存恢复、在途箭、固定候选、视图震动不改物理和瞄准、独立设置 checkpoint 均已覆盖。

窗口脚本 tests/test_settings_window.gd：非headless启动 --script res://tests/test_settings_window.gd -- --test-mode，13断言0失败。实际全屏往返、五总线/试听声部、轨迹图像差异、视觉复位通过。生成并查看 artifacts/t08a-{settings,fullscreen,settings-small,guide-on,guide-off}.png，分别含1280×720/1920×1080/960×540。测试使用 user://tests 与工作区临时音频/日志，不修改玩家档；窗口恢复并退出，无残留进程。

## 下一轮 T08-B：互动教程

只做互动教程，完成后停止。现 PageRouter._feature 的 tutorial 仍是静态说明，替换独立组件；教程需要玩家实际拉弓、靶心、金币购买技能、奇遇三选一，支持跳过和重玩。

使用单独临时 RunModel/GameSession/PlayerProfile/ArcheryWorld，教程得分/金币/天赋/RNG/击倒不得写入正式 session。正式局/世界对象暂停保留，教程退出回原入口并恢复在途箭、SHOP/CHOICE候选，不消耗/补发正式拉弓。完成只更新 profile.tutorial_completed；GameSession.save_payload 目前只独立合并 settings，教程完成记录应同样按独立档案字段合并，不能混入教程收益或覆盖战斗 checkpoint。

教程应用当前设置，音效复用 AudioService，控制画面绘制/暂停模式别与正式世界争用。按需要给教程增加小而明确的观察事件接口，避免将大量教程逻辑塞进 main 或改变正式数值。测试临时收益隔离、真实引导推进、跳过/重玩/恢复、独立完成记录和实际画面。
