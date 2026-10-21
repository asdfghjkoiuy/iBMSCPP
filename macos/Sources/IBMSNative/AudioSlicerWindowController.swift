import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// 共用切片窗。bmhelper 用 Division 时间线，woslicer 用裁断线。不是原版主程序窗。
@MainActor
final class AudioSlicerWindowController: NSWindowController, NSWindowDelegate {
    private let dialogView: AudioSlicerView

    init() {
        let size = AudioSlicerLayout.clientSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = NativeLocalization.text(AudioSlicerLayout.title)
        NativeLocalization.markFixed(window, key: AudioSlicerLayout.title)
        window.isReleasedWhenClosed = false
        window.contentMinSize = AudioSlicerLayout.minimumSize
        dialogView = AudioSlicerView(frame: NSRect(origin: .zero, size: size))
        super.init(window: window)
        window.delegate = self
        window.contentView = dialogView
        window.setContentSize(size)
        dialogView.onTitleChange = { [weak self] title in
            if title == AudioSlicerLayout.title {
                self?.window?.title = NativeLocalization.text(title)
            } else if let division = title.split(separator: "\"").dropFirst().first {
                self?.window?.title = NativeLocalization.format("Audio splitter (division: \"%@\")", String(division))
            } else {
                self?.window?.title = title
            }
        }
    }

    required init?(coder: NSCoder) { nil }

    func previousPreviewEnabledForTesting() -> Bool {
        dialogView.previousPreviewEnabledForTesting()
    }

    func presentBmhelper(divisionName: String, notes: [MidiNoteEvent], quantize: Int) {
        dialogView.applyBmhelper(divisionName: divisionName, notes: notes, quantize: quantize)
        show()
    }

    func presentWoslicer() {
        dialogView.applyWoslicer()
        show()
    }

    func present() {
        dialogView.applyWoslicer()
        show()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        dialogView.stopPreviewPlayback()
        sender.orderOut(self)
        return false
    }

    private func show() {
        guard let window else { return }
        window.center()
        showWindow(self)
        window.makeKeyAndOrderFront(self)
    }
}

@MainActor
private final class AudioSlicerView: FlippedDialogView, NSTextFieldDelegate {
    var onTitleChange: ((String) -> Void)?
    private let modeControl = NSSegmentedControl(
        labels: AudioSliceMode.allCases.map(\.displayName),
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let inputField = NSTextField(string: "")
    private let outputField = NSTextField(string: "")
    private let prefixField = NSTextField(string: "")
    private let bpmField = NSTextField(string: "120")
    private let offsetField = NSTextField(string: "0")
    private let marksField = NSTextField(string: "")
    private let currentMarkField = NSTextField(string: "1.0")
    private let sequenceStartField = NSTextField(string: "1")
    private let ffDefinitionButton = NSButton(
        checkboxWithTitle: NativeLocalization.text(AudioSlicerLayout.ffDefinitionTitle),
        target: nil,
        action: nil
    )
    private var woslicerOnlyViews: [NSView] = []
    private var mode: AudioSliceMode = .woslicer
    private var notes: [MidiNoteEvent] = []
    private var quantize = 480
    private var marks: [Double] = []
    private var previewPlayer: AVAudioPlayer?
    private let waveformView = AudioSlicerWaveformView(frame: .zero)
    private var waveformDuration: Double = 0
    private var loadedInputURL: URL?
    private var loadedInputModified: Date?
    private var loadedInputSize: Int?
    private var loadedWav: BmhelperPcmWav?
    private var trimmedWav: BmhelperPcmWav?
    private var waveformColumnWidth = 0
    private var actionButtons: [NSButton] = []
    private var labels: [NSTextField] = []

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(origin: .zero, size: AudioSlicerLayout.clientSize))
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        registerForDraggedTypes([.fileURL])

        addLabel(AudioSlicerLayout.modeLabel, x: 10, y: 10, width: 90)
        modeControl.frame = NSRect(x: 100, y: 6, width: 220, height: 24)
        modeControl.selectedSegment = 1
        modeControl.target = self
        modeControl.action = #selector(changeSliceMode)
        addSubview(modeControl)

