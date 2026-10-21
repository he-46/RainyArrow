# 战斗曲第二轮：换乐器对比

用户已接受第一轮01《月下弓弦》和03《营火来信》，二者音频原样保留。第一轮战斗曲暂不采用；此轮三版都沿用02《万箭破晓》的原创主题、和声与148 BPM，均48小节、约1:18。主奏按音区作八度调整，并减少密集伴奏、去掉原芯片主奏及连续高频踩镲，便于比较配器方向。版本尚待试听确认，未接入游戏自动播放。

| 版本 | 主奏和配器 | 方向 |
| --- | --- | --- |
| A 林野木琴 | 马林巴、尼龙吉他、拨奏弦乐、康加手鼓 | 轻巧、森林冒险 |
| B 疾行钢琴 | 钢琴、拨奏/长弦乐、大提琴、定音鼓 | 旋律清楚、持续推进 |
| C 远征号角 | 圆号、短弦乐、大提琴、定音鼓和低战鼓 | 厚实、出征感 |

这里的乐器由采样音色库渲染，不是现场录音。旋律与编曲源在tools/compose_battle_variants.py；可编辑的.mid、可循环的.ogg与检测catalog.json位于本目录。试听MP3、24秒快速比较、WAV母版及试听页位于artifacts/bgm/battle_v2，仍属于Git忽略产物。

三版统一约−17 LUFS；录制三轮后截取中间轮，在起点45毫秒用下一轮的连续波形过渡，保留拍长并消除自由振荡/释放尾音引起的跳变；短混响采用环形处理。编码后检查长度、声道、峰值与接缝，Godot导入Loop开启。MP3用于试听，游戏循环优先用OGG。技术检测不代替主观听感和实际游戏混音。

## 音色来源与制作工具

- GeneralUser GS 2.0.3，S. Christian Collins：[官方项目](https://github.com/mrbumpy409/GeneralUser-GS)、[完整许可](https://github.com/mrbumpy409/GeneralUser-GS/blob/main/documentation/LICENSE.txt)。许可原文随附GeneralUser-GS-LICENSE.txt，包含作者对样本来源的说明。原始.sf2仅在本地.tools/soundfonts，不打包进游戏音乐资源。
- 实际音色文件SHA256：9575028c7a1f589f5770fccc8cff2734566af40cd26ed836944e9a5152688cfe。
- FluidSynth 2.6.1：[官方发布](https://github.com/FluidSynth/fluidsynth/releases/tag/v2.6.1)，仅用于本地离线渲染，未作为游戏运行依赖。原始工具和音色库在.tools目录，Git忽略。
- 复现需要numpy、imageio-ffmpeg，以及上述FluidSynth可执行文件和SoundFont，路径见脚本顶部；原曲谱复用compose_bgm.py。
