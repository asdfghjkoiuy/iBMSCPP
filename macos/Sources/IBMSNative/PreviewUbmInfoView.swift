import AppKit

/// 盖在右侧 BGA 上的青色信息。文字图来自皮肤点阵，放大用最近邻，相同字符串不重复栅格化。
@MainActor
final class PreviewUbmInfoView: NSView {
    private(set) var text = ""
    private(set) var pixelScale: CGFloat = 1
    private(set) var rasterCount = 0
    /// 缓存已换、还没有画上窗口。隐藏期间保持为真，避免 `displayIfNeeded` 带动舞台。
    private(set) var needsPresentation = false
    private var cachedImage: CGImage?
    /// 隐藏时先记下文字，真正要画或读取图像时再栅格化。
    private var rasterPending = false
    private var cachedNSImage: NSImage?
    private var cachedNSImageSource: CGImage?
    private var cachedNSImagePixelSize = NSSize.zero

    /// 原版点阵一格 8×12。这是图本身的像素，窗口放大只乘一次。
    static let cellAdvance: CGFloat = 8
    static let cellHeight: CGFloat = 12

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    /// 只在文字变化时向皮肤要一次图。倍率只影响绘制，不重新栅格化。
    /// 图立刻画进当前视图。显示器回调不再等下一次空闲的显示周期。
    func setText(_ text: String) {
        guard rememberText(text) else { return }
        presentStoredImage()
    }

    /// 换成新的内部文字和图，不标脏、不画。隐藏时钟走这里。
    /// 视图本身隐藏时只留下字符串，避免每条时钟都做字形栅格化。
    @discardableResult
    func rememberText(_ text: String) -> Bool {
        guard text != self.text else { return false }
        self.text = text
        rasterCount += 1
        needsPresentation = true
        cachedNSImage = nil
        cachedNSImageSource = nil
        if isHidden {
            rasterPending = true
            cachedImage = nil
            return true
        }
        rasterPending = false
        cachedImage = PreviewUbmStyle.textImage(text)
        return true
    }

    /// 把已经缓存的图画出来。文字没变时也可以补上隐藏期间欠的那一次。
    func presentStoredImage() {
        ensureRasterized()
        needsPresentation = false
        publishImage()
    }

    /// `draw` 正在用的那张图。视图不建自己的图层。
    /// 隐藏期间推迟的栅格化在这里补上，测试读到的是当前文字。
    var presentedImage: CGImage? {
        ensureRasterized()
        return cachedImage
    }

    func setMagnification(_ scale: CGFloat) {
        let next = max(CGFloat(1), scale.isFinite ? scale.rounded(.down) : 1)
        guard next != pixelScale else { return }
        pixelScale = next
        needsDisplay = true
    }

    /// 点阵原尺寸。舞台倍率由窗口在摆框时乘一次，这里不再乘。
    func layoutSize() -> CGSize {
        guard !text.isEmpty else { return .zero }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let columns = lines.map(\.count).max() ?? 0
        return CGSize(
            width: CGFloat(columns) * Self.cellAdvance,
            height: CGFloat(lines.count) * Self.cellHeight
        )
    }

    var sourceImage: CGImage? {
        ensureRasterized()
        return cachedImage
    }

    func preferredSize() -> CGSize {
        layoutSize()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        ensureRasterized()
        guard let cachedImage else { return }
        let pixelSize = NSSize(width: cachedImage.width, height: cachedImage.height)
        if cachedNSImage == nil || cachedNSImageSource !== cachedImage || cachedNSImagePixelSize != pixelSize {
            cachedNSImage = NSImage(cgImage: cachedImage, size: pixelSize)
            cachedNSImageSource = cachedImage
            cachedNSImagePixelSize = pixelSize
        }
        cachedNSImage?.draw(
            in: bounds,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSNumber(value: NSImageInterpolation.none.rawValue)]
        )
    }

    /// 同一条文字只向皮肤要一次图。隐藏时记下的字符串在显示、绘制或读取图像时落地。
    private func ensureRasterized() {
        guard rasterPending else { return }
        rasterPending = false
        cachedImage = PreviewUbmStyle.textImage(text)
        cachedNSImage = nil
        cachedNSImageSource = nil
    }

    /// 最近邻由 `draw` 完成。不建图层，也不在这里重读 `font.png`。
    private func publishImage() {
        needsDisplay = true
        guard bounds.width > 1, bounds.height > 1, window != nil else { return }
        if let superview {
            let rect = convert(bounds, to: superview)
            superview.setNeedsDisplay(rect)
        }
        displayIfNeeded()
    }

    private func configure() {
        wantsLayer = false
        identifier = NSUserInterfaceItemIdentifier("PreviewUbmInfo")
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityIdentifier("PreviewUbmInfo")
    }
}
