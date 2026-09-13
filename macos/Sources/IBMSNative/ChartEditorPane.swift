import AppKit

/// 对照 `PMainL` / `PMain` / `PMainR`：一块谱面加一对滚动条。
@MainActor
final class ChartEditorPane: NSView {
    let index: Int
    let surface = ChartSurfaceView()
    let footer = BmsonSequenceFooterView()
    let verticalScroll = NSScroller()
    let horizontalScroll = NSScroller()
    var onScrollChange: ((ChartEditorPane) -> Void)?
    var onBecomeActive: ((Int) -> Void)?

    private var sideWidthConstraint: NSLayoutConstraint?
    private var footerHeightConstraint: NSLayoutConstraint!

    init(index: Int, fillsWidth: Bool) {
        self.index = index
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        clipsToBounds = true
        surface.translatesAutoresizingMaskIntoConstraints = false
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.isHidden = true
        verticalScroll.translatesAutoresizingMaskIntoConstraints = false
        verticalScroll.controlSize = .regular
        verticalScroll.scrollerStyle = .legacy
        verticalScroll.tag = index
        verticalScroll.target = self
        verticalScroll.action = #selector(verticalScrolled(_:))
        horizontalScroll.translatesAutoresizingMaskIntoConstraints = false
        horizontalScroll.controlSize = .small
        horizontalScroll.scrollerStyle = .legacy
        horizontalScroll.tag = index
        horizontalScroll.target = self
        horizontalScroll.action = #selector(horizontalScrolled(_:))
        [surface, footer, verticalScroll, horizontalScroll].forEach(addSubview)
        footerHeightConstraint = footer.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.trailingAnchor.constraint(equalTo: verticalScroll.leadingAnchor),
            surface.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: verticalScroll.leadingAnchor),
            footer.bottomAnchor.constraint(equalTo: horizontalScroll.topAnchor),
            footerHeightConstraint,
            verticalScroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            verticalScroll.topAnchor.constraint(equalTo: topAnchor),
            verticalScroll.bottomAnchor.constraint(equalTo: footer.topAnchor),
            verticalScroll.widthAnchor.constraint(equalToConstant: MainWindowChrome.scrollbarSize),
            horizontalScroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            horizontalScroll.trailingAnchor.constraint(equalTo: verticalScroll.leadingAnchor),
            horizontalScroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            horizontalScroll.heightAnchor.constraint(equalToConstant: MainWindowChrome.scrollbarSize)
        ])
        if !fillsWidth {
            let width = widthAnchor.constraint(equalToConstant: CGFloat(LegacyPanelScroll.defaultSideWidth))
            width.isActive = true
            sideWidthConstraint = width
        }
        surface.contentSizeDidChange = { [weak self] contentSize, offset in
            guard let self else { return }
            self.footer.contentOffsetX = offset.x
            self.updateScrollers(contentSize: contentSize, offset: offset)
            self.onScrollChange?(self)
        }
        surface.onBecomeActive = { [weak self] in
            guard let self else { return }
            self.onBecomeActive?(self.index)
        }
    }

    func setFooterHeight(_ height: CGFloat, visible: Bool) {
        let clamped = visible ? CGFloat(BmsONEFooter.clampHeight(Int(height.rounded()))) : 0
        footer.isHidden = !visible || clamped <= 0
        footerHeightConstraint.constant = clamped
        footer.footerHeight = clamped
    }

    required init?(coder: NSCoder) { nil }

    var sideWidth: CGFloat {
        get { sideWidthConstraint?.constant ?? bounds.width }
        set { sideWidthConstraint?.constant = CGFloat(LegacyPanelScroll.clampWidth(Int(newValue.rounded()))) }
    }

    func updateScrollers(contentSize: CGSize, offset: CGPoint) {
        let verticalRange = max(0, contentSize.height - surface.bounds.height)
        verticalScroll.isEnabled = verticalRange > 0
        verticalScroll.knobProportion = max(0.02, min(1, surface.bounds.height / max(1, contentSize.height)))
        verticalScroll.doubleValue = verticalRange == 0 ? 0 : offset.y / verticalRange
        let horizontalRange = max(0, contentSize.width - surface.bounds.width)
        horizontalScroll.isEnabled = horizontalRange > 0
        horizontalScroll.knobProportion = max(0.02, min(1, surface.bounds.width / max(1, contentSize.width)))
        horizontalScroll.doubleValue = horizontalRange == 0 ? 0 : offset.x / horizontalRange
    }

    @objc private func verticalScrolled(_ sender: NSScroller) {
        surface.setVerticalFraction(CGFloat(sender.doubleValue))
    }

    @objc private func horizontalScrolled(_ sender: NSScroller) {
        surface.setHorizontalFraction(CGFloat(sender.doubleValue))
    }
}

