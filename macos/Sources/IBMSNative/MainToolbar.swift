import AppKit

@MainActor
final class MainToolbarView: NSView {
    var onCommand: ((String) -> Void)?
    private var buttons: [String: ToolbarChromeButton] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        for (item, frame) in MainToolbarLayout.frames() {
            if item.kind == .separator {
                let separator = NSBox(frame: NSRect(x: frame.minX + 2, y: 4, width: 1, height: 17))
                separator.boxType = .separator
                addSubview(separator)
                continue
            }
            let button = ToolbarChromeButton(item: item)
            button.frame = frame
            button.toolTip = item.tooltip
            button.target = self
            button.action = #selector(buttonPressed(_:))
            button.identifier = NSUserInterfaceItemIdentifier(item.name)
            if item.kind == .split {
                button.menu = dropDownMenu(for: item.name)
            }
            addSubview(button)
            buttons[item.name] = button
        }
    }

    required init?(coder: NSCoder) { nil }

    func setEnabled(_ name: String, _ enabled: Bool) {
        buttons[name]?.isEnabled = enabled
    }

    func setChecked(_ name: String, _ checked: Bool) {
        buttons[name]?.checked = checked
    }

    func setIcon(_ name: String, icon: String) {
        buttons[name]?.iconOverride = icon
    }

    func isChecked(_ name: String) -> Bool {
        buttons[name]?.checked == true
    }

    func setStatisticsTitle(_ title: String) {
        buttons["TBStatistics"]?.statisticsTitle = title
    }

    func setThemeMenu(_ menu: NSMenu) {
        buttons["TBTheme"]?.menu = menu
    }

    func setLanguageMenu(_ menu: NSMenu) {
        buttons["TBLanguage"]?.menu = menu
    }

    func refreshConversionMenu() {
        guard let menu = buttons["POConvert"]?.menu else { return }
        menu.autoenablesItems = false
        let ntInput = isChecked("TBNTInput")
        for item in menu.items {
            guard let command = item.representedObject as? String else { continue }
            item.isEnabled = LegacyChromeMenu.conversionEnabled(command: command, ntInput: ntInput)
        }
    }

    func setRecentSlots(_ slots: [String], noneWord: String = LegacyRecent.noneWord) {
        guard let menu = buttons["TBOpen"]?.menu else { return }
        menu.autoenablesItems = false
        for index in 0..<LegacyRecent.slotCount {
            guard menu.items.indices.contains(index) else { continue }
            let path = slots.indices.contains(index) ? slots[index] : ""
            let item = menu.items[index]
            item.title = LegacyRecent.menuTitle(path, noneWord: noneWord)
            item.toolTip = LegacyRecent.tooltip(path)
            item.isEnabled = LegacyRecent.isEnabled(path)
            item.tag = index
            item.representedObject = "TBOpenR\(index)"
        }
    }

    @objc private func buttonPressed(_ sender: ToolbarChromeButton) {
        guard let name = sender.identifier?.rawValue else { return }
        onCommand?(name)
    }

    private func dropDownMenu(for name: String) -> NSMenu {
        let menu = NSMenu()
        switch name {
        case "TBOpen":
            menu.autoenablesItems = false
            for index in 0..<LegacyRecent.slotCount {
                addCommand(menu, title: LegacyRecent.emptyTitle, command: "TBOpenR\(index)", enabled: false)
            }
            menu.addItem(.separator())
            addCommand(menu, title: "Import from .SM file", command: "TBImportSM")
            addCommand(menu, title: "Import from .IBMSC file", command: "TBImportIBMSC")
        case "TBSave":
            addCommand(menu, title: "Save As...", command: "TBSaveAs")
            addCommand(menu, title: "Export .IBMSC file", command: "TBExport")
        case "POConvert":
            menu.autoenablesItems = false
            let ntInput = isChecked("TBNTInput")
            for entry in LegacyChromeMenu.conversions {
                switch entry {
                case .separator:
                    menu.addItem(.separator())
                case .item(let title, let command, _, _, _):
                    addCommand(
                        menu,
                        title: title,
                        command: command,
                        enabled: LegacyChromeMenu.conversionEnabled(command: command, ntInput: ntInput)
                    )
                case .submenu:
                    break
                }
            }
        case "TBLanguage":
            addCommand(menu, title: "(Default)", command: "TBLangDef")
            addCommand(menu, title: "Refresh", command: "TBLangRefresh")
        default:
            break
        }
        return menu
    }

    private func addCommand(_ menu: NSMenu, title: String, command: String, enabled: Bool = true) {
        let item = menu.addItem(withTitle: title, action: #selector(menuCommand(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = command
        item.isEnabled = enabled
    }

    @objc private func menuCommand(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? String else { return }
        onCommand?(command)
    }
}

@MainActor
private final class ToolbarChromeButton: NSControl {
    let item: MainToolbarItem
    var checked = false { didSet { needsDisplay = true } }
    var statisticsTitle = "0" { didSet { needsDisplay = true } }
    var iconOverride: String? { didSet { needsDisplay = true } }
    private var pressed = false { didSet { needsDisplay = true } }

    init(item: MainToolbarItem) {
        self.item = item
        self.checked = item.checked
        super.init(frame: .zero)
        isEnabled = true
        focusRingType = .none
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        NSSize(width: item.width, height: item.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds
        if checked || pressed {
            NSColor.selectedContentBackgroundColor.withAlphaComponent(checked ? 0.28 : 0.16).setFill()
            bounds.fill()
        }
        let image = LegacyChromeIcons.image(named: iconOverride ?? item.icon ?? "")
        let imageRect = NSRect(x: item.kind == .statistics ? 2 : floor((item.kind == .split ? 20 : bounds.width) / 2 - 8),
                               y: floor((bounds.height - 16) / 2),
                               width: 16,
                               height: 16)
        image?.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: isEnabled ? 1 : 0.4)
        if item.kind == .statistics {
            let title = statisticsTitle as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: LegacyChromeFont.segoeBold,
                .foregroundColor: NSColor.labelColor
            ]
            let size = title.size(withAttributes: attrs)
            title.draw(at: NSPoint(x: 18, y: floor((bounds.height - size.height) / 2)), withAttributes: attrs)
        }
        if item.kind == .split {
            let chevron = NSBezierPath()
            let cx = bounds.maxX - 7
            let cy = bounds.midY
            chevron.move(to: NSPoint(x: cx - 3, y: cy + 1.5))
            chevron.line(to: NSPoint(x: cx + 3, y: cy + 1.5))
            chevron.line(to: NSPoint(x: cx, y: cy - 2))
            chevron.close()
            NSColor.secondaryLabelColor.setFill()
            chevron.fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        pressed = true
        let split = item.kind == .split
        if split, let dropDown = menu {
            let local = convert(event.locationInWindow, from: nil)
            if local.x >= bounds.maxX - 12 {
                pressed = false
                dropDown.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.minY), in: self)
                return
            }
        }
        var keep = true
        while keep {
            guard let next = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) else { break }
            let inside = bounds.contains(convert(next.locationInWindow, from: nil))
            pressed = inside
            if next.type == .leftMouseUp {
                keep = false
                pressed = false
                if inside {
                    sendAction(action, to: target)
                    if split, event.modifierFlags.contains(.option), let dropDown = menu {
                        dropDown.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.minY), in: self)
                    }
                }
            }
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        menu?.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.minY), in: self)
    }
}