        addLabel(BmhelperAudioSplitterLayout.audioFileTitle, x: 10, y: 40, width: 200)
        addLabel(BmhelperAudioSplitterLayout.dropHint, x: 10, y: 58, width: 780)
        inputField.frame = NSRect(x: 10, y: 78, width: 680, height: 22)
        inputField.delegate = self
        inputField.lineBreakMode = .byTruncatingMiddle
        NativeLocalization.markTooltip(inputField, key: "Audio file path")
        addSubview(inputField)
        addButton(BmhelperAudioSplitterLayout.browseTitle, x: 700, y: 74, width: 90, action: #selector(browseInput))

        addLabel(BmhelperAudioSplitterLayout.outputDirectoryTitle, x: 10, y: 108, width: 200)
        outputField.frame = NSRect(x: 10, y: 128, width: 680, height: 22)
        outputField.lineBreakMode = .byTruncatingMiddle
        NativeLocalization.markTooltip(outputField, key: "Output folder path")
        addSubview(outputField)
        addButton(BmhelperAudioSplitterLayout.browseTitle, x: 700, y: 124, width: 90, action: #selector(browseOutput))

        addLabel(BmhelperAudioSplitterLayout.prefixTitle, x: 10, y: 158, width: 220)
        prefixField.frame = NSRect(x: 230, y: 154, width: 240, height: 22)
        addSubview(prefixField)

        addLabel(BmhelperAudioSplitterLayout.bpmTitle, x: 10, y: 192, width: 50)
        bpmField.frame = NSRect(x: 60, y: 188, width: 80, height: 22)
        addSubview(bpmField)
        addLabel(BmhelperAudioSplitterLayout.offsetTitle, x: 160, y: 192, width: 120)
        offsetField.frame = NSRect(x: 280, y: 188, width: 80, height: 22)
        offsetField.delegate = self
        addSubview(offsetField)

        addLabel(AudioSlicerLayout.marksTitle, x: 10, y: 224, width: 200)
        marksField.frame = NSRect(x: 10, y: 244, width: 420, height: 22)
        marksField.isEditable = false
        addSubview(marksField)
        currentMarkField.frame = NSRect(x: 440, y: 244, width: 80, height: 22)
        addSubview(currentMarkField)
        addButton(AudioSlicerLayout.addMarkTitle, x: 530, y: 240, width: 100, action: #selector(addMark))
        addButton(AudioSlicerLayout.clearMarksTitle, x: 640, y: 240, width: 110, action: #selector(clearMarks))

        let sequenceLabel = addLabel(AudioSlicerLayout.sequenceStartTitle, x: 10, y: 280, width: 120)
        sequenceStartField.frame = NSRect(x: 130, y: 276, width: 50, height: 22)
        addSubview(sequenceStartField)
        ffDefinitionButton.frame = NSRect(x: 190, y: 274, width: 130, height: 24)
        addSubview(ffDefinitionButton)
        let exportButton = addButton(
            AudioSlicerLayout.exportBMSETitle,
            x: 330,
            y: 272,
            width: 120,
            action: #selector(exportBMSEClipboard)
        )
        let importButton = addButton(
            AudioSlicerLayout.importBMSETitle,
            x: 460,
            y: 272,
            width: 120,
            action: #selector(importBMSEClipboard)
        )
        woslicerOnlyViews = [sequenceLabel, sequenceStartField, ffDefinitionButton, exportButton, importButton]

        waveformView.frame = NSRect(
            x: AudioSlicerLayout.waveformX,
            y: AudioSlicerLayout.waveformY,
            width: AudioSlicerLayout.waveformSize.width,
            height: AudioSlicerLayout.waveformSize.height
        )
        addSubview(waveformView)

        addButton("Play Current Segment", x: 10, y: AudioSlicerLayout.splitButtonY, width: 100, action: #selector(previewCurrentSlice))
        addButton("Play Previous Segment", x: 118, y: AudioSlicerLayout.splitButtonY, width: 100, action: #selector(previewPreviousSlice))
        addButton("Stop", x: 226, y: AudioSlicerLayout.splitButtonY, width: 72, action: #selector(stopPreviewPlayback))

        addButton(
            BmhelperAudioSplitterLayout.splitTitle,
            x: 620,
            y: AudioSlicerLayout.splitButtonY,
            width: 80,
            action: #selector(split)
        )
        addButton(
            BmhelperAudioSplitterLayout.closeTitle,
            x: 710,
            y: AudioSlicerLayout.splitButtonY,
            width: 80,
            action: #selector(closeSplitter)
        )
        refreshModeControls()
        reloadWaveform()
        refreshMarksField()
        refreshActionAvailability()
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let inset = AudioSlicerLayout.contentInset
        let width = bounds.width
        let height = bounds.height
        let fullWidth = max(width - inset * 2, 0)
        let browseWidth: CGFloat = 82
        let fieldWidth = max(fullWidth - browseWidth - 8, 0)
        let waveformFrame = AudioSlicerLayout.waveformFrame(in: bounds.size)
        let formY = waveformFrame.maxY + AudioSlicerLayout.spacing
        let bottomY = max(height - 44, formY + 170)

        if labels.indices.contains(0) { labels[0].frame = NSRect(x: inset, y: 18, width: 72, height: 18) }
        modeControl.frame = NSRect(x: inset + 76, y: 14, width: 220, height: 28)
        if labels.indices.contains(1) { labels[1].frame = NSRect(x: inset, y: 51, width: 72, height: 18) }
        if labels.indices.contains(2) { labels[2].isHidden = true }
        inputField.frame = NSRect(x: inset + 76, y: 47, width: fieldWidth - 76, height: 26)
        if actionButtons.indices.contains(0) { actionButtons[0].frame = NSRect(x: width - inset - browseWidth, y: 46, width: browseWidth, height: 28) }

        waveformView.frame = waveformFrame
        if labels.indices.contains(3) { labels[3].frame = NSRect(x: inset, y: formY + 4, width: 72, height: 20) }
        outputField.frame = NSRect(x: inset + 76, y: formY, width: fieldWidth - 76, height: 26)
        if actionButtons.indices.contains(1) { actionButtons[1].frame = NSRect(x: width - inset - browseWidth, y: formY - 1, width: browseWidth, height: 28) }

        let row2 = formY + 38
        if labels.indices.contains(4) { labels[4].frame = NSRect(x: inset, y: row2 + 4, width: 104, height: 20) }
        prefixField.frame = NSRect(x: inset + 108, y: row2, width: max(fullWidth * 0.34, 160), height: 26)
        if labels.indices.contains(5) { labels[5].frame = NSRect(x: inset + fullWidth * 0.5, y: row2 + 4, width: 44, height: 20) }
        bpmField.frame = NSRect(x: inset + fullWidth * 0.5 + 48, y: row2, width: 88, height: 26)
        if labels.indices.contains(6) { labels[6].frame = NSRect(x: inset + fullWidth * 0.5 + 148, y: row2 + 4, width: 86, height: 20) }
        offsetField.frame = NSRect(x: inset + fullWidth * 0.5 + 238, y: row2, width: 88, height: 26)

        let row3 = row2 + 38
        if labels.indices.contains(7) { labels[7].frame = NSRect(x: inset, y: row3 + 4, width: 112, height: 20) }
        marksField.frame = NSRect(x: inset + 116, y: row3, width: max(fullWidth - 440, 120), height: 26)
        currentMarkField.frame = NSRect(x: width - inset - 314, y: row3, width: 74, height: 26)
        if actionButtons.indices.contains(2) { actionButtons[2].frame = NSRect(x: width - inset - 232, y: row3 - 1, width: 104, height: 28) }
        if actionButtons.indices.contains(3) { actionButtons[3].frame = NSRect(x: width - inset - 120, y: row3 - 1, width: 120, height: 28) }

        let row4 = row3 + 38
        if labels.indices.contains(8) { labels[8].frame = NSRect(x: inset, y: row4 + 4, width: 96, height: 20) }
        sequenceStartField.frame = NSRect(x: inset + 100, y: row4, width: 54, height: 26)
        ffDefinitionButton.frame = NSRect(x: inset + 166, y: row4 + 1, width: 126, height: 24)
        if actionButtons.indices.contains(4) { actionButtons[4].frame = NSRect(x: inset + 304, y: row4 - 1, width: 116, height: 28) }
        if actionButtons.indices.contains(5) { actionButtons[5].frame = NSRect(x: inset + 428, y: row4 - 1, width: 116, height: 28) }

        if actionButtons.indices.contains(8) { actionButtons[8].frame = NSRect(x: inset, y: bottomY, width: 122, height: 28) }
        if actionButtons.indices.contains(9) { actionButtons[9].frame = NSRect(x: inset + 130, y: bottomY, width: 144, height: 28) }
        if actionButtons.indices.contains(10) { actionButtons[10].frame = NSRect(x: inset + 282, y: bottomY, width: 72, height: 28) }
        if actionButtons.indices.contains(6) { actionButtons[6].frame = NSRect(x: width - inset - 190, y: bottomY, width: 112, height: 28) }
        if actionButtons.indices.contains(7) { actionButtons[7].frame = NSRect(x: width - inset - 70, y: bottomY, width: 70, height: 28) }
        refreshWaveformMarks()
        refreshWaveformColumnsIfNeeded()
    }

    func applyBmhelper(divisionName: String, notes: [MidiNoteEvent], quantize: Int) {
        stopPreviewPlayback()
        mode = .bmhelper
        modeControl.selectedSegment = 0
        self.notes = notes
        self.quantize = max(quantize, 1)
        prefixField.stringValue = divisionName.isEmpty ? BmhelperDefDialogLayout.defaultName : divisionName
        bpmField.stringValue = String(format: "%.\(BmhelperAudioSplitterLayout.bpmDigits)f", BmhelperAudioSplitterLayout.defaultBpm)
        offsetField.stringValue = String(Int(BmhelperAudioSplitterLayout.defaultOffsetMs))
        refreshModeControls()
        reloadWaveform()
        refreshWaveformMarks()
        onTitleChange?(BmhelperAudioSplitterLayout.title(divisionName: prefixField.stringValue))
    }

    func applyWoslicer() {
        stopPreviewPlayback()
        mode = .woslicer
        modeControl.selectedSegment = 1
        notes = []
        marks = []
        if prefixField.stringValue.isEmpty {
            prefixField.stringValue = "slice"
        }
        refreshModeControls()
        refreshMarksField()
        if loadedWav != nil {
            publishWaveform()
        } else {
            refreshWaveformMarks()
        }
        onTitleChange?(AudioSlicerLayout.title)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              let url = urls.first
        else {
            return false
        }
        setInput(url)
        return true
    }

    @objc private func changeSliceMode() {
        stopPreviewPlayback()
        mode = modeControl.selectedSegment == 0 ? .bmhelper : .woslicer
        refreshModeControls()
        reloadWaveform()
        if mode == .bmhelper {
            onTitleChange?(BmhelperAudioSplitterLayout.title(divisionName: prefixField.stringValue))
        } else {
            onTitleChange?(AudioSlicerLayout.title)
        }
    }

    @objc private func browseInput() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        var allowed: [UTType] = [.wav, .audio]
        if let ogg = UTType(filenameExtension: "ogg") {
            allowed.append(ogg)
        }
        panel.allowedContentTypes = allowed
        panel.message = BmhelperAudioSplitterLayout.selectAudioTitle
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setInput(url)
    }

    @objc private func browseOutput() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = BmhelperAudioSplitterLayout.selectOutputTitle
        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputField.stringValue = url.path
        if !outputField.stringValue.hasSuffix("/") {
            outputField.stringValue += "/"
        }
    }

    @objc private func addMark() {
        let value = Double(currentMarkField.stringValue) ?? 0
        marks = WoslicerSplit.toggleMark(value, in: marks)
        refreshMarksField()
        refreshWaveformMarks()
    }

    @objc private func clearMarks() {
        marks = []
        refreshMarksField()
        refreshWaveformMarks()
    }

    @objc private func exportBMSEClipboard() {
        guard mode == .woslicer else { return }
        guard let text = WoslicerClipboard.encode(
            marks: marks,
            offset: clipboardOffsetSeconds(),
            bpm: clipboardBPM(),
            sequenceStart: clipboardSequenceStart(),
            ffDefinition: ffDefinitionButton.state == .on
        ) else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func importBMSEClipboard() {
        guard mode == .woslicer else { return }
        guard let text = NSPasteboard.general.string(forType: .string),
              let imported = WoslicerClipboard.decodeMarks(text, bpm: clipboardBPM())
        else {
            return
        }
        marks = imported
        refreshMarksField()
        refreshWaveformMarks()
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === inputField {
            reloadWaveform()
        } else if field === offsetField {
            refreshWaveformMarks()
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        guard mode == .woslicer, modifiers.isEmpty else {
            super.keyDown(with: event)
            return
        }
        switch event.charactersIgnoringModifiers?.uppercased() {
        case "Z":
            addMark()
        case "C":
            clearMarks()
        case "M":
            split()
        case "V":
            exportBMSEClipboard()
        case "B":
            importBMSEClipboard()
        case "N":
            ffDefinitionButton.state = ffDefinitionButton.state == .on ? .off : .on
        case "A":
            sequenceStartField.stringValue = String(
                WoslicerClipboard.nudgeSequenceStart(clipboardSequenceStart(), delta: 1)
            )
        case "S":
            sequenceStartField.stringValue = String(
                WoslicerClipboard.nudgeSequenceStart(clipboardSequenceStart(), delta: -1)
            )
        case "P", "\r":
            previewCurrentSlice()
        case "O":
            previewPreviousSlice()
        default:
            super.keyDown(with: event)
        }
    }

    @objc private func split() {
        guard !inputField.stringValue.isEmpty else {
            presentSplitMessage(NativeLocalization.text("Choose an audio file before exporting."), style: .warning)
            return
        }
        let input = URL(fileURLWithPath: inputField.stringValue)
        let output = URL(fileURLWithPath: outputField.stringValue, isDirectory: true)
        let prefix = resolvedPrefix(input: input)
        let request: AudioSliceRequest
        switch mode {
        case .bmhelper:
            request = .bmhelper(
                notes: notes,
                quantize: quantize,
                bpm: clamped(
                    Double(bpmField.stringValue) ?? BmhelperAudioSplitterLayout.defaultBpm,
                    BmhelperAudioSplitterLayout.bpmMinimum,
                    BmhelperAudioSplitterLayout.bpmMaximum
                ),
                offsetMs: clamped(
                    Double(offsetField.stringValue) ?? BmhelperAudioSplitterLayout.defaultOffsetMs,
                    BmhelperAudioSplitterLayout.offsetMinimum,
                    BmhelperAudioSplitterLayout.offsetMaximum
                )
            )
        case .woslicer:
            let offsetMs = Double(offsetField.stringValue) ?? 0
            request = .woslicer(marks: marks, offsetSeconds: offsetMs / 1000, duration: nil)
        }
        do {
            let urls: [URL]
            if let cached = cachedInputWav(input) {
                urls = try AudioSlice.splitFile(
                    mode: mode,
                    wav: cached,
                    outputDirectory: output,
                    prefix: prefix,
                    request: request
                )
            } else {
                urls = try AudioSlice.splitFile(
                    mode: mode,
                    input: input,
                    outputDirectory: output,
                    prefix: prefix,
                    request: request
                )
            }
            presentSplitMessage(
                NativeLocalization.format("Exported %d slices to %@", urls.count, output.path),
                style: .informational
            )
        } catch {
            presentSplitError(error)
        }
    }

    @objc private func closeSplitter() {
        stopPreviewPlayback()
        window?.orderOut(self)
    }

    @objc func previewCurrentSlice() {
        playPreview(previous: false)
    }

    @objc func previewPreviousSlice() {
        playPreview(previous: true)
    }

    @objc func stopPreviewPlayback() {
        previewPlayer?.stop()
        previewPlayer = nil
    }

    private func playPreview(previous: Bool) {
        guard !inputField.stringValue.isEmpty, let wav = waveformWavForDisplay() else {
            NSSound.beep()
            return
        }
        do {
            let part: BmhelperPcmWav
            if mode == .bmhelper {
                guard let range = bmhelperPreviewSampleRange(wav: wav, previous: previous) else {
                    NSSound.beep()
                    return
                }
                part = BmhelperPcmWav(
                    sampleRate: wav.sampleRate,
                    channels: wav.channels,
                    samples: Array(wav.samples[range.start..<range.end])
                )
            } else {
                let frames = wav.samples.count / max(wav.channels, 1)
                let duration = Double(frames) / Double(max(wav.sampleRate, 1))
                let current = Double(currentMarkField.stringValue) ?? 0
                let offset = clipboardOffsetSeconds()
                let range = previous
                    ? WoslicerPreview.previousSegment(
                        current: current,
                        marks: marks,
                        duration: duration,
                        offset: offset
                    )
                    : WoslicerPreview.currentSegment(
                        current: current,
                        marks: marks,
                        duration: duration,
                        offset: offset
                    )
                guard let range else {
                    NSSound.beep()
                    return
                }
                part = AudioSlice.extract(wav: wav, start: range.start, end: range.end)
            }
            guard !part.samples.isEmpty else {
                NSSound.beep()
                return
            }
            let data = try BmhelperWavIO.write(part)
            stopPreviewPlayback()
            let player = try AVAudioPlayer(data: data)
            player.prepareToPlay()
            guard player.play() else {
                NSSound.beep()
                return
            }
            previewPlayer = player
        } catch {
            NSSound.beep()
        }
    }

    private func setInput(_ url: URL) {
        stopPreviewPlayback()
        inputField.stringValue = url.path
        if outputField.stringValue.isEmpty {
            outputField.stringValue = url.deletingLastPathComponent().path
            if !outputField.stringValue.hasSuffix("/") {
                outputField.stringValue += "/"
            }
        }
        if mode == .woslicer {
            prefixField.stringValue = WoslicerSplit.defaultBaseName(input: url)
        }
        reloadWaveform()
    }

    private func reloadWaveform() {
        stopPreviewPlayback()
        let path = inputField.stringValue
        guard !path.isEmpty else {
            clearWaveform()
            return
        }
        let url = URL(fileURLWithPath: path)
        if !loadedWavMatches(url) {
            guard let raw = try? AudioSlice.readPcm(url) else {
                clearWaveform()
                return
            }
            let stamp = fileStamp(url)
            loadedInputURL = url
            loadedInputModified = stamp?.modified
            loadedInputSize = stamp?.size
            loadedWav = raw
            trimmedWav = nil
        }
        publishWaveform()
        refreshActionAvailability()
    }

    private func loadedWavMatches(_ url: URL) -> Bool {
        guard loadedWav != nil, let loadedInputURL, loadedInputURL.path == url.path else { return false }
        guard let stamp = fileStamp(url) else { return false }
        return stamp.modified == loadedInputModified && stamp.size == loadedInputSize
    }

    private func cachedInputWav(_ url: URL) -> BmhelperPcmWav? {
        guard loadedWavMatches(url) else { return nil }
        return loadedWav
    }

    private func fileStamp(_ url: URL) -> (modified: Date, size: Int)? {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              let modified = values.contentModificationDate,
              let size = values.fileSize
        else {
            return nil
        }
        return (modified, size)
    }

    private func waveformWavForDisplay() -> BmhelperPcmWav? {
        guard let loadedWav else { return nil }
        if mode == .bmhelper { return loadedWav }
        if let trimmedWav { return trimmedWav }
        let trimmed = WoslicerTrim.trim(loadedWav)
        trimmedWav = trimmed
        return trimmed
    }

    private func publishWaveform() {
        guard let waveformWav = waveformWavForDisplay() else {
            waveformDuration = 0
            waveformColumnWidth = 0
            waveformView.columns = []
            waveformView.markXs = []
            return
        }
        let frames = waveformWav.samples.count / max(waveformWav.channels, 1)
        waveformDuration = Double(frames) / Double(max(waveformWav.sampleRate, 1))
        let width = max(780, Int(waveformView.bounds.width))
        waveformColumnWidth = width
        waveformView.columns = WoslicerWaveform.columns(
            samples: waveformWav.samples,
            channels: waveformWav.channels,
            width: width
        )
        refreshWaveformMarks()
    }

    private func refreshWaveformColumnsIfNeeded() {
        let width = max(780, Int(waveformView.bounds.width))
        guard width != waveformColumnWidth, loadedWav != nil else { return }
        publishWaveform()
    }

    private func clearWaveform() {
        waveformDuration = 0
        loadedInputURL = nil
        loadedInputModified = nil
        loadedInputSize = nil
        loadedWav = nil
        trimmedWav = nil
        waveformColumnWidth = 0
        waveformView.columns = []
        waveformView.markXs = []
        refreshActionAvailability()
    }

    private func bmhelperPreviewSampleRange(wav: BmhelperPcmWav, previous: Bool) -> (start: Int, end: Int)? {
        let times = BmhelperWavSplit.splitPoints(
            notes: notes,
            quantize: quantize,
            bpm: clamped(
                Double(bpmField.stringValue) ?? BmhelperAudioSplitterLayout.defaultBpm,
                BmhelperAudioSplitterLayout.bpmMinimum,
                BmhelperAudioSplitterLayout.bpmMaximum
            ),
            offsetMs: clamped(
                Double(offsetField.stringValue) ?? BmhelperAudioSplitterLayout.defaultOffsetMs,
                BmhelperAudioSplitterLayout.offsetMinimum,
                BmhelperAudioSplitterLayout.offsetMaximum
            )
        )
        let ranges = BmhelperWavSplit.sliceRanges(wav: wav, times: times)
        guard !ranges.isEmpty else { return nil }
        let channels = max(wav.channels, 1)
        let sampleRate = max(wav.sampleRate, 1)
        let current = Double(currentMarkField.stringValue) ?? 0
        let frame = min(max(Int(current * Double(sampleRate)), 0), max(wav.samples.count / channels, 0))
        let sample = frame * channels
        var index = -1
        for candidate in ranges.indices where ranges[candidate].start <= sample {
            index = candidate
        }
        guard index >= 0 else { return nil }
        if previous {
            guard index > 0 else { return nil }
            index -= 1
        }
        let range = ranges[index]
        guard range.end > range.start, range.start >= 0, range.end <= wav.samples.count else { return nil }
        return range
    }

    private func refreshActionAvailability() {
        let available = loadedWav != nil && !inputField.stringValue.isEmpty
        if actionButtons.indices.contains(6) { actionButtons[6].isEnabled = available }
        if actionButtons.indices.contains(8) { actionButtons[8].isEnabled = available }
        if actionButtons.indices.contains(9) { actionButtons[9].isEnabled = available }
        if actionButtons.indices.contains(10) { actionButtons[10].isEnabled = available }
    }

    func previousPreviewEnabledForTesting() -> Bool {
        actionButtons.indices.contains(9) && actionButtons[9].isEnabled
    }

    private func presentSplitMessage(_ message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = style == .informational ? NativeLocalization.text("Export complete") : NativeLocalization.text("Audio export needs attention")
        alert.informativeText = message
        alert.alertStyle = style
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    private func refreshWaveformMarks() {
        waveformView.markXs = WoslicerWaveform.markXs(
            marks: marks,
            offset: clipboardOffsetSeconds(),
            duration: waveformDuration,
            width: max(Int(waveformView.bounds.width.rounded(.down)), 1)
        )
    }

    private func resolvedPrefix(input: URL) -> String {
        if !prefixField.stringValue.isEmpty {
            return prefixField.stringValue
        }
        return mode == .woslicer
            ? WoslicerSplit.defaultBaseName(input: input)
            : BmhelperDefDialogLayout.defaultName
    }

    private func refreshModeControls() {
        let bmhelper = mode == .bmhelper
        marksField.isHidden = bmhelper
        currentMarkField.isHidden = bmhelper
        for view in woslicerOnlyViews {
            view.isHidden = bmhelper
        }
    }

    private func clipboardBPM() -> Double {
        Double(bpmField.stringValue) ?? WoslicerClipboard.defaultBPM
    }

    private func clipboardOffsetSeconds() -> Double {
        (Double(offsetField.stringValue) ?? 0) / 1000
    }

    private func clipboardSequenceStart() -> Int {
        Int(sequenceStartField.stringValue) ?? WoslicerClipboard.defaultSequenceStart
    }

    private func refreshMarksField() {
        marksField.stringValue = marks.map { String($0) }.joined(separator: ", ")
    }

    private func presentSplitError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = BmhelperAudioSplitterLayout.errorTitle
        if let splitError = error as? BmhelperWavSplitError {
            alert.informativeText = splitError.localizedDescription
        } else {
            alert.informativeText = error.localizedDescription
        }
        alert.alertStyle = .critical
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func clamped(_ value: Double, _ minimum: Double, _ maximum: Double) -> Double {
        min(max(value, minimum), maximum)
    }

    @discardableResult
    private func addLabel(_ title: String, x: CGFloat, y: CGFloat, width: CGFloat) -> NSTextField {
        let field = NSTextField(labelWithString: NativeLocalization.text(title))
        NativeLocalization.markFixed(field, key: title)
        field.frame = NSRect(x: x, y: y, width: width, height: 16)
        addSubview(field)
        labels.append(field)
        return field
    }

    @discardableResult
    private func addButton(_ title: String, x: CGFloat, y: CGFloat, width: CGFloat, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.frame = NSRect(x: x, y: y, width: width, height: 28)
        button.bezelStyle = .rounded
        NativeLocalization.markFixed(button, key: title)
        button.setAccessibilityLabel(NativeLocalization.text(title))
        button.title = NativeLocalization.text(title)
        addSubview(button)
        actionButtons.append(button)
        return button
    }
}

/// 按列 min/max 画竖包络。颜色是工作值，不是原版。
@MainActor
private final class AudioSlicerWaveformView: NSView {
    var columns: [WoslicerWaveform.Column] = [] {
        didSet { needsDisplay = true }
    }
    var markXs: [Int] = [] {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Self.backgroundColor.cgColor
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        Self.backgroundColor.setFill()
        bounds.fill()
        guard bounds.width > 0, bounds.height > 0 else { return }
        let mid = bounds.midY
        let half = bounds.height / 2
        Self.envelopeColor.setStroke()
        let visibleColumns = max(Int(bounds.width.rounded(.down)), 1)
        for xIndex in 0..<visibleColumns {
            guard !columns.isEmpty else { break }
            let start = xIndex * columns.count / visibleColumns
            let end = max(start + 1, (xIndex + 1) * columns.count / visibleColumns)
            let range = columns[start..<min(end, columns.count)]
            let minimum = range.map(\.min).min() ?? 0
            let maximum = range.map(\.max).max() ?? 0
            let path = NSBezierPath()
            path.lineWidth = 1
            let x = CGFloat(xIndex) + 0.5
            path.move(to: NSPoint(x: x, y: mid + CGFloat(minimum) * half))
            path.line(to: NSPoint(x: x, y: mid + CGFloat(maximum) * half))
            path.stroke()
        }
        Self.markColor.setStroke()
        for mark in markXs {
            let path = NSBezierPath()
            path.lineWidth = 1
            let x = CGFloat(mark) + 0.5
            path.move(to: NSPoint(x: x, y: 0))
            path.line(to: NSPoint(x: x, y: bounds.height))
            path.stroke()
        }
    }

    private static let backgroundColor = NSColor(srgbRed: 0.12, green: 0.12, blue: 0.14, alpha: 1)
    private static let envelopeColor = NSColor(srgbRed: 0.45, green: 0.78, blue: 0.55, alpha: 1)
    private static let markColor = NSColor(srgbRed: 0.95, green: 0.45, blue: 0.25, alpha: 1)
}
