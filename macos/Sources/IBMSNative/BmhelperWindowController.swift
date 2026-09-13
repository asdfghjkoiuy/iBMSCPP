import AppKit
import UniformTypeIdentifiers

struct BmhelperWindowLayoutSnapshot {
    let sourceFrame: CGRect
    let divisionFrame: CGRect
    let inspectorFrame: CGRect
    let actionFrames: [CGRect]
    let definitionFrame: CGRect
    let divisionListFrame: CGRect
    let transposeFrames: [CGRect]
}

@MainActor
final class BmhelperWindowController: NSWindowController, NSWindowDelegate {
    private let helperMenu: NSMenu
    private var restoredAppMenu: NSMenu?
    private let defDialog = BmhelperDefDialogWindowController()
    private let defTranspose = BmhelperDefTransposeWindowController()
    private let midiImport = BmhelperMidiImportWindowController()
    private let divisionSettings = BmhelperDivisionSettingWindowController()
    private let audioSplitter = AudioSlicerWindowController()
    private var lastDefinitionName = BmhelperDefDialogLayout.defaultName
    private var lastNotes: [MidiNoteEvent] = []
    private var lastQuantize = 480
    private var lastSettings = BmhelperDivisionSetting.makeDefault(name: BmhelperDefDialogLayout.defaultName, quantize: 480)
    private var lastDivision = BmhelperDivision.divide(
        notes: [],
        setting: BmhelperDivisionSetting.makeDefault(name: BmhelperDefDialogLayout.defaultName, quantize: 480),
        quantize: 480
    )
    private var projectURL: URL?
    private var projectIsTitled = false
    private var projectChanged = false
    private var storedDivisions: [BmhelperSavedDivision] = []
    private var selectedIndex: Int?
    private var hasProject = false

    init() {
        helperMenu = BmhelperMenuBar.make()
        let size = BmhelperMainLayout.clientSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = BmhelperTitle.empty
        window.isReleasedWhenClosed = false
        window.contentMinSize = BmhelperMainLayout.minimumWindowSize
        super.init(window: window)
        window.delegate = self
        let mainView = BmhelperMainView(frame: NSRect(origin: .zero, size: size))
        mainView.onNewDivision = { [weak self] in
            self?.newDivision(nil)
        }
        mainView.onImportMidi = { [weak self] in self?.newFromMidi(nil) }
        mainView.onOpenProject = { [weak self] in self?.openProject(nil) }
        mainView.onSaveProject = { [weak self] in self?.saveProject(nil) }
        mainView.onSelectDivision = { [weak self] index in
            self?.selectListedDivision(index)
        }
        mainView.onTransposeUp = { [weak self] in
            self?.transposeDefinitions(.up)
        }
        mainView.onTransposeDown = { [weak self] in
            self?.transposeDefinitions(.down)
        }
        mainView.onTransposeTo = { [weak self] in
            self?.presentTransposeTo()
        }
        mainView.onWriteMidi = { [weak self] in
            self?.writeModifiedMidi(nil)
        }
        mainView.onCopyDivision = { [weak self] in
            self?.copyDivision(nil)
        }
        mainView.onOpenCutter = { [weak self] in
            self?.openAudioCutter(nil)
        }
        mainView.onOpenDefinitions = { [weak self] in
            self?.showWavDefinitions(nil)
        }
        mainView.onCopySequence = { [weak self] in
            self?.copyBmsSequence(nil)
        }
        window.contentView = mainView
        window.setContentSize(size)
        mainView.onDropFiles = { [weak self] urls in
            self?.handleDroppedFiles(urls)
        }
        BmhelperMenuBar.bind(helperMenu, to: self)
        NativeLocalization.registerKnownStaticMenu(helperMenu)
        NativeLocalization.localize(menu: helperMenu)
        refreshStatus()
        refreshTitle()
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        guard let window else { return }
        window.center()
        revealWindow()
    }

    func layoutSnapshotForTesting() -> BmhelperWindowLayoutSnapshot? {
        guard let mainView = window?.contentView as? BmhelperMainView else { return nil }
        mainView.layoutSubtreeIfNeeded()
        return mainView.layoutSnapshotForTesting()
    }

    func definitionsCloseButtonWorksForTesting() -> Bool {
        guard let window = defDialog.window,
              let button = allSubviews(of: window.contentView ?? NSView()).compactMap({ $0 as? NSButton }).first(where: {
                  $0.action != nil && $0.title == NativeLocalization.text(BmhelperDefDialogLayout.closeTitle)
              })
        else { return false }
        window.orderFront(nil)
        button.performClick(nil)
        return !window.isVisible
    }

    private func allSubviews(of root: NSView) -> [NSView] {
        [root] + root.subviews.flatMap { allSubviews(of: $0) }
    }

    private func revealWindow() {
        guard let window else { return }
        showWindow(self)
        window.makeKeyAndOrderFront(self)
    }

