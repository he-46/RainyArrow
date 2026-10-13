# T05 交接：四棵永久天赋树

已完成；下一轮只执行 T06 奇遇基础系统。T01–T04 交接保留为历史，本文件描述当前接口。验证日期：2026-10-09。

## 树结构与购买

TalentData / TalentCatalog / data/talents 独立定义 20 个节点：quiver、economy、damage、field，每树 suffix 为 root / left / right / master_left / master_right。根 3 阶，早期两分支各 2 阶，末端各 1 阶。早期需要根 1 阶，末端需要自己分支 2 阶；两早期分支可以同时学习，同树末端 exclusive_group 二选一。

根升级成本 1/2/3，早期 2/3，专精 4；单树可用组合满级花 20 点。PlayerProfile.invest_talent 校验目录身份、前置、互斥、满级及精确费用，talent_spending 保存真实投入；reset_talents 一次返还实际账本。恢复按目录拓扑顺序保留合法节点，未知、冲突或孤立节点不扣掉可用点。GameSession.purchase_talent / reset_talents 仅大厅可用，main 再限制路由为 talents。

TalentPage 是独立 UI，PageRouter 只负责创建与转发。点击节点查看说明，再点击学习；锁定节点也可以查看。selected_talent 在刷新和重置后保留。界面显示前置、费用、满级与互斥，重置免费且立即生效到永久档案。

## 当前数值

| 树 | 根（每阶） | 左分支（每阶） | 右分支（每阶） | 左 / 右专精 |
| --- | --- | --- | --- | --- |
| 箭袋 | 初始拉弓 +2 | 击倒回复率 +8% | 有效暴击回复率 +2% | 击倒再 +20% / 暴击再 +6% |
| 金币 | 全局金币倍率 +0.15 | 此前每次连中金币 +4% | 靶心击倒金币 +20% | 此前每次连中再 +6% / 靶心再 +60% |
| 伤害 | 基础伤害 +4 | 基础伤害 +8 | 穿甲 +2 | 伤害再 +20 / 穿甲再 +6 |
| 靶场 | 靶数 +1、尺寸 +0.10 | 靶数 +2 | 尺寸 +0.15 | 靶数再 +5 / 尺寸再 +0.70 |

容量最高 16 次拉弓；两种回复合计每次拉弓最多一次，概率最高击倒 36% 或暴击 10%。经济连击最多计算 5 次此前连续命中。限制配置在 data/talent_rules.tres。当前数值为可玩基线，T09 统一平衡。

新局复制 profile.talents 到 run.talent_snapshot，rebuild_stats 派生 talent_effects；开局只设置一次 initial_shots / shots_left。属性计算顺序：基础 → 天赋伤害/穿甲/金币 → 旧档兼容 → 新技能加法 → 数量伤害乘数 → clamp。当前局不读取大厅后来修改的树；重算/读档不返还弹药。

## 按拉弓顺序结算

RunModel.consume_shot 成功后 shot_sequence 加一。World._release 为每箭设置 shot_id 和 source_id，_attach_arrow 建立 pending_volleys[str(shot_id)]，struck 绑定这支箭。伤害、粒子、音效立即表现；待结算只保存 hit_id / event_id / effective / broken / critical / bullseye / reward_score / reward_gold。

World._settle_shots 数字排序拉弓编号；若最早的一次仍有箭，则后发完成的也等待。完成时发 shot_settled(id,hits) → main._settle_shot → session.settle_shot。会话用 last_settled_shot 避免重复；同次命中用 hit_id 去重。一次拉弓只要有有效伤害，combo +1；全部落空清零，多箭不自断连击。

击倒金币 = 基础金币 × (1 + combo_gold × min(combo - 1, 5)) × (1 + bullseye_gold，仅最后一击为靶心) × stats.gold_multiplier。最后一个全局倍率仍由 RunModel.record_defeat 唯一应用；gold_fraction 保存小数。有效非致死命中只延续连击，不发金币/经验。

每个接受的击倒尝试 kill_refund，有效暴击尝试 crit_refund，使用 run.rng；到每次拉弓回复上限后停止抽取。没有对应天赋不抽 RNG。两种回复在 World 最终 settle_volley 判耗尽前执行。defeat_recorded 兼容钩子仍保留；新天赋集中在 settle_shot，不要再连接信号重复回复。

目标死亡计时到期且 run.credited_defeats 含该生命 ID 后才补充，避免未结算击倒产生旧难度目标。长反弹飞行会推迟这次收益和补靶，T09 应试玩评估。当前不会阻止下一次拉弓；只是按发射顺序结算。

## 靶场与 v5 存档

无天赋保留原三靶位置；旧四靶保存也保留旧布局。天赋数量/尺寸在右侧生成网格，最多 15 靶 ×1.6 或 10 靶 ×2.3。面积变大不加血量；collision size 乘 target.scale，靶心阈值也随尺寸增大。移动靶限制在场内；替换生命保留尺寸与 anchor；支柱按缩放修正落地，血条和护甲文字保持可读大小。

Target.snapshot 增加 anchor/target_scale；Arrow.snapshot 增加 shot_id/source_id；World.snapshot 增加 pending_volleys；RunModel 保存 shot_sequence/last_settled_shot/combo。正常退出、大厅暂停、技能购买都捕获已伤害的目标与未入账命中、箭矢、资源、RNG，继续不会丢奖励或重新抽回复。

SaveStore VERSION=5，兼容 v1–v4；v4 先原字节另存 .legacy-v4。缺少编号的旧在途箭归入 0 号拉弓，按恢复顺序给 source_id，保留 hit_slots；只等待结束，不补造旧命中奖励。缺几何字段沿用旧坐标。后续新拉弓从 1 开始，旧已发击倒不重放。其他版本备份、损坏恢复与未来版本保护保留。

## 验证与截图

tools/run.ps1 -Mode Test：387 项断言、0 失败。tests/test_talents.gd 覆盖树约束/实际支出/重置、开局与读档、经济/连击/去重、真实最终一箭两种回复、放大碰撞、15 靶与巨型布局、待结算命中存盘和发射顺序、真实 UI 操作、v4 旧飞行迁移；T01–T04 回归继续保留。

实际渲染并检查 artifacts/t05-talents.png、t05-talents-built.png、t05-field-many.png、t05-field-giant.png。--preview 演示构筑只在 --test-mode 生效；截图参数下不因隐藏窗口失焦转入暂停，正式失焦暂停保持原行为。无长期压力/正式平衡/完整音效听感验收的承诺。

## T06 接入点

1. 每个接受的击倒累计阈值，pending_encounters 可多次累积；用固定候选数据与 seen_encounters（展示过的特性也不再显示）保存三选一。普通无负面项至少一槽，特性池耗尽用普通填补。
2. 一次 settle_shot 的全部命中、金币、经验和回复完成后再进入 CHOICE。不要在 record_defeat 的中途改变 phase，否则同次多箭后续奖励会被拒绝而丢失。
3. World._settle_shots 每次发射信号前检查 phase；若进入 CHOICE，后面已完成但尚未结算的拉弓队列保留。选择完恢复，继续按编号结算。main._refresh 当前只在 SHOP 暂停，需要加入 CHOICE，UI ALWAYS。
4. World 最终结束检查应继续依赖 pending_encounters == 0。最后一箭到第十击倒可先选择回复机会再判断结束；新局清空全部待选、已见与普通加成。
5. 本轮没有实现奇遇数据/候选、三选一面板或普通奇遇效果；T07 的分裂/增速/转换也未开始。保存原始加成并集中重算，保持在途箭发射快照。技能的六类数据和永久天赋不要与奇遇账本混写。
