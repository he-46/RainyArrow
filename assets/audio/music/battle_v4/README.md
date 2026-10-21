# 战斗曲第四轮：《林间交锋》

针对第三轮“像打扫战场，需要游侠正在与敌人作战”的反馈，重新编写主题。126 BPM、4/4、32 小节、约 60.95 秒。目标是轻装游侠交战时的敏捷与紧张：短促弦乐推进，长笛以简洁短句应答，低鼓提供重心，吉他轻点起音。旋律以四分音符为主，保留休止，不使用连续快速音阶。D 小调中短暂使用多利亚色彩；中段减少配器但保持节奏。

此版本已获用户认可并接入正式战斗与教程射箭场景。主页面使用 01《月下弓弦》，大厅及升级使用 03《营火来信》。此前候选音频均未覆盖。

- 本目录：可循环 OGG、可编辑 MIDI、catalog.json、音色许可。
- 试听 MP3、WAV 母版、检测结果：`artifacts/bgm/battle_v4/`，由 Git 忽略。
- 曲谱：`tools/compose_ranger_battle.py`，复用 `compose_focused_battle.py` 的 MIDI 导出、渲染和验证流程。

目标约 −17 LUFS；使用三轮连续演奏的中间轮，加循环起点的短过渡与环形混响，编码后检查声道、时长、峰值、接缝，并验证 Godot 的循环与节拍导入。MP3 用于试听，游戏循环使用 OGG。技术检查不等于主观听感确认。

## 制作工具与音色

使用 FluidSynth 2.6.1 和 S. Christian Collins 的 [GeneralUser GS 2.0.3](https://github.com/mrbumpy409/GeneralUser-GS) 离线渲染，并非真人演奏录音。完整许可随附 `GeneralUser-GS-LICENSE.txt`，包含作者对历史样本来源的说明。音色库 SHA256 为 `9575028c7a1f589f5770fccc8cff2734566af40cd26ed836944e9a5152688cfe`。工具与音色库留在被 Git 忽略的 `.tools` 中，不作为游戏运行依赖。
