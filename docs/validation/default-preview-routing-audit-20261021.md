# 默认播放器入口审计（2026-10-21，只读）

结论：本轮检查的默认 F5/F6/F7、Preview 菜单和主工具栏已汇入内置 uBMplay 预览窗口及统一音频外壳，没有在这些默认链路发现外置播放器或单文件纯音路径。显式外置菜单仍保留。此结论是源码路由审计，不等于 bundle资源、设备播放、视觉或整合验收通过；未运行 UI/测试、未改产品，未等待 Grok DI。

## 实际路径

- **菜单/快捷键：** LegacyChromeMenu.swift:67–76定义 TBPlayB/F5、TBPlay/F6、TBStop/F7；MenuBuilder.swift:507–512加入主Preview菜单，618–632绑定 MainWindowController.performChromeCommand，667–675映射NSF5/6/7且modifierMask为空。MainWindowController.swift:671–697将三command转为对应handler。编辑器ChartRenderer.swift:2369起直接处理的是F1/F2/F3工具选择，未见独立F5/F6/F7旧播放路由。本工作区没有独立LegacyChromeKeyboard.swift或同名类型，实际功能键证据位于MenuBuilder。
- **工具栏：** MainWindowChrome.swift:612–614定义同三command；MainToolbar.swift:89–91按钮向onCommand送name；MainWindowContentView.swift:1373接handleToolbar，1874–1879调用actions；MainWindowController.swift:232–235经setPreviewPlayback接入同三个方法。无外置分支。
- **默认窗口/后端：** AppDelegate.swift:21–39创建PreviewWindowController、documentSource及三handler；109–119先showPreview，再playFromStart/playFromPointer/stopPlayback。PreviewWindowController.swift:592取state.previewPlayer，902–909调用player.playChart，LegacyPreviewAudio.swift:984内部为PreviewUnifiedAudioSession。ApplicationState.swift:8–17创建共享LegacyPreviewAudioPlayer并注入OGG/WAV解码。名称Legacy不表示默认链仍是旧纯音播放器。
- **未保存BMS/BMSON：** MainWindowController.swift:432–440按内存bmsonDocument优先，否则previewReadOnlyChart；480–523读取session.currentBytes，以当前raw缓存/展开RANDOM并建立chartSession，不要求保存到磁盘。526–581由同session构造timing、notes、1P/2P lanes、BMP和visualChart；583–612由内存BMSON的soundChannels/BPM/STOP/模式/BGA/layer/poor构造context。Here均取content.lastPointerBeat，资源目录来自fileURL/filePath父目录；尚无路径的新文档可以构造context，但相对资源目录缺失的可解析性不能据此担保。
- **1P/2P/BGA绑定：** PreviewWindowController.swift:886–909将context.visualChart/timing/目录先bindClock再playChart；1132–1182据同fromBeat建立索引与bindSurfaces。2047–2080将同chart/timing交两个playfield和BGA，showPlayback2082起将同beat/chartElapsed发两侧与BGA；2192起applyPlayerSide同步两playfield。源码说明共享context，未验证最终像素、双侧裁切或外置资源的bundle查找。
- **保留的非默认路径：** MainWindowController.swift:443–474/653–654是点音符、BMSON通道源等单文件试听的playFile；默认三handler不调用这些方法。PreviewWindowController.swift:760也有显式previewNote单文件路径。MenuBuilder.swift:514–550单独添加外置beginning/here/stop/config菜单（keyEquivalent为空），进入MainWindowController.swift:1027–1036→1298起runExternalViewer；BMS分支再入1371起runBmsExternalPlayer。这是明确选择的外置功能，未发现默认播放handler自动选择它。

## hash边界

以下为读取结束时逐文件SHA-256；Grok仍可能修改AppDelegate/State等文件，不声称跨文件原子快照或之后版本不变。行号是本轮读取位置，后续按hash重定位。

| 文件（macos/Sources/IBMSNative） | SHA-256 |
| --- | --- |
| AppDelegate.swift | `4af6a93ca16536ccb689b4eec734fb4e01e696db665f80d4876ba65c2850f3e2` |
| MainWindowController.swift | `777e49840329ee5e489917478349546858ffa0fe905a3d6de14b2166ea023fe2` |
| MenuBuilder.swift | `73240d1d91cd99445446c5d831bcda251f04b7368e6d307acbd7059b6a9bc058` |
| MainToolbar.swift | `1f24c2c37c1cc4a50cdced4765113e202feba90c7783eaba807adc569d12dd81` |
| MainWindowContentView.swift | `b23fa9e32d8d64be5a60c06bb6fdcd1389b0709fe6c168453bbaa4b2dce14817` |
| MainWindowChrome.swift | `9b9274678ade6acee01230d9a9a12267da82039c2b7cbea03955c214e8ee017f` |
| LegacyChromeMenu.swift | `2e8eae9172dd2a664e45c1c8618d7c44bf1ac44406bea4be3c987f02b69ebd2e` |
| ChartRenderer.swift | `b93dc3042dbdd103d0e31b2f629be2a9189903d2f0c3422104d48c911a32a463` |
| ApplicationState.swift | `4fe2b62ba74d1d7e042bb9483f43e7797017b0ba51cc12934b80cb09dd740605` |
| PreviewWindowController.swift | `4cb3a4cf0322b9710d6a97105f089ea1d5a069f2ff2a27dbd65260c02e5bdd24` |
| LegacyPreviewAudio.swift | `99b51f1d69999ea75e2beb647a2774390b7434d8e1072ea7cdf2001d80ac92d2` |

最小剩余整合验证：DI完成后核bundle内皮肤/字体等资源解析与构建；随后在可用显示会话分别用未保存BMS/BMSON从F5、F6、工具栏起播，核同一内置窗口、Here拍、1P/2P/BGA及F7停止。此处只列验证，不替代用户要求的实际整合工作，也不为显式外置菜单引入默认重定向。
