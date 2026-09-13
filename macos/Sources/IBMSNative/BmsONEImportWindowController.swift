import AppKit

/// BMS 导入窗。对照 `BmsImportDialog`。
///
/// 客户区 `640 × 480`。底栏控件框是工作值，源码用 sizer，未截图。
/// 没勾 Skip Questions 时按源码顺序问编码、RANDOM、游戏模式。
/// 勾了就用默认值：编码空串、RANDOM `1`、`GetMode`。
@MainActor
final class BmsONEImportWindowController: NSWindowController, NSWindowDelegate {
    private let dialogView: BmsONEImportView

    init() {
        let size = BmsONEDialogLayout.bmsImportSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = NativeLocalization.text(BmsONEDialogLayout.bmsImportTitle)
        window.isReleasedWhenClosed = false
        window.contentMinSize = size
        window.contentMaxSize = size
        dialogView = BmsONEImportView(frame: NSRect(origin: .zero, size: size))
        super.init(window: window)
        window.delegate = self
        window.contentView = dialogView
        NativeLocalization.markFixed(window, key: BmsONEDialogLayout.bmsImportTitle)
        window.setContentSize(size)
    }

    required init?(coder: NSCoder) { nil }

    func present(data: Data, path: String? = nil, onFinish: @escaping (BmsONEDocument) -> Void) {
        dialogView.begin(data: data, path: path, onFinish: onFinish)
        guard let window else { return }
        window.center()
        showWindow(self)
        window.makeKeyAndOrderFront(self)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(self)
        return false
    }
}

@MainActor
private final class BmsONEImportView: FlippedDialogView, NSTextFieldDelegate {
    private enum Step {
        case encoding
        case random
        case gameMode
        case finished
    }

