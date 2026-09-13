import AppKit

@MainActor
final class PreviewWindowController: NSWindowController, NSWindowDelegate {
    private let player: LegacyPreviewAudioPlayer
    private var documentSource: () -> PreviewAudioDocumentContext?
    private var onPlayheadBeat: ((Double?) -> Void)?
    private var playheadFromBeat: Double = 0
    private var playheadContext: PreviewAudioDocumentContext?
    private var playheadDelayRatio = 1.0

    init(
        state: ApplicationState,
        documentSource: @escaping () -> PreviewAudioDocumentContext? = { nil },
        onPlayheadBeat: ((Double?) -> Void)? = nil
    ) {
        player = state.previewPlayer
        self.documentSource = documentSource
        self.onPlayheadBeat = onPlayheadBeat
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 260),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        window.title = "Preview"
        NativeLocalization.markFixed(window, key: "Preview")
        window.isFloatingPanel = false
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        player.onElapsedSeconds = { [weak self] elapsed in
            self?.updatePlayhead(elapsed: elapsed)
        }
        player.onPlaybackStopped = { [weak self] in
            self?.clearPlayhead()
        }
        window.contentView = PreviewWindowContentView(
            audioImplemented: state.previewAudioIsImplemented,
            playFromStart: { [weak self] in self?.play(fromBeat: 0) },
            playHere: { [weak self] in self?.playHere() },
            stop: { [weak self] in self?.player.stop() }
        )
        NativeLocalization.localize(window: window)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setDocumentSource(_ source: @escaping () -> PreviewAudioDocumentContext?) {
        documentSource = source
    }

    func previewNote(url: URL) {
        player.playFile(url: url)
    }

    func stopPlayback() {
        player.stop()
        clearPlayhead()
    }

    func playFromStart() {
        play(fromBeat: 0)
    }

    func playFromPointer() {
        playHere()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(self)
        return false
    }

    private func playHere() {
        // 调用方给当前拍；拿不到就用 0。
        play(fromBeat: documentSource()?.playHereBeat ?? 0)
    }

    private func play(fromBeat: Double) {
        guard let context = documentSource() else {
            player.stop()
            return
        }
        playheadFromBeat = fromBeat
        playheadContext = context
        playheadDelayRatio = context.appliesBmsonPlayhead
            ? BmsONEPreferences.load().previewDelayRatio
            : 0
        player.playChart(
            documentData: context.documentData,
            chartDirectory: context.chartDirectory,
            notes: context.notes,
            timing: context.timing,
            fromBeat: fromBeat
        )
    }

    private func updatePlayhead(elapsed: Double) {
        guard let context = playheadContext, context.appliesBmsonPlayhead else {
            onPlayheadBeat?(nil)
            return
        }
        let delayed = BmsONEPreviewTiming.playheadSeconds(audioSeconds: elapsed, ratio: playheadDelayRatio)
        onPlayheadBeat?(
            LegacyPreviewAudio.beat(afterSeconds: delayed, fromBeat: playheadFromBeat, timing: context.timing)
        )
    }

    private func clearPlayhead() {
        playheadContext = nil
        onPlayheadBeat?(nil)
    }
}

@MainActor
private final class PreviewWindowContentView: NSView {
    private let playFromStartHandler: () -> Void
    private let playHereHandler: () -> Void
    private let stopHandler: () -> Void

    init(
        audioImplemented: Bool,
        playFromStart: @escaping () -> Void,
        playHere: @escaping () -> Void,
        stop: @escaping () -> Void
    ) {
        playFromStartHandler = playFromStart
        playHereHandler = playHere
        stopHandler = stop
        super.init(frame: .zero)
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 28, left: 28, bottom: 28, right: 28)
        addSubview(stack)

        let title = NSTextField(labelWithString: NativeLocalization.text("Preview"))
        NativeLocalization.markFixed(title, key: "Preview")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        stack.addArrangedSubview(title)

        let message = NSTextField(wrappingLabelWithString: "Built-in preview plays #WAV samples from the chart folder. OGG stays silent if the system cannot decode it.")
        message.alignment = .center
        message.textColor = .secondaryLabelColor
        message.maximumNumberOfLines = 3
        message.preferredMaxLayoutWidth = 360
        stack.addArrangedSubview(message)

        let controls = NSStackView()
        controls.orientation = .horizontal
        controls.spacing = 8
        let startButton = NSButton(title: "Play from Start", target: self, action: #selector(playFromStartClicked))
        NativeLocalization.markFixed(startButton, key: "Play from Start")
        startButton.title = NativeLocalization.text("Play from Start")
        let hereButton = NSButton(title: "Play Here", target: self, action: #selector(playHereClicked))
        NativeLocalization.markFixed(hereButton, key: "Play Here")
        hereButton.title = NativeLocalization.text("Play Here")
        let stopButton = NSButton(title: "Stop", target: self, action: #selector(stopClicked))
        NativeLocalization.markFixed(stopButton, key: "Stop")
        stopButton.title = NativeLocalization.text("Stop")
        for button in [startButton, hereButton, stopButton] {
            button.isEnabled = audioImplemented
            controls.addArrangedSubview(button)
        }
        stack.addArrangedSubview(controls)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    @objc private func playFromStartClicked() {
        playFromStartHandler()
    }

    @objc private func playHereClicked() {
        playHereHandler()
    }

    @objc private func stopClicked() {
        stopHandler()
    }
}