    /// 对照启动时的 `wxGetSingleChoiceIndex`。只存选项，不换文案。
    /// 取消不写 UserDefaults。有窗时用 sheet。
    private func presentLanguageChoice(then finish: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = BmhelperLanguage.title
        alert.informativeText = BmhelperLanguage.prompt
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 240, height: 24), pullsDown: false)
        popup.addItems(withTitles: BmhelperLanguage.options)
        popup.selectItem(at: BmhelperLanguage.defaultIndex)
        alert.accessoryView = popup
        alert.window.title = BmhelperLanguage.title
        let complete: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertFirstButtonReturn {
                let index = popup.indexOfSelectedItem
                if BmhelperLanguage.options.indices.contains(index) {
                    BmhelperLanguage.save(BmhelperLanguage.options[index])
                }
            }
            finish()
        }
        if let window, window.isVisible {
            alert.beginSheetModal(for: window, completionHandler: complete)
        } else {
            complete(alert.runModal())
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard NSApp.mainMenu !== helperMenu else { return }
        restoredAppMenu = NSApp.mainMenu
        NSApp.mainMenu = helperMenu
    }

    func windowDidResignKey(_ notification: Notification) {
        guard NSApp.mainMenu === helperMenu, let restoredAppMenu else { return }
        NSApp.mainMenu = restoredAppMenu
        self.restoredAppMenu = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        askCloseProject { [weak self] allowed in
            guard allowed else { return }
            sender.orderOut(self)
        }
        return false
    }

    /// 对照 `OnCloseProject`。没有工程直接返回。关完窗留下。
    @objc func closeProject(_ sender: Any?) {
        askCloseProject { _ in }
    }

    /// 对照 `OnNewProject`：先走 `_AskCloseProject`，abort 则不换文件。
    /// 选 MIDI，再弹出 `LoadSmfDialog`。
    /// 按 OK 后按默认 `DivisionSetting` 聚类，再写成 `#WAV` 文本。
    /// 工程未命名，保存时要另存为 `.bmh`。
    @objc func newFromMidi(_ sender: Any?) {
        askCloseProject { [weak self] allowed in
            guard allowed else { return }
            self?.pickNewMidi()
        }
    }

    private func pickNewMidi() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Self.midiTypes
        panel.message = "Please select source MIDI file"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try loadMidiAndShowDefinitions(url: url)
        } catch {
            presentOpenError(url: url)
        }
    }

    @objc func showWavDefinitions(_ sender: Any?) {
        presentDefinitions(alreadyDivided: selectedIndex != nil)
    }

    @objc func newDivision(_ sender: Any?) {
        presentDivisionSettings()
    }

    /// 对照 `divedit.cpp:368-373`。系统输入框，只改选中的 division 名。
    @objc func renameDivision(_ sender: Any?) {
        presentRenameDialog()
    }

    /// 对照 `divedit.cpp` 的 `OnDivRegenerate`。没有工程或没有选中则不弹窗。
    @objc func regenerateDivision(_ sender: Any?) {
        presentRegenerateSettings()
    }

    /// 对照 `divedit.cpp` 的 `<` / `>`。只改选中项的 zz，不重新聚类。
    private func transposeDefinitions(_ kind: BmhelperTranspose.Kind) {
        applyTranspose(kind)
    }

    /// 对照 `divview.cpp` 的 `OnDeleteDivision`。没有工程或没有选中则不弹窗。
    @objc func deleteDivision(_ sender: Any?) {
        presentDeleteDialog()
    }

    @objc func openProject(_ sender: Any?) {
        askCloseProject { [weak self] allowed in
            guard allowed else { return }
            self?.pickOpenProject()
        }
    }

    private func pickOpenProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: BmhelperProjectFile.fileExtension)].compactMap { $0 }
        panel.message = BmhelperMainLayout.openProjectPrompt
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try loadProject(url: url)
        } catch {
            presentOpenError(url: url)
        }
    }

    @objc func saveProject(_ sender: Any?) {
        if projectIsTitled, let projectURL {
            do {
                try writeProject(to: projectURL)
                projectChanged = false
                refreshTitle()
            } catch {
                presentOpenError(url: projectURL)
            }
            return
        }
        saveProjectAs(sender)
    }

    @objc func saveProjectAs(_ sender: Any?) {
        _ = performSaveAs()
    }

    @discardableResult
    private func performSaveAs() -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: BmhelperProjectFile.fileExtension)].compactMap { $0 }
        panel.nameFieldStringValue = lastDefinitionName + "." + BmhelperProjectFile.fileExtension
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try writeProject(to: url)
            projectURL = url
            projectIsTitled = true
            projectChanged = false
            refreshTitle()
            return true
        } catch {
            presentOpenError(url: url)
            return false
        }
    }

    @objc func openAudioCutter(_ sender: Any?) {
        audioSplitter.presentBmhelper(
            divisionName: lastDefinitionName,
            notes: lastDivision.notes,
            quantize: lastDivision.quantize
        )
    }

    /// 对照 `divedit.cpp` `_SmfOut`。写出选中 division 的时间线 MIDI，不是源 MIDI。
    /// 右侧按钮和菜单走同一套动作。不改工程脏标记。
    @objc func writeModifiedMidi(_ sender: Any?) {
        guard BmhelperSmfOut.shouldExport(hasProject: hasProject, hasSelection: selectedIndex != nil) else {
            return
        }
        let panel = NSSavePanel()
        panel.title = BmhelperSmfOut.saveTitle
        panel.message = BmhelperSmfOut.saveTitle
        panel.allowedContentTypes = Self.midiTypes
        panel.nameFieldStringValue = lastDefinitionName + "." + BmhelperSmfOut.defaultExtension
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data = BmhelperMidi.encode(
            quantize: max(lastDivision.quantize, 1),
            notes: lastDivision.notes
        )
        do {
            try data.write(to: url)
        } catch {
            presentSmfOutError()
        }
    }

    /// 对照 `division.cpp` 的 `get_div_sequence_data`。只写系统剪贴板。
    /// 用 Division 时间线，不是源 MIDI。右侧按钮和菜单走同一套动作。
    @objc func copyDivision(_ sender: Any?) {
        guard BmhelperDivCopy.shouldCopy(hasProject: hasProject, hasSelection: selectedIndex != nil) else {
            return
        }
        let quantize = max(lastDivision.quantize, 1)
        let text = BmhelperDivCopy.format(
            positions: lastDivision.notes.map(\.position),
            quantize: quantize
        )
        writeClipboard(text)
    }

    /// 对照 `divedit.cpp` 的 `OnSeqCopy`。只写系统剪贴板，不写主编辑器 BMS。
    @objc func copyBmsSequence(_ sender: Any?) {
        guard BmhelperSequence.shouldCopy(hasProject: hasProject, hasSelection: selectedIndex != nil) else {
            return
        }
        let quantize = max(lastDivision.quantize > 0 ? lastDivision.quantize : lastQuantize, 1)
        let text = BmhelperSequence.format(
            positions: lastNotes.map(\.position),
            zzStrings: lastDivision.definitions.map(\.zz),
            src2def: lastDivision.src2def,
            quantize: quantize
        )
        writeClipboard(text)
    }

    /// 对照 `frame.cpp:269-271`。系统 `NSAlert`，没有手写客户区。
    @objc func showAbout(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = BmhelperAbout.messageText
        alert.informativeText = BmhelperAbout.informativeText
        alert.alertStyle = .informational
        alert.window.title = BmhelperAbout.windowTitle
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    func loadMidiAndShowDefinitions(url: URL) throws {
        let data = try Data(contentsOf: url)
        switch BmhelperMidi.parse(data) {
        case .success(let file):
            midiImport.present(file: file) { [weak self] settings in
                self?.applyImportedMidi(file: file, settings: settings, url: url)
            }
        case .failure:
            throw NSError(
                domain: "org.ibmsc.native.bmhelper",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: BmhelperMainLayout.openFailedTitle]
            )
        }
    }

    /// 对照 `OnDropFiles`。不先问保存。第一个成功就停。
    private func handleDroppedFiles(_ urls: [URL]) {
        window?.makeKeyAndOrderFront(self)
        for url in urls {
            let action = BmhelperDrop.decide(hasProject: hasProject, files: [url.path])
            do {
                switch action {
                case .none:
                    return
                case .newFromMidi:
                    try loadMidiAndShowDefinitions(url: url)
                case .openProject:
                    try loadProject(url: url)
                case .replaceSource:
                    try beginReplaceSource(url: url)
                }
                return
            } catch {
                presentDropFailed(path: url.path)
            }
        }
    }

    /// 对照 `SetNewSource` → `load_smf`。只换源，再弹导入窗。不重建 division，不设脏。
    private func beginReplaceSource(url: URL) throws {
        let data = try Data(contentsOf: url)
        switch BmhelperMidi.parse(data) {
        case .success(let file):
            midiImport.present(file: file) { [weak self] settings in
                self?.applyReplacedSource(file: file, settings: settings)
            }
        case .failure:
            throw NSError(
                domain: "org.ibmsc.native.bmhelper",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: BmhelperDrop.dropFailedMessage(url.path)]
            )
        }
    }

    private func applyReplacedSource(file: BmhelperMidiFile, settings: BmhelperMidiImportSettings) {
        lastNotes = BmhelperMidi.collectNoteEvents(from: file, settings: settings)
        lastQuantize = max(file.ticksPerQuarter, 1)
        refreshSourceMidi()
        refreshStatus()
        refreshTitle()
    }

    private func applyImportedMidi(file: BmhelperMidiFile, settings: BmhelperMidiImportSettings, url: URL) {
        lastNotes = BmhelperMidi.collectNoteEvents(from: file, settings: settings)
        lastQuantize = max(file.ticksPerQuarter, 1)
        lastDefinitionName = url.deletingPathExtension().lastPathComponent
        if lastDefinitionName.isEmpty {
            lastDefinitionName = BmhelperDefDialogLayout.defaultName
        }
        lastSettings = BmhelperDivisionSetting.makeDefault(name: lastDefinitionName, quantize: lastQuantize)
        projectURL = url.deletingPathExtension().appendingPathExtension(BmhelperProjectFile.fileExtension)
        projectIsTitled = false
        projectChanged = true
        lastDivision = BmhelperDivision.divide(
            notes: lastNotes,
            setting: lastSettings,
            quantize: lastQuantize
        )
        storedDivisions = [savedCurrentDivision()]
        selectedIndex = BmhelperDivisionList.selectionAfterLoad(count: storedDivisions.count)
        hasProject = true
        refreshDivisionList()
        refreshSourceMidi()
        refreshTimelineMidi()
        presentDefinitions(alreadyDivided: true)
    }

    func loadProject(url: URL) throws {
        let project = try BmhelperProjectFile.decode(Data(contentsOf: url))
        lastNotes = project.source.notes
        lastQuantize = max(project.source.quantize, 1)
        storedDivisions = project.divisions
        selectedIndex = BmhelperDivisionList.selectionAfterLoad(count: storedDivisions.count)
        if let index = selectedIndex {
            applyStoredDivision(at: index)
        } else {
            lastDefinitionName = url.deletingPathExtension().lastPathComponent
            lastDivision = BmhelperDivision.divide(
                notes: lastNotes,
                setting: lastSettings,
                quantize: lastQuantize
            )
        }
        projectURL = url
        projectIsTitled = true
        projectChanged = false
        hasProject = true
        refreshDivisionList()
        refreshSourceMidi()
        refreshTimelineMidi()
        presentDefinitions(alreadyDivided: selectedIndex != nil)
    }

    private func writeProject(to url: URL) throws {
        try BmhelperProjectFile.encode(currentProject()).write(to: url)
    }

    /// 保存当前窗口里的源 MIDI 和已打开的 division。
    /// 当前编辑状态写回选中下标；其余条目原样写回。
    private func currentProject() -> BmhelperProject {
        var divisions = storedDivisions
        if let index = selectedIndex, divisions.indices.contains(index) {
            divisions[index] = savedCurrentDivision()
        } else if divisions.isEmpty {
            divisions = [savedCurrentDivision()]
        }
        return BmhelperProject(
            source: BmhelperMidiBlob(quantize: lastQuantize, notes: lastNotes),
            divisions: divisions
        )
    }

    private func savedCurrentDivision() -> BmhelperSavedDivision {
        BmhelperSavedDivision(
            name: lastDefinitionName.isEmpty ? BmhelperDefDialogLayout.defaultName : lastDefinitionName,
            midi: BmhelperMidiBlob(quantize: lastDivision.quantize, notes: lastDivision.notes),
            src2def: lastDivision.src2def,
            definitions: lastDivision.definitions,
            zzEnabled: lastSettings.zzDefinition,
            source: BmhelperMidiBlob(quantize: lastQuantize, notes: lastNotes)
        )
    }

    private func mainView() -> BmhelperMainView? {
        window?.contentView as? BmhelperMainView
    }

    private func refreshDivisionList() {
        mainView()?.reloadDivisions(
            names: BmhelperDivisionList.names(storedDivisions.map(\.name)),
            selection: selectedIndex
        )
        refreshStatus()
        refreshTitle()
    }

    /// 对照 `srcview.cpp`：有工程时 `SetMidiData(&project->GetSource())`，没有则 `0`。
    /// 画源 MIDI，不是 Division 时间线。
    private func refreshSourceMidi() {
        mainView()?.setSourceMidi(
            notes: hasProject ? lastNotes : nil,
            quantize: lastQuantize
        )
    }

    /// 对照 `divedit.cpp` 的 `SetDivision`：有选中则时间线，没有则没有 data。
    /// 画 `division.midi.notes`，不是源 MIDI。平移不调用这里。
    private func refreshTimelineMidi() {
        let hasSelection = hasProject && selectedIndex != nil
        mainView()?.setTimelineMidi(
            notes: BmhelperMidiView.notesToShow(
                source: lastNotes,
                timeline: lastDivision.notes,
                hasSelection: hasSelection
            ),
            quantize: lastDivision.quantize
        )
    }

    private func refreshStatus() {
        let selectedName = selectedIndex == nil ? nil : lastDefinitionName
        mainView()?.applyStatus(
            BmhelperStatus.fields(
                hasProject: hasProject,
                selectedName: selectedName,
                notes: lastDivision.notes.count,
                definitions: lastDivision.definitions.count,
                sourceNotes: lastNotes.count
            )
        )
        mainView()?.setRightButtonsEnabled(
            BmhelperRightPane.buttonsEnabled(
                hasProject: hasProject,
                hasSelection: selectedIndex != nil
            )
        )
        refreshDefinitionBar()
    }

    /// 对照 `ReloadDivision`。有选中则按该 division 的 zz / div 填格；没有则空条。
    private func refreshDefinitionBar() {
        if hasProject, selectedIndex != nil {
            mainView()?.reloadDefinitionView(lastDivision.definitions.map { ($0.zz, $0.div) })
        } else {
            mainView()?.reloadDefinitionView(nil)
        }
    }

    private func refreshTitle() {
        let name = projectURL.map(BmhelperTitle.fileTitle) ?? ""
        window?.title = BmhelperTitle.caption(
            hasProject: hasProject,
            titled: projectIsTitled,
            changed: projectChanged,
            fileTitle: name
        )
        mainView()?.setProjectSummary(hasProject: hasProject, name: name, changed: projectChanged)
    }

    /// 对照 `_AskCloseProject`。`allowed == true` 表示可以继续（工程已关或本来没有）。
    /// File → Close 只关工程；New / Open / 点窗关闭在 allowed 之后才换文件或藏窗。
    private func askCloseProject(then proceed: @escaping (Bool) -> Void) {
        if !hasProject {
            proceed(BmhelperClose.decide(hasProject: false) != .abort)
            return
        }
        if !projectChanged {
            applyClosedProject()
            proceed(true)
            return
        }
        presentClosePrompt { [weak self] answer in
            guard let self else { return }
            let titled = self.projectIsTitled
            var saveAsSucceeded = false
            if answer == .yes && !titled {
                saveAsSucceeded = self.performSaveAs()
            }
            let decision = BmhelperClose.decide(
                hasProject: true,
                changed: true,
                answer: answer,
                titled: titled,
                saveAsSucceeded: saveAsSucceeded
            )
            switch decision {
            case .ignore:
                proceed(true)
            case .abort:
                proceed(false)
            case .close:
                self.applyClosedProject()
                proceed(true)
            case .saveThenClose:
                self.saveTitledIgnoringResult()
                self.applyClosedProject()
                proceed(true)
            case .saveAsThenClose:
                self.applyClosedProject()
                proceed(true)
            }
        }
    }

    /// 对照 `SetProject(0)`：名单空、状态栏空、标题回到程序名。不重新聚类。
    private func applyClosedProject() {
        hasProject = false
        projectChanged = false
        projectIsTitled = false
        storedDivisions = []
        selectedIndex = nil
        projectURL = nil
        refreshSourceMidi()
        refreshTimelineMidi()
        refreshDivisionList()
    }

    /// 已命名 + Yes：对照源码，不检查 `Save()` 成败，仍关工程。
    private func saveTitledIgnoringResult() {
        guard let projectURL else { return }
        try? writeProject(to: projectURL)
    }

    private func presentClosePrompt(then finish: @escaping (BmhelperClose.Answer) -> Void) {
        let alert = NSAlert()
        alert.messageText = BmhelperClose.prompt
        alert.alertStyle = .warning
        alert.addButton(withTitle: BmhelperClose.yesTitle)
        alert.addButton(withTitle: BmhelperClose.noTitle)
        alert.addButton(withTitle: BmhelperClose.cancelTitle)
        alert.window.title = BmhelperClose.windowTitle
        let complete: (NSApplication.ModalResponse) -> Void = { response in
            let answer: BmhelperClose.Answer
            switch response {
            case .alertFirstButtonReturn:
                answer = .yes
            case .alertSecondButtonReturn:
                answer = .no
            default:
                answer = .cancel
            }
            finish(answer)
        }
        if let window {
            alert.beginSheetModal(for: window, completionHandler: complete)
        } else {
            complete(alert.runModal())
        }
    }

    private func markProjectChangedIfTitled() {
        if projectIsTitled {
            projectChanged = true
        }
    }

    private func selectListedDivision(_ index: Int) {
        guard let next = BmhelperDivisionList.select(index, count: storedDivisions.count) else { return }
        if selectedIndex == next { return }
        commitCurrentToStored()
        selectedIndex = next
        applyStoredDivision(at: next)
        refreshTimelineMidi()
        refreshStatus()
    }

    private func commitCurrentToStored() {
        guard let index = selectedIndex, storedDivisions.indices.contains(index) else { return }
        storedDivisions[index] = savedCurrentDivision()
    }

    private func applyStoredDivision(at index: Int) {
        guard storedDivisions.indices.contains(index) else { return }
        let division = storedDivisions[index]
        lastDefinitionName = division.name
        lastSettings.name = division.name
        lastSettings.zzDefinition = division.zzEnabled
        lastDivision = BmhelperDivisionResult(
            definitions: division.definitions,
            src2def: division.src2def,
            notes: division.midi.notes,
            quantize: max(division.midi.quantize, 1)
        )
        if defDialog.window?.isVisible == true {
            presentDefinitions(alreadyDivided: true)
        }
        if audioSplitter.window?.isVisible == true {
            audioSplitter.window?.title = BmhelperAudioSplitterLayout.title(divisionName: lastDefinitionName)
        }
    }

    private func presentRenameDialog() {
        let alert = NSAlert()
        alert.messageText = BmhelperRename.prompt(current: lastDefinitionName)
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: BmhelperRename.displayName(lastDefinitionName))
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.window.title = BmhelperRename.windowTitle
        alert.window.initialFirstResponder = field
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            let entered: String? = response == .alertFirstButtonReturn ? field.stringValue : nil
            self?.applyRename(entered)
        }
        if let window {
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(alert.runModal())
        }
    }

    private func presentDeleteDialog() {
        guard let index = selectedIndex, storedDivisions.indices.contains(index) else { return }
        let alert = NSAlert()
        alert.messageText = BmhelperDelete.prompt(lastDefinitionName)
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Yes")
        alert.addButton(withTitle: "No")
        alert.window.title = BmhelperDelete.windowTitle
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            let confirmed: Bool? = response == .alertFirstButtonReturn ? true : false
            self?.applyDelete(confirmed, at: index)
        }
        if let window {
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(alert.runModal())
        }
    }

    /// No / 取消不删。Yes 只去掉选中项，不重新聚类。
    private func applyDelete(_ confirmed: Bool?, at index: Int) {
        guard BmhelperDelete.commit(confirmed) else { return }
        guard storedDivisions.indices.contains(index) else { return }
        storedDivisions.remove(at: index)
        selectedIndex = BmhelperDelete.selectionAfterDelete(
            deleted: index,
            remaining: storedDivisions.count
        )
        if let next = selectedIndex {
            applyStoredDivision(at: next)
        }
        markProjectChangedIfTitled()
        refreshTimelineMidi()
        refreshDivisionList()
    }

    /// 取消不改名。确定后只改选中项的名字，不重新聚类。
    private func applyRename(_ entered: String?) {
        guard let name = BmhelperRename.commit(entered) else { return }
        lastDefinitionName = name
        lastSettings.name = name
        if let index = selectedIndex, storedDivisions.indices.contains(index) {
            storedDivisions[index].name = name
        }
        markProjectChangedIfTitled()
        refreshDivisionList()
        if defDialog.window?.isVisible == true {
            presentDefinitions(alreadyDivided: true)
        }
        if audioSplitter.window?.isVisible == true {
            audioSplitter.window?.title = BmhelperAudioSplitterLayout.title(divisionName: name)
        }
    }

    private func presentDivisionSettings() {
        var setting = lastSettings
        setting.name = lastDefinitionName
        divisionSettings.present(setting: setting, quantize: lastQuantize) { [weak self] updated in
            self?.appendDivision(updated)
        }
    }

    /// 对照 `OnDivRegenerate`：设置窗用默认值加当前名，不带 `lastSettings` 里改过的阈值。
    private func presentRegenerateSettings() {
        guard hasProject, let index = selectedIndex, storedDivisions.indices.contains(index) else {
            return
        }
        let stored = storedDivisions[index]
        let quantize = max(stored.source.quantize > 0 ? stored.source.quantize : lastQuantize, 1)
        let setting = BmhelperDivisionSetting.makeDefault(name: lastDefinitionName, quantize: quantize)
        divisionSettings.present(setting: setting, quantize: quantize) { [weak self] updated in
            self?.applyRegenerate(updated)
        }
    }

    /// 对照 `divedit.cpp` 的 `Transpose to...`。定义为空则不弹窗。
    private func presentTransposeTo() {
        guard hasProject, selectedIndex != nil else { return }
        guard !lastDivision.definitions.isEmpty else { return }
        let defaultText = lastDivision.definitions[0].zz
        defTranspose.present(
            defaultText: defaultText,
            zzEnabled: lastSettings.zzDefinition
        ) { [weak self] nbegin in
            self?.applyTranspose(.to(nbegin))
        }
    }

    /// 只改选中项的 `definitions[].zz`。`div` / 音符 / `src2def` 不动。
    /// 已命名则变脏。定义窗若已打开则刷新。
    private func applyTranspose(_ kind: BmhelperTranspose.Kind) {
        guard let index = selectedIndex, storedDivisions.indices.contains(index) else { return }
        let next = BmhelperTranspose.apply(
            zzEnabled: lastSettings.zzDefinition,
            zzStrings: lastDivision.definitions.map(\.zz),
            kind: kind
        )
        for i in lastDivision.definitions.indices {
            guard next.indices.contains(i) else { continue }
            lastDivision.definitions[i].zz = next[i]
        }
        storedDivisions[index] = savedCurrentDivision()
        markProjectChangedIfTitled()
        refreshStatus()
        refreshTitle()
        if defDialog.window?.isVisible == true {
            presentDefinitions(alreadyDivided: true)
        }
    }

    /// 就地重聚选中项。用该 division 的 `source.notes`；若空则退回工程 `lastNotes`。
    /// 写回同一下标。条数不变。定义窗若已打开则刷新，不新开。
    private func applyRegenerate(_ setting: BmhelperDivisionSetting) {
        guard let index = selectedIndex, storedDivisions.indices.contains(index) else { return }
        let applied = setting
        let stored = storedDivisions[index]
        let notes = stored.source.notes.isEmpty ? lastNotes : stored.source.notes
        let quantize = max(stored.source.quantize > 0 ? stored.source.quantize : lastQuantize, 1)
        lastSettings = applied
        if !applied.name.isEmpty {
            lastDefinitionName = applied.name
        } else {
            lastDefinitionName = BmhelperDefDialogLayout.defaultName
        }
        lastDivision = BmhelperDivision.divide(
            notes: notes,
            setting: lastSettings,
            quantize: quantize
        )
        var saved = savedCurrentDivision()
        saved.source = stored.source
        storedDivisions[index] = saved
        markProjectChangedIfTitled()
        refreshTimelineMidi()
        refreshDivisionList()
        if defDialog.window?.isVisible == true {
            presentDefinitions(alreadyDivided: true)
        }
    }

    /// 对照 `_NewDivision`：用新设置对源 MIDI 再聚类，追加并选中新项。
    private func appendDivision(_ setting: BmhelperDivisionSetting) {
        commitCurrentToStored()
        lastSettings = setting
        if !setting.name.isEmpty {
            lastDefinitionName = setting.name
        }
        lastDivision = BmhelperDivision.divide(
            notes: lastNotes,
            setting: lastSettings,
            quantize: lastQuantize
        )
        storedDivisions.append(savedCurrentDivision())
        selectedIndex = BmhelperDivisionList.selectionAfterAppend(count: storedDivisions.count)
        markProjectChangedIfTitled()
        refreshTimelineMidi()
        refreshDivisionList()
        presentDefinitions(alreadyDivided: true)
    }

    private func presentDefinitions(alreadyDivided: Bool = false) {
        if !alreadyDivided {
            lastDivision = BmhelperDivision.divide(
                notes: lastNotes,
                setting: lastSettings,
                quantize: lastQuantize
            )
        }
        defDialog.present(
            filename: lastDefinitionName,
            zzStrings: lastDivision.definitions.map(\.zz),
            divs: lastDivision.definitions.map(\.div),
            offset: 0
        )
    }

    private func presentOpenError(url: URL) {
        let alert = NSAlert()
        alert.messageText = BmhelperMainLayout.openFailedTitle
        alert.informativeText = url.path
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    /// 对照 `OnDropFiles` 失败文案。带路径。同步弹出，才能继续试下一个。
    private func presentDropFailed(path: String) {
        let alert = NSAlert()
        alert.messageText = BmhelperDrop.dropFailedMessage(path)
        alert.runModal()
    }

    private func presentSmfOutError() {
        let alert = NSAlert()
        alert.messageText = BmhelperSmfOut.failedMessage
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    /// 对照原文：剪贴板打不开时提示同一句。按钮和菜单共用。
    private func writeClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        if !NSPasteboard.general.setString(text, forType: .string) {
            presentClipboardUnavailable()
        }
    }

    private func presentClipboardUnavailable() {
        let alert = NSAlert()
        alert.messageText = BmhelperRightPane.clipboardUnavailable
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private static let midiTypes: [UTType] = {
        BmhelperMidi.fileExtensions.compactMap { UTType(filenameExtension: $0) }
    }()
}

@MainActor
enum BmhelperMenuBar {
    static func make() -> NSMenu {
        let menu = NSMenu(title: BmhelperMainLayout.title)
        menu.addItem(submenu(BmhelperMainLayout.title, ["About Be-Music Helper", "Quit Be-Music Helper"]))
        menu.addItem(submenu(BmhelperMainLayout.fileMenuTitle, [
            BmhelperMainLayout.newMenuTitle,
            BmhelperMainLayout.openProjectMenuTitle,
            BmhelperMainLayout.saveProjectMenuTitle,
            BmhelperMainLayout.saveProjectAsMenuTitle,
            BmhelperClose.menuTitle
        ]))
        menu.addItem(submenu(BmhelperMainLayout.divisionsMenuTitle, [
            BmhelperMainLayout.newDivisionMenuTitle,
            BmhelperRename.menuTitle,
            BmhelperRegenerate.menuTitle,
            BmhelperDelete.menuTitle,
            BmhelperSmfOut.menuTitle,
            BmhelperMainLayout.defOutMenuTitle,
            BmhelperMainLayout.openCutterMenuTitle,
            BmhelperDivCopy.menuTitle,
            BmhelperSequence.menuTitle
        ]))
        menu.addItem(submenu(BmhelperMainLayout.helpMenuTitle, [BmhelperAbout.menuTitle]))
        return menu
    }

    static func bind(_ menu: NSMenu, to target: BmhelperWindowController) {
        if let app = menu.item(withTitle: BmhelperMainLayout.title)?.submenu {
            if let item = app.item(withTitle: "About Be-Music Helper") {
                item.action = #selector(BmhelperWindowController.showAbout(_:))
                item.target = target
            }
            if let item = app.item(withTitle: "Quit Be-Music Helper") {
                item.action = #selector(NSApplication.terminate(_:))
                item.target = NSApp
                item.keyEquivalent = "q"
            }
        }
        if let file = menu.item(withTitle: BmhelperMainLayout.fileMenuTitle)?.submenu {
            if let item = file.item(withTitle: BmhelperMainLayout.newMenuTitle) {
                item.action = #selector(BmhelperWindowController.newFromMidi(_:))
                item.target = target
                item.keyEquivalent = "n"
            }
            if let item = file.item(withTitle: BmhelperMainLayout.openProjectMenuTitle) {
                item.action = #selector(BmhelperWindowController.openProject(_:))
                item.target = target
                item.keyEquivalent = "o"
            }
            if let item = file.item(withTitle: BmhelperMainLayout.saveProjectMenuTitle) {
                item.action = #selector(BmhelperWindowController.saveProject(_:))
                item.target = target
                item.keyEquivalent = "s"
            }
            if let item = file.item(withTitle: BmhelperMainLayout.saveProjectAsMenuTitle) {
                item.action = #selector(BmhelperWindowController.saveProjectAs(_:))
                item.target = target
                item.keyEquivalent = "s"
                item.keyEquivalentModifierMask = [.command, .shift]
            }
            if let item = file.item(withTitle: BmhelperClose.menuTitle) {
                item.action = #selector(BmhelperWindowController.closeProject(_:))
                item.target = target
            }
        }
        if let divisions = menu.item(withTitle: BmhelperMainLayout.divisionsMenuTitle)?.submenu {
            if let item = divisions.item(withTitle: BmhelperMainLayout.newDivisionMenuTitle) {
                item.action = #selector(BmhelperWindowController.newDivision(_:))
                item.target = target
            }
            if let item = divisions.item(withTitle: BmhelperRename.menuTitle) {
                item.action = #selector(BmhelperWindowController.renameDivision(_:))
                item.target = target
            }
            if let item = divisions.item(withTitle: BmhelperRegenerate.menuTitle) {
                item.action = #selector(BmhelperWindowController.regenerateDivision(_:))
                item.target = target
                item.keyEquivalent = "r"
            }
            if let item = divisions.item(withTitle: BmhelperDelete.menuTitle) {
                item.action = #selector(BmhelperWindowController.deleteDivision(_:))
                item.target = target
            }
            if let item = divisions.item(withTitle: BmhelperSmfOut.menuTitle) {
                item.action = #selector(BmhelperWindowController.writeModifiedMidi(_:))
                item.target = target
            }
            if let item = divisions.item(withTitle: BmhelperMainLayout.defOutMenuTitle) {
                item.action = #selector(BmhelperWindowController.showWavDefinitions(_:))
                item.target = target
            }
            if let item = divisions.item(withTitle: BmhelperMainLayout.openCutterMenuTitle) {
                item.action = #selector(BmhelperWindowController.openAudioCutter(_:))
                item.target = target
            }
            if let item = divisions.item(withTitle: BmhelperDivCopy.menuTitle) {
                item.action = #selector(BmhelperWindowController.copyDivision(_:))
                item.target = target
            }
            if let item = divisions.item(withTitle: BmhelperSequence.menuTitle) {
                item.action = #selector(BmhelperWindowController.copyBmsSequence(_:))
                item.target = target
            }
        }
        if let help = menu.item(withTitle: BmhelperMainLayout.helpMenuTitle)?.submenu {
            if let item = help.item(withTitle: BmhelperAbout.menuTitle) {
                item.action = #selector(BmhelperWindowController.showAbout(_:))
                item.target = target
            }
        }
    }

    private static func submenu(_ title: String, _ items: [String]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        for name in items {
            menu.addItem(NSMenuItem(title: name, action: nil, keyEquivalent: ""))
        }
        item.submenu = menu
        return item
    }
}

@MainActor
final class BmhelperDefTransposeWindowController: NSWindowController, NSWindowDelegate {
    private let dialogView: BmhelperDefTransposeView

    init() {
        let size = BmhelperDefTransposeLayout.clientSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = BmhelperDefTransposeLayout.title
        window.isReleasedWhenClosed = false
        window.contentMinSize = size
        window.contentMaxSize = size
        dialogView = BmhelperDefTransposeView(frame: NSRect(origin: .zero, size: size))
        super.init(window: window)
        window.delegate = self
        window.contentView = dialogView
        window.setContentSize(size)
    }

    required init?(coder: NSCoder) { nil }

    func present(defaultText: String, zzEnabled: Bool, onOK: @escaping (String) -> Void) {
        dialogView.apply(defaultText: defaultText, zzEnabled: zzEnabled) { [weak self] accepted in
            self?.window?.orderOut(self)
            onOK(accepted)
        }
        guard let window else { return }
        window.center()
        showWindow(self)
        window.makeKeyAndOrderFront(self)
        window.makeFirstResponder(dialogView.editField)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        dialogView.cancel()
        sender.orderOut(self)
        return false
    }
}

@MainActor
final class BmhelperDefDialogWindowController: NSWindowController, NSWindowDelegate {
    private let dialogView: BmhelperDefDialogView

    init() {
        let size = BmhelperDefDialogLayout.clientSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = NativeLocalization.text(BmhelperDefDialogLayout.title)
        NativeLocalization.markFixed(window, key: BmhelperDefDialogLayout.title)
        window.isReleasedWhenClosed = false
        window.contentMinSize = size
        dialogView = BmhelperDefDialogView(frame: NSRect(origin: .zero, size: size))
        super.init(window: window)
        window.delegate = self
        window.contentView = dialogView
        window.setContentSize(size)
    }

    required init?(coder: NSCoder) { nil }

    func present(
        filename: String = BmhelperDefDialogLayout.defaultName,
        zzStrings: [String] = [],
        divs: [Int] = [],
        offset: Int = 0
    ) {
        dialogView.apply(filename: filename, zzStrings: zzStrings, divs: divs, offset: offset)
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
private final class BmhelperMainView: FlippedDialogView {
    private let projectToolbar: NSView
    private let projectSummary = NSTextField(labelWithString: "")
    private let midiView: BmhelperSourceMidiView
    private let lowerPane: BmhelperLowerPane
    private let rightPane: BmhelperRightPaneView
    private let sourceDivider = BmhelperDragDivider(vertical: false)
    private let inspectorDivider = BmhelperDragDivider(vertical: true)
    private let statusBar: BmhelperStatusBarView
    private var statusFields = ["", "", ""]
    private var hoverText = ""
    private var sourceRatio: CGFloat = 0.44
    private var inspectorWidth: CGFloat = 220
    var onNewDivision: (() -> Void)?
    var onImportMidi: (() -> Void)?
    var onOpenProject: (() -> Void)?
    var onSaveProject: (() -> Void)?
    var onSelectDivision: ((Int) -> Void)?
    var onTransposeUp: (() -> Void)?
    var onTransposeDown: (() -> Void)?
    var onTransposeTo: (() -> Void)?
    var onWriteMidi: (() -> Void)?
    var onCopyDivision: (() -> Void)?
    var onOpenCutter: (() -> Void)?
    var onOpenDefinitions: (() -> Void)?
    var onCopySequence: (() -> Void)?
    var onDropFiles: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        projectToolbar = NSView()
        midiView = BmhelperSourceMidiView(frame: .zero, title: "Source MIDI")
        lowerPane = BmhelperLowerPane(frame: .zero)
        rightPane = BmhelperRightPaneView(frame: .zero)
        statusBar = BmhelperStatusBarView(frame: .zero)
        super.init(frame: NSRect(origin: .zero, size: BmhelperMainLayout.clientSize))
        wantsLayer = true
        midiView.setAccessibilityIdentifier("bmhelper.source-midi")
        lowerPane.setAccessibilityIdentifier("bmhelper.division-workspace")
        rightPane.setAccessibilityIdentifier("bmhelper.action-inspector")
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        registerForDraggedTypes([.fileURL])

        projectToolbar.wantsLayer = true
        projectToolbar.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        let importButton = makeToolbarButton("Import MIDI", action: #selector(importMidiClicked))
        let openButton = makeToolbarButton("Open Project", action: #selector(openProjectClicked))
        let saveButton = makeToolbarButton("Save", action: #selector(saveProjectClicked))
        projectSummary.lineBreakMode = .byTruncatingMiddle
        projectSummary.textColor = .secondaryLabelColor
        projectSummary.setAccessibilityLabel(NativeLocalization.text("Project Status"))
        [importButton, openButton, saveButton, projectSummary].forEach(projectToolbar.addSubview(_:))
        addSubview(projectToolbar)

        addSubview(midiView)
        addSubview(lowerPane)
        addSubview(rightPane)
        addSubview(sourceDivider)
        addSubview(inspectorDivider)
        sourceDivider.onDrag = { [weak self] point in
            guard let self else { return }
            let workspace = BmhelperMainLayout.contentSplitFrame(size: self.bounds.size, statusHeight: self.statusBar.workingHeight)
            self.sourceRatio = min(max((point.y - workspace.minY) / max(workspace.height, 1), 0.28), 0.72)
            self.needsLayout = true
        }
        inspectorDivider.onDrag = { [weak self] point in
            guard let self else { return }
            self.inspectorWidth = min(max(self.bounds.width - point.x, 200), 320)
            self.needsLayout = true
        }
        addSubview(statusBar)
        midiView.onHover = { [weak self] text in
            self?.applyHover(text)
        }
        lowerPane.onHover = { [weak self] text in
            self?.applyHover(text)
        }
        lowerPane.onNewDivision = { [weak self] in
            self?.onNewDivision?()
        }
        lowerPane.onSelect = { [weak self] index in
            self?.onSelectDivision?(index)
        }
        lowerPane.onTransposeUp = { [weak self] in
            self?.onTransposeUp?()
        }
        lowerPane.onTransposeDown = { [weak self] in
            self?.onTransposeDown?()
        }
        lowerPane.onTransposeTo = { [weak self] in
            self?.onTransposeTo?()
        }
        rightPane.onWriteMidi = { [weak self] in
            self?.onWriteMidi?()
        }
        rightPane.onCopyDivision = { [weak self] in
            self?.onCopyDivision?()
        }
        rightPane.onOpenCutter = { [weak self] in
            self?.onOpenCutter?()
        }
        rightPane.onOpenDefinitions = { [weak self] in
            self?.onOpenDefinitions?()
        }
        rightPane.onCopySequence = { [weak self] in
            self?.onCopySequence?()
        }
        applyStatus(BmhelperStatus.fields(hasProject: false))
    }

    required init?(coder: NSCoder) { nil }

    func reloadDivisions(names: [String], selection: Int?) {
        lowerPane.reload(names: names, selection: selection)
    }

    func setRightButtonsEnabled(_ enabled: Bool) {
        rightPane.setEnabled(enabled)
    }

    func setProjectSummary(hasProject: Bool, name: String, changed: Bool) {
        guard hasProject else {
            projectSummary.stringValue = NativeLocalization.text("No project yet.") + " "
                + NativeLocalization.text("Import MIDI or open an existing project.")
            return
        }
        let displayedName = name.isEmpty ? NativeLocalization.text("Untitled project") : name
        projectSummary.stringValue = changed
            ? NativeLocalization.format("Project has unsaved changes: %@", displayedName)
            : displayedName
    }

    func reloadDefinitionView(_ definitions: [(zz: String, div: Int)]?) {
        lowerPane.reloadDefinitions(definitions)
    }

    func setSourceMidi(notes: [MidiNoteEvent]?, quantize: Int) {
        midiView.setMidiData(notes: notes, quantize: quantize)
    }

    func setTimelineMidi(notes: [MidiNoteEvent]?, quantize: Int) {
        lowerPane.setTimelineMidi(notes: notes, quantize: quantize)
    }

    func applyStatus(_ fields: [String]) {
        statusFields = fields
        paintStatus()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedFileURLs(from: sender).isEmpty ? [] : .copy
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !droppedFileURLs(from: sender).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = droppedFileURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onDropFiles?(urls)
        return true
    }

    private func droppedFileURLs(from sender: NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
    }

    override func layout() {
        super.layout()
        let barHeight = statusBar.workingHeight
        let toolbarHeight = BmhelperMainLayout.projectToolbarHeight
        projectToolbar.frame = CGRect(x: 0, y: 0, width: bounds.width, height: toolbarHeight)
        let buttons = projectToolbar.subviews.compactMap { $0 as? NSButton }
        var x: CGFloat = 12
        for button in buttons {
            let width = max(button.intrinsicContentSize.width + 18, 76)
            button.frame = CGRect(x: x, y: 6, width: width, height: 28)
            x += width + 8
        }
        projectSummary.frame = CGRect(x: x + 8, y: 10, width: max(bounds.width - x - 20, 0), height: 20)
        let workspace = BmhelperMainLayout.contentSplitFrame(size: bounds.size, statusHeight: barHeight)
        let rightWidth = min(max(inspectorWidth, 200), min(320, max(workspace.width - 540, 200)))
        let leftWidth = max(workspace.width - rightWidth - 1, 0)
        let sourceHeight = min(max(220, workspace.height * sourceRatio), max(workspace.height - 180, 0))
        midiView.frame = CGRect(x: workspace.minX, y: workspace.minY, width: leftWidth, height: sourceHeight)
        lowerPane.frame = CGRect(x: workspace.minX, y: workspace.minY + sourceHeight + 1, width: leftWidth, height: max(workspace.height - sourceHeight - 1, 0))
        rightPane.frame = CGRect(x: workspace.minX + leftWidth + 1, y: workspace.minY, width: max(rightWidth - 1, 0), height: workspace.height)
        sourceDivider.frame = CGRect(x: workspace.minX, y: workspace.minY + sourceHeight - 3, width: leftWidth, height: 6)
        inspectorDivider.frame = CGRect(x: workspace.minX + leftWidth - 3, y: workspace.minY, width: 6, height: workspace.height)
        statusBar.frame = CGRect(x: 0, y: toolbarHeight + workspace.height, width: bounds.width, height: barHeight)
    }

    @objc private func importMidiClicked() { onImportMidi?() }
    @objc private func openProjectClicked() { onOpenProject?() }
    @objc private func saveProjectClicked() { onSaveProject?() }

    private func makeToolbarButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: NativeLocalization.text(title), target: self, action: action)
        NativeLocalization.markFixed(button, key: title)
        button.bezelStyle = .texturedRounded
        button.setAccessibilityLabel(title)
        return button
    }

    func layoutSnapshotForTesting() -> BmhelperWindowLayoutSnapshot {
        BmhelperWindowLayoutSnapshot(
            sourceFrame: midiView.frame,
            divisionFrame: lowerPane.frame,
            inspectorFrame: rightPane.frame,
            actionFrames: rightPane.buttonFramesForTesting(),
            definitionFrame: convert(lowerPane.definitionFrameForTesting(), from: lowerPane),
            divisionListFrame: convert(lowerPane.divisionListFrameForTesting(), from: lowerPane),
            transposeFrames: lowerPane.transposeFramesForTesting().map { convert($0, from: lowerPane) }
        )
    }


    private func applyHover(_ text: String) {
        hoverText = text
        paintStatus()
    }

    /// 左列写悬停文案。中列 / 右列保持 BH-STAT。
    private func paintStatus() {
        var fields = statusFields
        if fields.isEmpty {
            fields = ["", "", ""]
        }
        fields[0] = hoverText
        statusBar.apply(fields)
    }
}

@MainActor
private final class BmhelperDragDivider: NSView {
    let vertical: Bool
    var onDrag: ((CGPoint) -> Void)?

    init(vertical: Bool) {
        self.vertical = vertical
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.separatorColor.cgColor
    }

    required init?(coder: NSCoder) { nil }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: vertical ? .resizeLeftRight : .resizeUpDown)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let superview else { return }
        onDrag?(superview.convert(event.locationInWindow, from: nil))
    }
}

/// 对照 `mdview.cpp` 的 `MidiView`。上半窗格传入源 MIDI，左栏传入时间线。
/// 没有 data 时铺灰底。音符矩形按同一套整数公式。滚轮对照 `OnMouseWheel`。未截图。
@MainActor
private final class BmhelperSourceMidiView: FlippedDialogView {
    private let sectionTitle: String?
    var onHover: ((String) -> Void)?
    private var notes: [MidiNoteEvent]?
    private var quantize = 480
    private var scroll = BmhelperMidiView.Point(x: 0, y: 0)
    private var cachedMetrics: BmhelperMidiView.Metrics?
    private var keepWheelState = false
    private var tracking: NSTrackingArea?

    init(frame frameRect: NSRect, title: String? = nil) {
        sectionTitle = title.map { NativeLocalization.text($0) }
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Self.noDataColor.cgColor
    }

    required init?(coder: NSCoder) { nil }

    func setMidiData(notes: [MidiNoteEvent]?, quantize: Int) {
        self.notes = notes
        self.quantize = max(quantize, 1)
        keepWheelState = false
        cachedMetrics = nil
        applyInitialScroll()
        needsDisplay = true
        onHover?("")
    }

    override func layout() {
        super.layout()
        if !keepWheelState {
            applyInitialScroll()
        }
    }

    /// Command 对照 `ControlDown`。Shift 对照 `ShiftDown`。没有 data 不改。
    override func scrollWheel(with event: NSEvent) {
        if !event.momentumPhase.isEmpty {
            return
        }
        let deltaY = event.scrollingDeltaY
        let deltaX = event.scrollingDeltaX
        let delta = deltaY != 0 ? deltaY : deltaX
        guard delta != 0 else { return }
        let metrics = currentMetrics()
        let result = BmhelperMidiView.applyWheel(
            metrics: metrics,
            scroll: scroll,
            client: clientSize(),
            command: event.modifierFlags.contains(.command),
            shift: event.modifierFlags.contains(.shift),
            up: delta > 0
        )
        guard metrics.hasData else { return }
        keepWheelState = true
        cachedMetrics = result.metrics
        scroll = result.scroll
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        reportHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        reportHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        onHover?("")
    }

    override func draw(_ dirtyRect: NSRect) {
        let metrics = currentMetrics()
        if metrics.hasData {
            Self.dataColor.setFill()
        } else {
            Self.noDataColor.setFill()
        }
        bounds.fill()
        drawSectionTitle()
        guard metrics.hasData else { return }
        for note in metrics.notes {
            let rect = BmhelperMidiView.noteRect(note: note, metrics: metrics, scroll: scroll)
            let frame = CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
            noteColor(velocity: note.velocity).setFill()
            frame.fill()
        }
    }

    private func applyInitialScroll() {
        let metrics = BmhelperMidiView.metrics(
            notes: notes,
            quantize: quantize,
            client: clientSize()
        )
        cachedMetrics = metrics
        scroll = BmhelperMidiView.Point(x: 0, y: metrics.hasData ? metrics.ypos : 0)
    }

    private func clientSize() -> BmhelperMidiView.Size {
        BmhelperMidiView.Size(
            width: max(Int(bounds.width.rounded(.towardZero)), 1),
            height: max(Int(bounds.height.rounded(.towardZero)), 1)
        )
    }

    private func currentMetrics() -> BmhelperMidiView.Metrics {
        if keepWheelState, let cached = cachedMetrics {
            return cached
        }
        return BmhelperMidiView.metrics(
            notes: notes,
            quantize: quantize,
            client: clientSize()
        )
    }

    private func reportHover(at point: CGPoint) {
        let metrics = currentMetrics()
        let hit = BmhelperMidiView.Point(
            x: Int(point.x.rounded(.towardZero)),
            y: Int(point.y.rounded(.towardZero))
        )
        onHover?(BmhelperMidiView.hoverText(at: hit, metrics: metrics, scroll: scroll))
    }

    private func noteColor(velocity: Int) -> NSColor {
        let c1 = 64 + (160 - 64) * velocity / 128
        let c2 = 64 + (256 - 64) * velocity / 128
        return NSColor(
            srgbRed: CGFloat(c1) / 255,
            green: CGFloat(c2) / 255,
            blue: CGFloat(c1) / 255,
            alpha: 1
        )
    }

    private func drawSectionTitle() {
        guard let sectionTitle else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        (sectionTitle as NSString).draw(at: CGPoint(x: 8, y: 6), withAttributes: attributes)
    }

    private static let noDataColor = NSColor.controlBackgroundColor
    private static let dataColor = NSColor(srgbRed: 64 / 255, green: 64 / 255, blue: 64 / 255, alpha: 1)
}

/// 对照 `divview.cpp`：名单在左、五个按钮在右。
/// `SplitVertically`，右栏提示宽 200，最小窗格 125，重力在左。
/// 左栏：时间线钢琴卷、定义条、名单。
@MainActor
private final class BmhelperLowerPane: FlippedDialogView, NSSplitViewDelegate {
    private let divisionsPane: BmhelperDivisionsPane
    var onHover: ((String) -> Void)?
    var onNewDivision: (() -> Void)?
    var onSelect: ((Int) -> Void)?
    var onTransposeUp: (() -> Void)?
    var onTransposeDown: (() -> Void)?
    var onTransposeTo: (() -> Void)?

    override init(frame frameRect: NSRect) {
        divisionsPane = BmhelperDivisionsPane(frame: .zero)
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        addSubview(divisionsPane)

        divisionsPane.onHover = { [weak self] text in
            self?.onHover?(text)
        }
        divisionsPane.onNewDivision = { [weak self] in
            self?.onNewDivision?()
        }
        divisionsPane.onSelect = { [weak self] index in
            self?.onSelect?(index)
        }
        divisionsPane.onTransposeUp = { [weak self] in
            self?.onTransposeUp?()
        }
        divisionsPane.onTransposeDown = { [weak self] in
            self?.onTransposeDown?()
        }
        divisionsPane.onTransposeTo = { [weak self] in
            self?.onTransposeTo?()
        }
    }

    required init?(coder: NSCoder) { nil }

    func reload(names: [String], selection: Int?) {
        divisionsPane.reload(names: names, selection: selection)
    }

    func reloadDefinitions(_ definitions: [(zz: String, div: Int)]?) {
        divisionsPane.reloadDefinitions(definitions)
    }

    func setTimelineMidi(notes: [MidiNoteEvent]?, quantize: Int) {
        divisionsPane.setTimelineMidi(notes: notes, quantize: quantize)
    }

    func definitionFrameForTesting() -> CGRect { divisionsPane.definitionFrameForTesting() }
    func divisionListFrameForTesting() -> CGRect { divisionsPane.divisionListFrameForTesting() }
    func transposeFramesForTesting() -> [CGRect] { divisionsPane.transposeFramesForTesting() }

    override func layout() {
        super.layout()
        divisionsPane.frame = bounds
    }
}

/// 对照 `divedit.cpp` 右侧五个按钮。sizer 比例 2/1/1/2/2，铺满右栏。
@MainActor
private final class BmhelperRightPaneView: FlippedDialogView {
    private let buttons: [NSButton]
    var onWriteMidi: (() -> Void)?
    var onCopyDivision: (() -> Void)?
    var onOpenCutter: (() -> Void)?
    var onOpenDefinitions: (() -> Void)?
    var onCopySequence: (() -> Void)?

    override init(frame frameRect: NSRect) {
        buttons = BmhelperRightPane.titles.enumerated().map { index, title in
            let button = NSButton(title: NativeLocalization.text(title), target: nil, action: nil)
            button.bezelStyle = .rounded
            button.tag = index
            NativeLocalization.markFixed(button, key: title)
            button.setAccessibilityLabel(NativeLocalization.text(title))
            return button
        }
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        for button in buttons {
            button.target = self
            button.action = #selector(clicked(_:))
            button.isEnabled = false
            addSubview(button)
        }
    }

    required init?(coder: NSCoder) { nil }

    func setEnabled(_ enabled: Bool) {
        for button in buttons {
            button.isEnabled = enabled
        }
    }

    func buttonFramesForTesting() -> [CGRect] { buttons.map(\.frame) }

    override func layout() {
        super.layout()
        var y: CGFloat = 12
        for button in buttons {
            button.frame = CGRect(x: 10, y: y, width: max(bounds.width - 20, 0), height: 32)
            y += 40
        }
    }

    @objc private func clicked(_ sender: NSButton) {
        switch sender.tag {
        case 0:
            onWriteMidi?()
        case 1:
            onCopyDivision?()
        case 2:
            onOpenCutter?()
        case 3:
            onOpenDefinitions?()
        case 4:
            onCopySequence?()
        default:
            break
        }
    }
}

/// 对照 `defview.cpp` 的 `DefinitionView`。只画 zz 和 div，不点选。
/// 没有 division 时铺系统按钮灰。超过客户区按格横滑。
@MainActor
private final class BmhelperDefinitionViewBar: FlippedDialogView {
    private let scroller = NSScroller()
    private var items: [BmhelperDefinitionView.Item] = []
    private var scrollPos = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlColor.cgColor
        scroller.controlSize = .small
        scroller.target = self
        scroller.action = #selector(scrollerChanged(_:))
        addSubview(scroller)
        reload(nil)
    }

    required init?(coder: NSCoder) { nil }

    func reload(_ definitions: [(zz: String, div: Int)]?) {
        items = BmhelperDefinitionView.items(definitions)
        scrollPos = 0
        applyScroll()
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let height = NSScroller.scrollerWidth(for: .small, scrollerStyle: scroller.scrollerStyle)
        scroller.frame = CGRect(
            x: 0,
            y: max(bounds.height - height, 0),
            width: bounds.width,
            height: height
        )
        applyScroll()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlColor.setFill()
        bounds.fill()
        guard !items.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor
        ]
        for (index, item) in items.enumerated() {
            let zz = BmhelperDefinitionView.zzPoint(index: index, scrollPos: scrollPos)
            let div = BmhelperDefinitionView.divPoint(index: index, scrollPos: scrollPos)
            (item.zz as NSString).draw(at: CGPoint(x: zz.x, y: zz.y), withAttributes: attrs)
            (item.divText as NSString).draw(at: CGPoint(x: div.x, y: div.y), withAttributes: attrs)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX
            : event.scrollingDeltaY
        guard delta != 0 else { return }
        let step = delta > 0 ? -1 : 1
        scrollPos = BmhelperDefinitionView.clampScroll(
            pos: scrollPos + step,
            count: items.count,
            page: currentPage()
        )
        applyScroll()
        needsDisplay = true
    }

    @objc private func scrollerChanged(_ sender: NSScroller) {
        let page = currentPage()
        let maxPos = max(items.count - page, 0)
        let next: Int
        switch sender.hitPart {
        case .decrementPage:
            next = scrollPos - max(page, 1)
        case .incrementPage:
            next = scrollPos + max(page, 1)
        case .decrementLine:
            next = scrollPos - 1
        case .incrementLine:
            next = scrollPos + 1
        case .knob, .knobSlot:
            next = Int((sender.doubleValue * Double(max(maxPos, 0))).rounded())
        default:
            return
        }
        scrollPos = BmhelperDefinitionView.clampScroll(pos: next, count: items.count, page: page)
        applyScroll()
        needsDisplay = true
    }

    private func currentPage() -> Int {
        BmhelperDefinitionView.page(clientWidth: Int(bounds.width.rounded(.towardZero)))
    }

    private func applyScroll() {
        let page = currentPage()
        scrollPos = BmhelperDefinitionView.clampScroll(pos: scrollPos, count: items.count, page: page)
        if items.isEmpty {
            scroller.isHidden = true
            scroller.isEnabled = false
            scroller.knobProportion = 1
            scroller.doubleValue = 0
            return
        }
        scroller.isHidden = false
        if items.count <= page {
            scroller.isEnabled = false
            scroller.knobProportion = 1
            scroller.doubleValue = 0
            return
        }
        scroller.isEnabled = true
        scroller.knobProportion = CGFloat(page) / CGFloat(items.count)
        let range = items.count - page
        scroller.doubleValue = range > 0 ? Double(scrollPos) / Double(range) : 0
    }
}

