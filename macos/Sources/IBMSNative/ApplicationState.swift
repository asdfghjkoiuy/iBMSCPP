import Foundation

final class ApplicationState {
    /// 内置预听播放器。对象在，预览窗就可以播。不表示外置 uBMplay 已接通。
    let previewPlayer = LegacyPreviewAudioPlayer()

    init() {
        let decode: (URL) -> Data? = { url in
            try? IBMSAudioBridge.pcmWav(fromFile: url.path)
        }
        previewPlayer.decodeToWav = decode
        AudioSlice.decodeToWav = decode
    }
    var previewAudioIsImplemented: Bool {
        // 播放器对象在就是 true。
        true
    }
    let editingIsImplemented = false
    let playbackIsImplemented = false
}
