# V06：构筑界面与图标

2026-10-18 完成。下一包 V07：全流程视觉与性能验收。

## 已接入

- `BuildIcon` 提供统一像素符号：金币、拉弓、经验、护甲、穿甲、暴击、箭数、大小、弹射、能量等。18 件神器用主符号与右下联动符号组合；三个主动技能复用现有专属图标。图形层不接收输入，不使用战斗随机源。
- 六类技能卡分出名称、等级／价格、效果说明与实际升级比较。精通用青绿色，购买不可用时弱化；整张卡仍可点击，保留原购买逻辑、完整文字与悬停说明。六卡、补给和返回按钮在小窗口中均可见。
- 六格神器背包增加图标、简短核心效果、强化阶数及明确“含代价”文字。右上角“…”打开只读详情，显示完整效果、当前参数、下一阶成本与比较，以及丢弃规则。最高阶有明确状态；满包替换页也能打开详情，原确认操作保留。
- 四棵天赋树增加树徽，36 个节点增加语义图标与阶层点。已学路径、可学、前置未达和互斥状态可区分，所有节点仍可查看说明。已经选另一专精时，优先显示“互斥”；实际购买限制不变。购买、重建界面和往返主动技能页保留当前选择及滚动位置。
- 八类契约使用对应图标，当前档位和预设有选中样式；局内锁定保持。主动技能页显示专属图标、能量标记与已装备样式。共享按钮选中、悬停、按下、禁用与焦点样式。

无新增存档字段、外部图片依赖或数值规则；原强化价格、成长、收益、奖励池与碰撞继续沿用。

## 主要文件

- `scripts/ui/build_icon.gd`：公共与组合图标、神器摘要、天赋／契约符号映射。
- `scripts/ui/upgrade_card.gd`：分层技能卡与点击输入。
- `scripts/ui/game_ui.gd`：共享卡片状态样式。
- `scripts/ui/game_hud.gd`、`encounter_panel.gd`：技能、HUD 资源标记、神器背包／详情／选择。
- `scripts/ui/talent_page.gd`、`page_router.gd`：树图状态与滚动保持。
- `scripts/ui/contracts_page.gd`、`active_skill_page.gd`：契约与主动技能页面。
- `tests/test_visual_v06_window.gd`：真实点击、导航、只读状态与截图。

## 验证

| 检查 | 断言 | 失败 |
| --- | ---: | ---: |
| `tools/run.ps1 -Mode Test` | 3175 | 0 |
| `test_visual_v06_window.gd` | 83 | 0 |
| `test_mastery_window.gd` | 145 | 0 |
| `test_backpack_window.gd` | 52 | 0 |
| `test_contracts_window.gd` | 107 | 0 |
| `test_talent_expansion_window.gd` | 201 | 0 |
| `test_trait_upgrades_window.gd` | 113 | 0 |

原生窗口合计 **701** 项。覆盖实际点击购买与详情开关、36 节点、互斥专精、滚动保持、契约锁定、六格替换及丢弃、精通、大额价格、最高强化与 Boss 免费强化。打开神器详情前后完整局内状态相等，金币、构筑和 RNG 不改变。

技能卡布局检查改为验证实际子标签的边界与相互间隔，修正过紧的卡片高度和底部空间。旧神器强化窗口脚本含 12 件神器的迁移压力夹具，先前默认按现代契约开局，存档验证会拒绝超容量；本轮显式按旧模式建立该夹具后重跑通过，游戏存档校验不变。

已核对 960×540、1280×720 截图，包括六格背包、转换类详情、天赋深层互斥、技能／精通与 Boss 免费强化的长标题。检查使用 `.tools/v06-profile` 隔离测试环境。Godot 仍有系统证书库读取警告，本地窗口和测试正常；1920×1080 全页面、密集构筑性能、跨 DPI 与正式导出不在本包结论内。

## 本地截图

截图均位于 Git 忽略的 `artifacts/`：

- `v06-skills.png`、`v06-skills-small.png`：六类技能卡。
- `v06-backpack.png`、`v06-backpack-small.png`：六格神器背包。
- `v06-artifact-details.png`、`v06-artifact-details-small.png`：完整规则、转换代价与强化比较。
- `v06-talents-roots.png`、`v06-talents-specialization.png`、`v06-talents-small.png`：树徽、进阶节点与互斥。
- `v06-active-skills.png`、`v06-contracts.png`、`v06-contracts-locked-small.png`：装备及契约状态。
- `v06-artifact-icons.png`：18 件神器图标的测试展示，不是新增玩家图鉴功能。
- `t16-full-choice.png`、`t16-replacement-list.png`：三选一及满包替换。
- `t12b-boss-free-choice.png`、`t12b-free-previews-small.png`：免费强化长标题与比较。

## 下一包

V07 对照 `visual-upgrade-plan.md` 检查所有页面、Boss 两阶段、三技能和密集箭矢；记录硬件、分辨率、构筑与测量条件。优先确认多箭／分裂／弹射／回响同屏的清晰度与帧耗时，完成暂停、减少特效、继续读档和导航验收，再衔接 T09。未经实际测量，不宣称低配性能或像素完美缩放。