/// 对照 `DivisionsView` 左栏：上边按钮，中间时间线钢琴卷，再下面定义条和平移按钮，名单在底。
/// 竖向分割：钢琴卷占剩余，下面定义条+名单较短。对照 sash `-60`，不是截图像素。
/// 定义条和 `<` / `>` / `Transpose to...` 同一行：左边格，右边按钮列（比例 8 / 1）。
/// Delete、Copy division 和 Copy BMS sequence 在 Divisions 菜单；右侧五个按钮在右栏。
@MainActor
private final class BmhelperDivisionsPane: FlippedDialogView, NSTableViewDataSource, NSTableViewDelegate {
    private let newButton: NSButton
    private let timelineView: BmhelperSourceMidiView
    private let editorSplitter: NSSplitView
    private let definitionView: BmhelperDefinitionViewBar
    private let upButton: NSButton
    private let downButton: NSButton
    private let toButton: NSButton
    private let table: NSTableView
    private var names: [String] = []
    private var suppressSelection = false
    private var placedEditorSash = false
    var onHover: ((String) -> Void)?
    var onNewDivision: (() -> Void)?
    var onSelect: ((Int) -> Void)?
    var onTransposeUp: (() -> Void)?
    var onTransposeDown: (() -> Void)?
    var onTransposeTo: (() -> Void)?

