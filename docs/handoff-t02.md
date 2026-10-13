# T02 交接：改名、主页面、大厅与导航

状态：已完成。下一轮只执行 T03，范围见 `tasks.md`。

## 本轮结果

- 工程、窗口、主菜单、HUD 和 README 使用《箭如雨下》。存档固定目录不改，旧名仅保留在迁移路径和历史记录。
- 独立的程序绘制像素森林主页面：开始、继续、设置、教程；无活动局禁用继续。主页不创建 RunModel/ArcheryWorld。
- 开始 → 大厅 → 去射箭才真正开局。有活动局点开始需确认放弃，取消保留全部状态；永久档案不清空。继续 → 大厅 → 继续射箭。
- 大厅有去射箭、天赋、装扮，以及永久等级/天赋点。暂停页可返回大厅；暂停中的金币只属于该局。
- 天赋、装扮、设置、教程各自为独立页面。设置复用静音，教程是静态操作说明；完整能力分别由 T05/T08 完成。
- 保留原型商店、三选一、五关流程，本轮未改变数值和命中逻辑。

## 文件和接入点

- `scripts/main.gd`：组合根，监听 UI action，管理 `_navigate / _enter_range / _new_run / _start_to_hub`、存档和音频。
- `scripts/ui/page_router.gd`：同一时刻一个非战斗页面；`route` 为 home/hub/range/settings/tutorial/talents/cosmetics/pause。功能页保存 return_route；通过 `action(id, value)` 发出请求。
- `scripts/ui/game_hud.gd`：显示数据、原型商店、赐福和结算，发相同 action 信号；T03 在这里替换阶段显示与结算。
- `scripts/ui/game_ui.gd`：共享主题、字体与控件工厂。
- `scripts/ui/menu_backdrop.gd`：不使用玩法对象或战斗 RNG 的像素背景。
- `tools/run.ps1` 的截图 View 新增 hub/settings/tutorial/talents/cosmetics/pause。

## 必须保留的边界

- `world` 在主页或刚开始的大厅可能为空，不能假设随 main 创建。
- `_create_world(snapshot)` 只用于初次进入/读档/新局，返回大厅后继续必须复用现有 world，不重建靶子或刷新拉弓次数。
- 大厅暂停场景树，同时 `GameSession.return_to_lobby()` 挂起 run；进入靶场调用 resume_run。即使有在途箭矢，内存恢复也使用同一对象。
- 无世界时保存沿用 session.world_snapshot，不覆盖为空对象；有在途箭矢仍保存之前的已结算检查点。
- 结束页面暂停后返回不隐式新开局；回大厅后点击去射箭才创建新局。
- UI 不直接修改经济/成长数据，只请求组合根调用模型接口。
- profile 永久等级与 run.prototype_level 是两套数值，T03 必须替换旧关卡经验而不是混用。

## 验证

`tools/run.ps1 -Mode Test`：160 项断言，0 失败。T02 新增 29 项导航/生命周期检查；包括真实鼠标拉弓后的在途暂停恢复、同一世界/目标引用、反复进出不回血不补箭、懒加载读档、新局取消、结束页恢复。

实际 OpenGL 生成并查看 artifacts 下 menu/hub/play/tutorial/shop/talents/settings 七张截图，布局正常。测试和渲染无脚本错误；沙箱的系统根证书读取错误不影响离线验证。

## T03 起步建议

先读 GameSession.record_defeat、RunModel.record_defeat、ArcheryWorld 靶子破坏回调，再统一击倒事件及去重。将固定五关替换为连续补靶，接入血量/护甲/奖励增长和永久经验，最后调整 GameHUD。沿用本轮的开始/继续/大厅流程与状态回归测试；更新教程中的操作说明时不提前实现 T08 互动教程。