    private let message = NSTextField(wrappingLabelWithString: NativeLocalization.text(BmsONEDialogLayout.bmsImportLoading))
    private let progress = NSProgressIndicator()
    private let log = NSTextView()
    private let skip = NSButton(
        checkboxWithTitle: NativeLocalization.text(BmsONEDialogLayout.bmsImportSkipTitle),
        target: nil,
        action: nil
    )
    private let nextButton = NSButton(title: NativeLocalization.text(BmsONEDialogLayout.bmsImportNextTitle), target: nil, action: nil)
    private let cancelButton = NSButton(title: NativeLocalization.text(BmsONEDialogLayout.bmsImportCancelTitle), target: nil, action: nil)
    private var radios: [NSButton] = []
    private var marks: [NSTextField] = []
    private var encodingRadios: [NSButton] = []
    private var encodingPreviews: [NSTextView] = []
    private let randomCheckbox = NSButton(
        checkboxWithTitle: NativeLocalization.text(BmsONEDialogLayout.bmsImportRandomCheckboxTitle),
        target: nil,
        action: nil
    )
    private let randomSlider = NSSlider()
    private let randomEdit = NSTextField()
    private var imported: BmsONEDocument?
    private var onFinish: ((BmsONEDocument) -> Void)?
    private var pendingData: Data?
    private var pendingPath: String?
    private var detectedMode = BmsONEBmsMode.mode7k
    private var selectedMode = BmsONEBmsMode.mode7k
    private var selectedEncoding = BmsONEImportQuestion.defaultEncoding
    private var randomMaxima: [Int] = []
    private var randomValues: [Int] = []
    private var randomIndex = 0
    private var step = Step.encoding
    private var importOptions = BmsONEImportOptions()

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(origin: .zero, size: BmsONEDialogLayout.bmsImportSize))
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        message.frame = BmsONEDialogLayout.bmsImportMessage
        NativeLocalization.markFixed(message, key: BmsONEDialogLayout.bmsImportLoading)
        addSubview(message)

        for (index, encoding) in BmsONETextEncoding.allCases.enumerated() {
            let radio = NSButton(radioButtonWithTitle: encoding.displayName, target: nil, action: nil)
            radio.tag = index
            radio.frame = BmsONEDialogLayout.encodingRadio(at: index)
            radio.target = self
            radio.action = #selector(selectEncoding(_:))
            radio.isHidden = true
            encodingRadios.append(radio)
            addSubview(radio)

            let preview = NSTextView(frame: BmsONEDialogLayout.encodingPreview(at: index))
            preview.isEditable = false
            preview.isRichText = false
            preview.isHidden = true
            encodingPreviews.append(preview)
            addSubview(preview)
        }

        for index in BmsONEBmsMode.allCases.indices {
            let radio = NSButton(
                radioButtonWithTitle: BmsONEBmsMode.allCases[index].longName,
                target: nil,
                action: nil
            )
            radio.tag = index
            radio.frame = BmsONEDialogLayout.gameModeRadio(at: index)
            radio.target = self
            radio.action = #selector(selectGameMode(_:))
            radio.isHidden = true
            radios.append(radio)
            addSubview(radio)

            let mark = NSTextField(labelWithString: BmsONEDialogLayout.bmsImportGameModeOkMark)
            mark.alignment = .center
            mark.frame = BmsONEDialogLayout.gameModeMark(at: index)
            mark.isHidden = true
            marks.append(mark)
            addSubview(mark)
        }

        randomCheckbox.frame = BmsONEDialogLayout.bmsImportRandomCheckbox
        randomCheckbox.target = self
        randomCheckbox.action = #selector(toggleRandom)
        randomCheckbox.isHidden = true
        addSubview(randomCheckbox)

        randomSlider.frame = BmsONEDialogLayout.bmsImportRandomSlider
        randomSlider.minValue = 1
        randomSlider.maxValue = 1
        randomSlider.doubleValue = 1
        randomSlider.target = self
        randomSlider.action = #selector(changeRandomSlider)
        randomSlider.isHidden = true
        addSubview(randomSlider)

        randomEdit.frame = BmsONEDialogLayout.bmsImportRandomEdit
        randomEdit.stringValue = "1"
        randomEdit.delegate = self
        randomEdit.isHidden = true
        addSubview(randomEdit)

        progress.frame = BmsONEDialogLayout.bmsImportProgress
        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = Double(BmsONEDialogLayout.bmsImportProgressMaximum)
        progress.doubleValue = 0
        addSubview(progress)

        log.frame = BmsONEDialogLayout.bmsImportLog
        log.isEditable = false
        log.isRichText = false
        addSubview(log)

        skip.frame = BmsONEDialogLayout.bmsImportSkip
        NativeLocalization.markFixed(skip, key: BmsONEDialogLayout.bmsImportSkipTitle)
        addSubview(skip)

        nextButton.frame = BmsONEDialogLayout.bmsImportNext
        NativeLocalization.markFixed(nextButton, key: BmsONEDialogLayout.bmsImportNextTitle)
        nextButton.bezelStyle = .rounded
        nextButton.keyEquivalent = "\r"
        nextButton.target = self
        nextButton.action = #selector(pressNext)
        nextButton.isEnabled = false
        addSubview(nextButton)

        cancelButton.frame = BmsONEDialogLayout.bmsImportCancel
        NativeLocalization.markFixed(cancelButton, key: BmsONEDialogLayout.bmsImportCancelTitle)
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.target = self
        cancelButton.action = #selector(cancelImport)
        addSubview(cancelButton)
    }

    required init?(coder: NSCoder) { nil }

    func begin(data: Data, path: String? = nil, onFinish: @escaping (BmsONEDocument) -> Void) {
        self.onFinish = onFinish
        imported = nil
        pendingData = data
        pendingPath = path
        importOptions = BmsONEPreferences.load().importOptions
        selectedEncoding = importOptions.defaultTextEncoding
        randomMaxima = []
        randomValues = []
        randomIndex = 0
        hideQuestions()
        message.frame = BmsONEDialogLayout.bmsImportMessage
        message.stringValue = NativeLocalization.text(BmsONEDialogLayout.bmsImportLoading)
        NativeLocalization.markFixed(message, key: BmsONEDialogLayout.bmsImportLoading)
        nextButton.title = NativeLocalization.text(BmsONEDialogLayout.bmsImportNextTitle)
        NativeLocalization.markFixed(nextButton, key: BmsONEDialogLayout.bmsImportNextTitle)
        nextButton.isEnabled = false
        cancelButton.title = NativeLocalization.text(BmsONEDialogLayout.bmsImportCancelTitle)
        NativeLocalization.markFixed(cancelButton, key: BmsONEDialogLayout.bmsImportCancelTitle)
        progress.doubleValue = 0
        log.string = ""

        if skip.state == .on {
            finishWithDefaults()
        } else if importOptions.shouldAskEncoding(skipQuestions: false) {
            askEncoding()
        } else {
            continueAfterEncoding()
        }
    }

    @objc private func selectEncoding(_ sender: NSButton) {
        guard sender.tag >= 0, sender.tag < BmsONETextEncoding.allCases.count else { return }
        selectedEncoding = BmsONETextEncoding.allCases[sender.tag]
        for radio in encodingRadios {
            radio.state = radio.tag == sender.tag ? .on : .off
        }
    }

    @objc private func selectGameMode(_ sender: NSButton) {
        guard let mode = BmsONEBmsMode(rawValue: sender.tag) else { return }
        selectedMode = mode
        for radio in radios {
            radio.state = radio.tag == sender.tag ? .on : .off
        }
    }

    @objc private func toggleRandom() {
        let isRandom = randomCheckbox.state == .on
        randomSlider.isEnabled = !isRandom
        randomEdit.isEnabled = !isRandom
    }

    @objc private func changeRandomSlider() {
        let value = Int(randomSlider.doubleValue.rounded())
        randomEdit.stringValue = String(value)
        randomSlider.doubleValue = Double(value)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard step == .random else { return }
        let maxValue = max(Int(randomSlider.maxValue), 1)
        var value = Int(randomEdit.stringValue) ?? 1
        if value <= 0 { value = 1 }
        if value > maxValue { value = maxValue }
        randomEdit.stringValue = String(value)
        randomSlider.doubleValue = Double(value)
    }

    @objc private func pressNext() {
        if let imported {
            onFinish?(imported)
            window?.orderOut(self)
            return
        }
        switch step {
        case .encoding:
            continueAfterEncoding()
        case .random:
            continueAfterRandom()
        case .gameMode:
            let mode = BmsONEImportQuestion.resolvedMode(
                skipQuestions: !importOptions.shouldAskGameMode(skipQuestions: skip.state == .on),
                detected: detectedMode,
                selected: selectedMode
            )
            convert(mode: mode)
        case .finished:
            break
        }
    }

    @objc private func cancelImport() {
        window?.orderOut(self)
    }

    private func askEncoding() {
        guard let pendingData else { return }
        step = .encoding
        hideQuestions()
        message.frame = BmsONEDialogLayout.bmsImportGameModePromptFrame
        message.stringValue = NativeLocalization.text(BmsONEImportQuestion.encodingPrompt)
        NativeLocalization.markFixed(message, key: BmsONEImportQuestion.encodingPrompt)
        for (index, encoding) in BmsONETextEncoding.allCases.enumerated() {
            encodingRadios[index].state = encoding == selectedEncoding ? .on : .off
            encodingRadios[index].isHidden = false
            encodingPreviews[index].string = encoding.preview(from: pendingData)
            encodingPreviews[index].isHidden = false
        }
        progress.doubleValue = 20
        nextButton.title = NativeLocalization.text(BmsONEDialogLayout.bmsImportNextTitle)
        nextButton.isEnabled = true
        log.string = NativeLocalization.format("Default: %@", BmsONEImportQuestion.defaultEncoding.displayName)
    }

    private func continueAfterEncoding() {
        let encoding = importOptions.resolvedEncoding(
            skipQuestions: skip.state == .on,
            selected: selectedEncoding
        )
        selectedEncoding = encoding
        do {
            let decoded = encoding.decode(pendingData ?? Data())
            randomMaxima = try BmsONEDocument.randomMaxima(from: decoded)
            randomValues = importOptions.defaultRandomValues(maxima: randomMaxima)
            randomIndex = 0
            if randomMaxima.isEmpty {
                askGameMode()
            } else if importOptions.shouldAskRandom(skipQuestions: skip.state == .on) {
                askRandom()
            } else {
                askGameMode()
            }
        } catch {
            showFailure(error)
        }
    }

    private func askRandom() {
        guard randomIndex < randomMaxima.count else {
            askGameMode()
            return
        }
        step = .random
        hideQuestions()
        message.frame = BmsONEDialogLayout.bmsImportGameModePromptFrame
        message.stringValue = NativeLocalization.text(BmsONEImportQuestion.randomPrompt)
        NativeLocalization.markFixed(message, key: BmsONEImportQuestion.randomPrompt)
        let maximum = max(randomMaxima[randomIndex], 1)
        randomCheckbox.state = .off
        randomSlider.minValue = 1
        randomSlider.maxValue = Double(maximum)
        randomSlider.doubleValue = Double(BmsONEImportQuestion.defaultRandomValue)
        randomSlider.isEnabled = true
        randomEdit.stringValue = String(BmsONEImportQuestion.defaultRandomValue)
        randomEdit.isEnabled = true
        randomCheckbox.isHidden = false
        randomSlider.isHidden = false
        randomEdit.isHidden = false
        progress.doubleValue = 40
        nextButton.title = NativeLocalization.text(BmsONEDialogLayout.bmsImportNextTitle)
        nextButton.isEnabled = true
        log.string = "RANDOM \(randomIndex + 1)/\(randomMaxima.count), max \(maximum), default 1"
    }

    private func continueAfterRandom() {
        guard randomIndex < randomValues.count else {
            askGameMode()
            return
        }
        randomValues[randomIndex] = importOptions.resolvedRandomValue(
            skipQuestions: skip.state == .on,
            isRandom: randomCheckbox.state == .on,
            selected: Int(randomSlider.doubleValue.rounded())
        )
        randomIndex += 1
        if randomIndex < randomMaxima.count {
            askRandom()
        } else {
            askGameMode()
        }
    }

    private func askGameMode() {
        hideQuestions()
        do {
            let question = try BmsONEDocument.gameModeQuestion(
                data: pendingData ?? Data(),
                path: pendingPath,
                encoding: selectedEncoding,
                randomValues: randomValues,
                options: importOptions
            )
            detectedMode = question.detected
            selectedMode = question.detected
            applyChoices(question.choices)
            if !importOptions.shouldAskGameMode(skipQuestions: skip.state == .on) {
                convert(mode: detectedMode)
            } else {
                step = .gameMode
                message.frame = BmsONEDialogLayout.bmsImportGameModePromptFrame
                message.stringValue = NativeLocalization.text(BmsONEImportQuestion.prompt)
                NativeLocalization.markFixed(message, key: BmsONEImportQuestion.prompt)
                setGameModeVisible(true)
                progress.doubleValue = 70
                nextButton.title = NativeLocalization.text(BmsONEDialogLayout.bmsImportNextTitle)
                nextButton.isEnabled = true
        log.string = NativeLocalization.format("Default: %@", detectedMode.longName)
            }
        } catch {
            showFailure(error)
        }
    }

    private func finishWithDefaults() {
        selectedEncoding = importOptions.defaultTextEncoding
        do {
            let decoded = selectedEncoding.decode(pendingData ?? Data())
            randomMaxima = try BmsONEDocument.randomMaxima(from: decoded)
            randomValues = importOptions.defaultRandomValues(maxima: randomMaxima)
            askGameMode()
        } catch {
            showFailure(error)
        }
    }

    private func convert(mode: BmsONEBmsMode) {
        hideQuestions()
        step = .finished
        message.frame = BmsONEDialogLayout.bmsImportMessage
        nextButton.isEnabled = false
        guard let pendingData else { return }
        do {
            let document = try BmsONEDocument.importBms(
                data: pendingData,
                path: pendingPath,
                mode: mode,
                encoding: selectedEncoding,
                randomValues: randomValues,
                options: importOptions
            )
            imported = document
            progress.doubleValue = Double(BmsONEDialogLayout.bmsImportProgressMaximum)
            message.stringValue = NativeLocalization.text(BmsONEDialogLayout.bmsImportSucceeded)
            NativeLocalization.markFixed(message, key: BmsONEDialogLayout.bmsImportSucceeded)
            nextButton.title = NativeLocalization.text(BmsONEDialogLayout.bmsImportFinishTitle)
            NativeLocalization.markFixed(nextButton, key: BmsONEDialogLayout.bmsImportFinishTitle)
            nextButton.isEnabled = true
            log.string = BmsONEImportLog.success(
                title: document.title,
                modeHint: document.modeHint,
                noteCount: document.soundChannels.reduce(0) { $0 + $1.notes.count },
                skipQuestions: skip.state == .on
            )
        } catch {
            showFailure(error)
        }
    }

    private func showFailure(_ error: Error) {
        hideQuestions()
        step = .finished
        progress.doubleValue = 0
        message.frame = BmsONEDialogLayout.bmsImportMessage
        message.stringValue = NativeLocalization.text(BmsONEDialogLayout.bmsImportFailed)
        NativeLocalization.markFixed(message, key: BmsONEDialogLayout.bmsImportFailed)
        cancelButton.title = NativeLocalization.text(BmsONEDialogLayout.bmsImportCloseTitle)
        NativeLocalization.markFixed(cancelButton, key: BmsONEDialogLayout.bmsImportCloseTitle)
        log.string = error.localizedDescription
    }

    private func applyChoices(_ choices: [BmsONEGameModeChoice]) {
        for (index, choice) in choices.enumerated() where index < radios.count {
            radios[index].title = choice.longName
            radios[index].state = choice.mode == selectedMode ? .on : .off
            marks[index].stringValue = choice.mark
        }
    }

    private func setGameModeVisible(_ visible: Bool) {
        for radio in radios {
            radio.isHidden = !visible
        }
        for mark in marks {
            mark.isHidden = !visible
        }
    }

    private func hideQuestions() {
        setGameModeVisible(false)
        for radio in encodingRadios {
            radio.isHidden = true
        }
        for preview in encodingPreviews {
            preview.isHidden = true
        }
        randomCheckbox.isHidden = true
        randomSlider.isHidden = true
        randomEdit.isHidden = true
    }
}

@MainActor
enum BmsONEImportLog {
    static func success(title: String, modeHint: String, noteCount: Int, skipQuestions: Bool) -> String {
        let shown = title.isEmpty ? NativeLocalization.text("(untitled)") : title
        var lines = [
            NativeLocalization.format("Converted as %@.", modeHint),
            NativeLocalization.format("Title: %@", shown),
            NativeLocalization.format("Notes: %d", noteCount)
        ]
        if skipQuestions {
            lines.append(NativeLocalization.text("Skip Questions used defaults."))
        }
        return lines.joined(separator: "\n")
    }
}