    override init(frame frameRect: NSRect) {
        newButton = NSButton(title: NativeLocalization.text(BmhelperDivisionList.buttonTitle), target: nil, action: nil)
        timelineView = BmhelperSourceMidiView(frame: .zero, title: "Slice Timeline")
        editorSplitter = NSSplitView()
        definitionView = BmhelperDefinitionViewBar(frame: .zero)
        upButton = NSButton(title: NativeLocalization.text(BmhelperDefTransposeLayout.upTitle), target: nil, action: nil)
        downButton = NSButton(title: NativeLocalization.text(BmhelperDefTransposeLayout.downTitle), target: nil, action: nil)
        toButton = NSButton(title: NativeLocalization.text(BmhelperDefTransposeLayout.toTitle), target: nil, action: nil)
        table = NSTableView()
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        newButton.bezelStyle = .rounded
        NativeLocalization.markFixed(newButton, key: BmhelperDivisionList.buttonTitle)
        newButton.setAccessibilityLabel(NativeLocalization.text(BmhelperDivisionList.buttonTitle))
        newButton.target = self
        newButton.action = #selector(newClicked)
        newButton.setContentHuggingPriority(.required, for: .vertical)

        timelineView.onHover = { [weak self] text in
            self?.onHover?(text)
        }
        timelineView.setContentHuggingPriority(.defaultLow, for: .vertical)
        timelineView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        configureTransposeButton(upButton, action: #selector(upClicked))
        configureTransposeButton(downButton, action: #selector(downClicked))
        configureTransposeButton(toButton, action: #selector(toClicked))
        setTransposeEnabled(false)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.title = ""
        table.addTableColumn(column)
        table.headerView = nil
        table.allowsEmptySelection = false
        table.allowsMultipleSelection = false
        table.dataSource = self
        table.delegate = self

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)

        let buttonColumn = NSStackView(views: [upButton, downButton, toButton])
        buttonColumn.orientation = .vertical
        buttonColumn.alignment = .width
        buttonColumn.distribution = .fillEqually
        buttonColumn.spacing = 4
        buttonColumn.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        buttonColumn.setContentCompressionResistancePriority(.required, for: .horizontal)

        definitionView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        definitionView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let transposeRow = NSStackView(views: [definitionView, buttonColumn])
        transposeRow.orientation = .horizontal
        transposeRow.alignment = .height
        transposeRow.distribution = .fill
        transposeRow.spacing = 4
        transposeRow.setContentHuggingPriority(.required, for: .vertical)
        let defWidth = definitionView.widthAnchor.constraint(
            equalTo: buttonColumn.widthAnchor,
            multiplier: CGFloat(BmhelperDefinitionView.barDefProportion)
                / CGFloat(BmhelperDefinitionView.barButtonProportion)
        )
        defWidth.priority = .defaultHigh
        defWidth.isActive = true

        let lowerStack = NSStackView(views: [transposeRow, scroll])
        lowerStack.orientation = .vertical
        lowerStack.alignment = .width
        lowerStack.distribution = .fill
        lowerStack.spacing = 4

        editorSplitter.isVertical = false
        editorSplitter.dividerStyle = .thin
        editorSplitter.addArrangedSubview(timelineView)
        editorSplitter.addArrangedSubview(lowerStack)
        editorSplitter.setHoldingPriority(.init(1), forSubviewAt: 0)
        editorSplitter.setHoldingPriority(.defaultHigh, forSubviewAt: 1)
        editorSplitter.setContentHuggingPriority(.defaultLow, for: .vertical)

        let stack = NSStackView(views: [newButton, editorSplitter])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.distribution = .fill
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func reload(names: [String], selection: Int?) {
        self.names = names
        suppressSelection = true
        table.reloadData()
        if let selection, names.indices.contains(selection) {
            table.selectRowIndexes(IndexSet(integer: selection), byExtendingSelection: false)
            setTransposeEnabled(true)
        } else {
            table.deselectAll(nil)
            setTransposeEnabled(false)
        }
        suppressSelection = false
    }

    func reloadDefinitions(_ definitions: [(zz: String, div: Int)]?) {
        definitionView.reload(definitions)
    }

    func setTimelineMidi(notes: [MidiNoteEvent]?, quantize: Int) {
        timelineView.setMidiData(notes: notes, quantize: quantize)
    }

    override func layout() {
        super.layout()
        applyEditorSashIfNeeded()
    }

    /// 对照 `SetSashGravity(1)`：多出来的给钢琴卷。下面那条保持较短。
    /// 不把 sash `-60` 写成已经核对过的像素。
    private func applyEditorSashIfNeeded() {
        let height = editorSplitter.bounds.height
        guard height > 0, !placedEditorSash else { return }
        placedEditorSash = true
        let bottom = max(height * (1 - min(BmhelperDivisionEditor.sashGravity, 1)), height / 3)
        editorSplitter.setPosition(max(height - bottom, 0), ofDividerAt: 0)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        names.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        names[row]
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("name")
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? {
            let view = NSTableCellView()
            view.identifier = id
            let field = NSTextField(labelWithString: "")
            field.translatesAutoresizingMaskIntoConstraints = false
            field.isBordered = false
            field.drawsBackground = false
            field.lineBreakMode = .byTruncatingTail
            view.addSubview(field)
            view.textField = field
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
                field.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
                field.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
            return view
        }()
        cell.textField?.stringValue = names[row]
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !suppressSelection else { return }
        let row = table.selectedRow
        if row >= 0 {
            onSelect?(row)
        }
    }

    @objc private func newClicked() {
        onNewDivision?()
    }

    @objc private func upClicked() {
        onTransposeUp?()
    }

    @objc private func downClicked() {
        onTransposeDown?()
    }

    @objc private func toClicked() {
        onTransposeTo?()
    }

    private func configureTransposeButton(_ button: NSButton, action: Selector) {
        button.bezelStyle = .rounded
        button.target = self
        button.action = action
        let title = button === upButton ? BmhelperDefTransposeLayout.upTitle : button === downButton ? BmhelperDefTransposeLayout.downTitle : BmhelperDefTransposeLayout.toTitle
        NativeLocalization.markFixed(button, key: title)
        button.setAccessibilityLabel(NativeLocalization.text(title))
        button.setContentHuggingPriority(.required, for: .vertical)
    }

    private func setTransposeEnabled(_ enabled: Bool) {
        upButton.isEnabled = enabled
        downButton.isEnabled = enabled
        toButton.isEnabled = enabled
    }

    func definitionFrameForTesting() -> CGRect { definitionView.convert(definitionView.bounds, to: self) }
    func divisionListFrameForTesting() -> CGRect { table.enclosingScrollView?.convert(table.enclosingScrollView!.bounds, to: self) ?? .zero }
    func transposeFramesForTesting() -> [CGRect] { [upButton, downButton, toButton].map { $0.convert($0.bounds, to: self) } }
}

/// 主窗底边三列。宽度 `-1` / `180` / `120`：左列铺满剩余，中 180，右 120。
/// 高度是一条系统标签的工作值，不是截图量出来的像素。
@MainActor
private final class BmhelperStatusBarView: FlippedDialogView {
    private let fields: [NSTextField]

    var workingHeight: CGFloat {
        let labelHeight = ceil(fields[0].fittingSize.height)
        return max(labelHeight, NSFont.smallSystemFontSize)
    }

    override init(frame frameRect: NSRect) {
        fields = (0..<3).map { _ in
            let field = NSTextField(labelWithString: "")
            field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            field.lineBreakMode = .byTruncatingTail
            return field
        }
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        for field in fields {
            addSubview(field)
        }
    }

    required init?(coder: NSCoder) { nil }

    func apply(_ texts: [String]) {
        for (index, field) in fields.enumerated() {
            field.stringValue = index < texts.count ? texts[index] : ""
        }
    }

    override func layout() {
        super.layout()
        let mid = CGFloat(BmhelperStatus.fieldWidths[1])
        let right = CGFloat(BmhelperStatus.fieldWidths[2])
        let left = max(bounds.width - mid - right, 0)
        let widths = [left, mid, right]
        var x: CGFloat = 0
        for (index, field) in fields.enumerated() {
            field.frame = CGRect(x: x, y: 0, width: widths[index], height: bounds.height)
            x += widths[index]
        }
    }
}

@MainActor
private final class BmhelperDefTransposeView: FlippedDialogView {
    let editField: NSTextView
    private let ok: NSButton
    private var zzEnabled = true
    private var onOK: ((String) -> Void)?

    override init(frame frameRect: NSRect) {
        editField = NSTextView(frame: BmhelperDefTransposeLayout.edit)
        ok = NSButton(title: BmhelperDefTransposeLayout.okTitle, target: nil, action: nil)
        super.init(frame: NSRect(origin: .zero, size: BmhelperDefTransposeLayout.clientSize))
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        editField.isRichText = false
        addSubview(editField)

        ok.frame = BmhelperDefTransposeLayout.ok
        ok.bezelStyle = .rounded
        ok.target = self
        ok.action = #selector(confirm)
        ok.keyEquivalent = "\r"
        addSubview(ok)
    }

    required init?(coder: NSCoder) { nil }

    func apply(defaultText: String, zzEnabled: Bool, onOK: @escaping (String) -> Void) {
        editField.string = defaultText
        self.zzEnabled = zzEnabled
        self.onOK = onOK
    }

    func cancel() {
        onOK = nil
    }

    @objc private func confirm() {
        let entered = editField.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let accepted = BmhelperTranspose.accept(entered, zzEnabled: zzEnabled) else {
            NSSound.beep()
            return
        }
        let finish = onOK
        onOK = nil
        finish?(accepted)
    }
}

@MainActor
private final class BmhelperDefDialogView: FlippedDialogView, NSTextFieldDelegate {
    private let filenameLabel: NSTextField
    private let name: NSTextField
    private let data: NSTextView
    private let copy: NSButton
    private let close: NSButton
    private var zzStrings: [String] = []
    private var divs: [Int] = []
    private var offset: Int = 0

    override init(frame frameRect: NSRect) {
        filenameLabel = NSTextField(labelWithString: NativeLocalization.text(BmhelperDefDialogLayout.filenameTitle))
        name = NSTextField(string: BmhelperDefDialogLayout.defaultName)
        data = NSTextView(frame: BmhelperDefDialogLayout.data)
        copy = NSButton(title: NativeLocalization.text(BmhelperDefDialogLayout.copyTitle), target: nil, action: nil)
        close = NSButton(title: NativeLocalization.text(BmhelperDefDialogLayout.closeTitle), target: nil, action: nil)
        super.init(frame: NSRect(origin: .zero, size: BmhelperDefDialogLayout.clientSize))
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        filenameLabel.frame = BmhelperDefDialogLayout.filenameLabel
        NativeLocalization.markFixed(filenameLabel, key: BmhelperDefDialogLayout.filenameTitle)
        addSubview(filenameLabel)

        name.frame = BmhelperDefDialogLayout.name
        name.delegate = self
        addSubview(name)

        data.isRichText = false
        addSubview(data)

        copy.frame = BmhelperDefDialogLayout.copy
        copy.bezelStyle = .rounded
        NativeLocalization.markFixed(copy, key: BmhelperDefDialogLayout.copyTitle)
        copy.target = self
        copy.action = #selector(copyDefinitionsToClipboard)
        addSubview(copy)

        close.frame = BmhelperDefDialogLayout.close
        close.bezelStyle = .rounded
        NativeLocalization.markFixed(close, key: BmhelperDefDialogLayout.closeTitle)
        close.target = self
        close.action = #selector(closeDialog)
        addSubview(close)
        refreshDefinitionText()
    }

    required init?(coder: NSCoder) { nil }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        let size = bounds.size
        filenameLabel.frame = BmhelperDefDialogLayout.filenameLabel
        name.frame = BmhelperDefDialogLayout.name(in: size)
        data.frame = BmhelperDefDialogLayout.data(in: size)
        copy.frame = BmhelperDefDialogLayout.copy(in: size)
        close.frame = BmhelperDefDialogLayout.close(in: size)
    }

    func apply(filename: String, zzStrings: [String], divs: [Int], offset: Int) {
        name.stringValue = BmhelperDefinitions.resolvedName(filename)
        self.zzStrings = zzStrings
        self.divs = divs
        self.offset = offset
        refreshDefinitionText()
    }

    func controlTextDidChange(_ obj: Notification) {
        refreshDefinitionText()
    }

    @objc private func closeDialog() {
        window?.orderOut(self)
    }

    private func refreshDefinitionText() {
        data.string = BmhelperDefinitions.formatDefinitionBlock(
            name: name.stringValue,
            offset: offset,
            zzStrings: zzStrings,
            divs: divs
        )
    }

    @objc private func copyDefinitionsToClipboard() {
        let text = data.string
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