/// 对照 `SpL` / `SpR`：宽 5，默认隐藏。
@MainActor
final class ChartSplitterView: NSView {
    var onResize: ((_ mouseX: Int, _ grabX: Int) -> Void)?

    private var thickness: NSLayoutConstraint!
    private var grabX = 0

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.separatorColor.cgColor
        thickness = widthAnchor.constraint(equalToConstant: 0)
        thickness.isActive = true
        isHidden = true
    }

    required init?(coder: NSCoder) { nil }

    var splitterVisible: Bool {
        get { !isHidden }
        set {
            isHidden = !newValue
            thickness.constant = newValue ? CGFloat(LegacyPanelScroll.splitterThickness) : 0
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        grabX = Int(convert(event.locationInWindow, from: nil).x.rounded())
    }

    override func mouseDragged(with event: NSEvent) {
        let mouseX = Int(convert(event.locationInWindow, from: nil).x.rounded())
        onResize?(mouseX, grabX)
    }
}

/// 对照 `SoundChannelFooter` / 演奏区底栏。贴在共用谱面底下，不另开窗。
@MainActor
final class BmsonSequenceFooterView: NSView {
    var cells: [BmsONEFooter.Cell] = [] {
        didSet { needsDisplay = true }
    }
    var currentIndex = 0 {
        didSet { needsDisplay = true }
    }
    var selectedIndices: Set<Int> = [] {
        didSet { needsDisplay = true }
    }
    var contentOffsetX: CGFloat = 0 {
        didSet { needsDisplay = true }
    }
    var footerHeight: CGFloat = 0 {
        didSet { needsDisplay = true }
    }
    var gutterWidth: CGFloat = 0 {
        didSet { needsDisplay = true }
    }
    var masterFrame = CGRect.zero {
        didSet { needsDisplay = true }
    }
    var onHit: ((BmsONEFooter.Hit) -> Void)?
    var onHeightDrag: ((Int) -> Void)?
    var onMenu: ((Int, NSPoint) -> Void)?
    var onPlayingMenu: ((NSPoint) -> Void)?

