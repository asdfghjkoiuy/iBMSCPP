# uBMplay 1.5.2 声音装载

`sound.dll` 只负责把 Ogg、WAV、MP3 解成一块 PCM。播放缓冲、频率和音量在 `uBMplay.exe` 的 `clsSoundBuffer`。两份二进制都只做了静态阅读，不是完整复刻。证据在 [UD-report.md](../../out/validation/ubmplay-parity-20261020/ida/sound/UD-report.md)，给实现对齐的短合同在 [UD-early.md](../../out/validation/ubmplay-parity-20261020/ida/sound/UD-early.md)。

样本：`sound.dll` imagebase `0x10000000`，MD5 `4e7836e120be46e66b2e98c242802ba8`。exe 仍是 imagebase `0x400000`、MD5 `44e3d8aa24e2eb19d1e426fde4086d03`。

## 更正 UR3 的 max

[UR3-report.md](../../out/validation/ubmplay-parity-20261020/ida/UR3-report.md) 已经写出 `dword_42E550 = 5 * Int(2000000 / max)`。当时虚表 `+0x54` 对到了 `0x423FD0`，那个函数的 `retn 0Ch` 和调用点的两个参数对不上，所以 `+4` 没有命名。

对象虚表的用户方法从 `+0x1C` 起算，不是从类描述符里跳转表的字节偏移起算。虚表 `+0x54` 是第 14 个用户方法 `Format`（`0x4249B0`）。它把对象 `+0x3C` 的 24 字节拷给调用者。`+4` 是 `nSamplesPerSec`，单位 Hz。max 为 0 时仍写 200。

`setFrequency` 再算 `clamp(__vbaFpI4(RealHS * 0.01 * 采样率), 100, 100000)`。上限 100000 是这条指令里的立即数 `0x186A0`。

## 装载

导出是 `soundOpen`、`soundRead`、`soundClose`、`soundGetSize`、`soundGetFormat`、`soundIsInitialized`、`soundGetHash32`。没有 `soundSeek`。

`soundOpen` 先试 Ogg，失败再试 WAV/MP3。成功后 exe 按 PCM 字节数一次 `soundRead`，拷贝 18 字节格式，然后 `soundClose`。播放不再读 DLL。`soundGetHash32` 是路径的 FNV-1a，不参与这次装载。

Ogg 和 MP3 的报告格式是 16 bit PCM，采样率保持源采样率。已经是 PCM 的 WAV 沿用文件里的位深和采样率。DLL 不把一切重采样到 44100，也不做混音。
