import Foundation

/// 主界面共享状态。窗口、菜单和预听都在主线程上用。
@MainActor
final class ApplicationState {
    /// 默认预览的那一个内置播放器。F5、F6、F7、预览菜单和工具栏都用它，不另做播放器选择。
    /// 预览窗是非模态的。未保存的 BMS / BMSON 快照由主窗读出后交给这个对象。
    /// 必须在 `init` 里创建：属性默认值不在主线程上求值。
    let previewPlayer: LegacyPreviewAudioPlayer

    init() {
        let player = LegacyPreviewAudioPlayer()
        let decode: @Sendable (URL) -> Data? = { url in
            try? IBMSAudioBridge.pcmWav(fromFile: url.path)
        }
        player.decodeToWav = decode
        AudioSlice.decodeToWav = decode
        previewPlayer = player
    }

    var previewAudioIsImplemented: Bool {
        // 播放器对象在就是 true。
        true
    }
    let editingIsImplemented = false
    let playbackIsImplemented = false
}