    private var draggingGrip = false
    private var dragStartHeight = 0
    private var dragStartWindowY: CGFloat = 0

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(
            srgbRed: 102 / 255,
            green: 102 / 255,
            blue: 102 / 255,
            alpha: 1
        ).cgColor
    }

    required init?(coder: NSCoder) { nil }

    override func resetCursorRects() {
        addCursorRect(
            NSRect(x: 0, y: 0, width: bounds.width, height: CGFloat(BmsONEFooter.gripWidth)),
            cursor: .resizeUpDown
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 102 / 255, green: 102 / 255, blue: 102 / 255, alpha: 1).setFill()
        bounds.fill()
        drawEntity(BmsONEFooter.entityFrame(x: 0, width: gutterWidth, height: bounds.height))
        if masterFrame.width > 0 {
            drawEntity(
                CGRect(
                    x: masterFrame.minX - contentOffsetX,
                    y: 0,
                    width: masterFrame.width,
                    height: bounds.height
                )
            )
        }
        for cell in cells {
            var frame = cell.frame
            frame.origin.x -= contentOffsetX
            switch cell.kind {
            case .channel(let index, let name):
                drawEntity(frame, current: index == currentIndex, selected: selectedIndices.contains(index))
                drawChannelName(name, in: frame)
            case .playing(let label, let imageName):
                drawEntity(frame)
                drawPlayingLabel(label, imageName: imageName, cell: frame)
            case .corner, .master:
                drawEntity(frame)
            }
        }
        NSColor.darkGray.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }

    override func mouseDown(with event: NSEvent) {
        handle(event, middle: false)
    }

    override func mouseDragged(with event: NSEvent) {
        guard draggingGrip else { return }
        let next = BmsONEFooter.heightAfterWindowDrag(
            startHeight: dragStartHeight,
            startWindowY: dragStartWindowY,
            currentWindowY: event.locationInWindow.y
        )
        onHeightDrag?(next)
    }

    override func mouseUp(with event: NSEvent) {
        draggingGrip = false
        _ = event
    }

    override func otherMouseDown(with event: NSEvent) {
        handle(event, middle: true)
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let menuPoint = NSPoint(x: event.locationInWindow.x, y: event.locationInWindow.y)
        if let index = BmsONEFooter.hitChannel(x: point.x, cells: cells, offsetX: contentOffsetX) {
            onMenu?(index, menuPoint)
        } else if BmsONEFooter.hitsPlaying(x: point.x, cells: cells, offsetX: contentOffsetX) {
            onPlayingMenu?(menuPoint)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        rightMouseDown(with: event)
        return nil
    }

    private func handle(_ event: NSEvent, middle: Bool) {
        let point = convert(event.locationInWindow, from: nil)
        let hit = BmsONEFooter.hit(
            point: point,
            cells: cells,
            offsetX: contentOffsetX,
            command: event.modifierFlags.contains(.command),
            doubleClick: event.clickCount >= 2,
            middle: middle
        )
        if hit == .grip {
            draggingGrip = true
            dragStartHeight = BmsONEFooter.clampHeight(Int(bounds.height.rounded()))
            dragStartWindowY = event.locationInWindow.y
            return
        }
        onHit?(hit)
    }

    private func drawEntity(_ frame: CGRect, current: Bool = false, selected: Bool = false) {
        guard frame.width > 0, frame.height > 0 else { return }
        let fill = current
            ? NSColor.windowBackgroundColor
            : selected
                ? NSColor.windowBackgroundColor.withAlphaComponent(0.92)
                : NSColor.windowBackgroundColor.withAlphaComponent(0.85)
        fill.setFill()
        frame.fill()
        NSColor.darkGray.setStroke()
        let path = NSBezierPath(rect: frame.insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = 1
        path.stroke()
    }

    private func drawChannelName(_ name: String, in frame: CGRect) {
        let width = max(Int(frame.width.rounded(.towardZero)), 0)
        let height = max(Int(frame.height.rounded(.towardZero)), 0)
        let mode = BmsONEFooter.textMode(internalWidth: width, height: height)
        let textRect = BmsONEFooter.textRect(internalWidth: width, height: height, mode: mode)
        let font = NSFont.systemFont(ofSize: CGFloat(BmsONEFooter.fontSize))
        let shown = BmsONEFooter.displayedName(name: name, textRect: textRect) { text in
            measure(text, font: font, wrap: mode != .verticalSingle, width: textRect.width)
        }
        guard let shown else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        let local = CGRect(
            x: frame.minX + textRect.minX,
            y: frame.minY + textRect.minY,
            width: textRect.width,
            height: textRect.height
        )
        guard let context = NSGraphicsContext.current?.cgContext else {
            (shown as NSString).draw(in: local, withAttributes: attrs)
            return
        }
        context.saveGState()
        if mode != .horizontal {
            context.translateBy(x: frame.minX, y: frame.maxY)
            context.rotate(by: -.pi / 2)
            let rotated = CGRect(x: textRect.minX, y: textRect.minY, width: textRect.width, height: textRect.height)
            (shown as NSString).draw(in: rotated, withAttributes: attrs)
        } else {
            (shown as NSString).draw(in: local, withAttributes: attrs)
        }
        context.restoreGState()
    }

    private func drawPlayingLabel(_ label: String, imageName: String, cell: CGRect) {
        let box = BmsONEFooter.playingLabelFrame(
            left: cell.minX,
            width: cell.width,
            imageName: imageName
        )
        let color: NSColor
        switch imageName {
        case "scratch":
            color = NSColor(srgbRed: 60 / 255, green: 26 / 255, blue: 26 / 255, alpha: 1)
        case "bkey":
            color = NSColor(srgbRed: 26 / 255, green: 26 / 255, blue: 60 / 255, alpha: 1)
        default:
            color = NSColor(srgbRed: 51 / 255, green: 51 / 255, blue: 51 / 255, alpha: 1)
        }
        color.setFill()
        box.fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.white,
            .paragraphStyle: centered
        ]
        (label as NSString).draw(in: box, withAttributes: attrs)
    }

    private var centered: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return style
    }

    private func measure(_ text: String, font: NSFont, wrap: Bool, width: CGFloat) -> CGSize {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        if wrap {
            return (text as NSString).boundingRect(
                with: CGSize(width: max(1, width), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs
            ).size
        }
        return (text as NSString).size(withAttributes: attrs)
    }
}
