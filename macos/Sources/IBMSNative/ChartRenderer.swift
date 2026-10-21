import AppKit
import MetalKit

private struct ChartVertex {
    var position: SIMD2<Float>
    var color: SIMD4<Float>
}

struct LegacyGradientPrimitive {
    let fill: CGRect
    let start: CGPoint
    let end: CGPoint
    let colors: ThemeGradientColors
}

/// Both presentation subviews are deliberately non-interactive. The surface
/// owns selection and editing, so AppKit must route pointer events back to it.
private final class PassiveMetalView: MTKView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class ChartRenderer: NSObject, MTKViewDelegate {
    private let commandQueue: MTLCommandQueue?
    private let pipeline: MTLRenderPipelineState?
    private var vertices: [ChartVertex] = []
    private var vertexBuffer: MTLBuffer?
    private var vertexCount = 0

    var isAvailable: Bool { pipeline != nil && commandQueue != nil }

    init(device: MTLDevice) {
        commandQueue = device.makeCommandQueue()
        pipeline = Self.makePipeline(device: device)
        super.init()
    }

    func replaceGeometry(_ quads: [(CGRect, NSColor)], viewport: CGSize, device: MTLDevice) {
        guard viewport.width > 0, viewport.height > 0 else {
            clearVertices()
            return
        }

        vertices.removeAll(keepingCapacity: true)
        vertices.reserveCapacity(quads.count * 6)
        for (rect, color) in quads {
            Self.appendQuad(into: &vertices, rect: rect, color: color, viewport: viewport)
        }
        storeVertices(device: device)
    }

    func replaceGeometry(
        _ quads: [(CGRect, NSColor)],
        gradients: [LegacyGradientPrimitive],
        overlays: [(CGRect, NSColor)],
        viewport: CGSize,
        device: MTLDevice
    ) {
        guard viewport.width > 0, viewport.height > 0 else {
            clearVertices()
            return
        }
        vertices.removeAll(keepingCapacity: true)
        vertices.reserveCapacity((quads.count + gradients.count + overlays.count) * 6)
        for (rect, color) in quads {
            Self.appendQuad(into: &vertices, rect: rect, color: color, viewport: viewport)
        }
        for primitive in gradients {
            Self.appendGradient(primitive, into: &vertices, viewport: viewport)
        }
        for (rect, color) in overlays {
            Self.appendQuad(into: &vertices, rect: rect, color: color, viewport: viewport)
        }
        storeVertices(device: device)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let renderPass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else {
            return
        }

        if let pipeline, let vertexBuffer, vertexCount > 0 {
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
        }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func clearVertices() {
        vertices.removeAll(keepingCapacity: true)
        vertexCount = 0
    }

    /// 容量够就原地拷贝。不够时按 1.5 倍扩，仍不够再按 2 倍，避免每帧 `makeBuffer`。
    private func storeVertices(device: MTLDevice) {
        vertexCount = vertices.count
        let byteCount = vertexCount * MemoryLayout<ChartVertex>.stride
        guard byteCount > 0 else { return }
        if let vertexBuffer, vertexBuffer.length >= byteCount {
            vertices.withUnsafeBytes { raw in
                guard let baseAddress = raw.baseAddress else { return }
                vertexBuffer.contents().copyMemory(from: baseAddress, byteCount: byteCount)
            }
            return
        }
        let previous = vertexBuffer?.length ?? 0
        var capacity = byteCount
        if previous > 0 {
            let grown = previous + previous / 2
            capacity = grown >= byteCount ? grown : max(byteCount, previous * 2)
        }
        guard let buffer = device.makeBuffer(length: capacity, options: .storageModeShared) else {
            vertexBuffer = nil
            vertexCount = 0
            return
        }
        vertices.withUnsafeBytes { raw in
            guard let baseAddress = raw.baseAddress else { return }
            buffer.contents().copyMemory(from: baseAddress, byteCount: byteCount)
        }
        vertexBuffer = buffer
    }

    private static func appendQuad(
        into vertices: inout [ChartVertex],
        rect: CGRect,
        color: NSColor,
        viewport: CGSize
    ) {
        let rgba = colorVector(color)
        appendQuad(
            into: &vertices,
            rect: rect,
            topLeft: rgba,
            topRight: rgba,
            bottomRight: rgba,
            bottomLeft: rgba,
            viewport: viewport
        )
    }

    private static func appendGradient(
        _ primitive: LegacyGradientPrimitive,
        into vertices: inout [ChartVertex],
        viewport: CGSize
    ) {
        func color(at point: CGPoint) -> SIMD4<Float> {
            colorVector(
                LegacyChartPaint.interpolate(
                    primitive.colors,
                    weight: LegacyChartPaint.gradientWeight(at: point, from: primitive.start, to: primitive.end)
                )
            )
        }
        appendQuad(
            into: &vertices,
            rect: primitive.fill,
            topLeft: color(at: CGPoint(x: primitive.fill.minX, y: primitive.fill.minY)),
            topRight: color(at: CGPoint(x: primitive.fill.maxX, y: primitive.fill.minY)),
            bottomRight: color(at: CGPoint(x: primitive.fill.maxX, y: primitive.fill.maxY)),
            bottomLeft: color(at: CGPoint(x: primitive.fill.minX, y: primitive.fill.maxY)),
            viewport: viewport
        )
    }

    private static func colorVector(_ color: NSColor) -> SIMD4<Float> {
        let rgba = color.usingColorSpace(.deviceRGB) ?? color
        return SIMD4(
            Float(rgba.redComponent),
            Float(rgba.greenComponent),
            Float(rgba.blueComponent),
            Float(rgba.alphaComponent)
        )
    }

    private static func appendQuad(
        into vertices: inout [ChartVertex],
        rect: CGRect,
        topLeft: SIMD4<Float>,
        topRight: SIMD4<Float>,
        bottomRight: SIMD4<Float>,
        bottomLeft: SIMD4<Float>,
        viewport: CGSize
    ) {
        let left = Float(rect.minX / viewport.width * 2 - 1)
        let right = Float(rect.maxX / viewport.width * 2 - 1)
        let topPosition = Float(1 - rect.minY / viewport.height * 2)
        let bottomPosition = Float(1 - rect.maxY / viewport.height * 2)
        let topLeftVertex = ChartVertex(position: SIMD2(left, topPosition), color: topLeft)
        let topRightVertex = ChartVertex(position: SIMD2(right, topPosition), color: topRight)
        let bottomRightVertex = ChartVertex(position: SIMD2(right, bottomPosition), color: bottomRight)
        let bottomLeftVertex = ChartVertex(position: SIMD2(left, bottomPosition), color: bottomLeft)
        vertices.append(topLeftVertex)
        vertices.append(topRightVertex)
        vertices.append(bottomRightVertex)
        vertices.append(topLeftVertex)
        vertices.append(bottomRightVertex)
        vertices.append(bottomLeftVertex)
    }

    private static func makePipeline(device: MTLDevice) -> MTLRenderPipelineState? {
        let source = """
        #include <metal_stdlib>
        using namespace metal;

        struct Vertex { float2 position; float4 color; };
        struct Output { float4 position [[position]]; float4 color; };

        vertex Output chartVertex(uint index [[vertex_id]], constant Vertex *vertices [[buffer(0)]]) {
            Output output;
            output.position = float4(vertices[index].position, 0.0, 1.0);
            output.color = vertices[index].color;
            return output;
        }

        fragment float4 chartFragment(Output input [[stage_in]]) {
            return input.color;
        }
        """
        do {
            let library = try device.makeLibrary(source: source, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "chartVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "chartFragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            return nil
        }
    }
}

struct ChartPresentedNote: Equatable {
    var ghost: Bool
    var longNote: Bool
    var channel: String
    var beat: Double
    var endBeat: Double
    var token: String
    var contentRect: CGRect
}

fileprivate struct PresentedPaint {
    var ghost: Bool
    var selected: Bool
    var colors: ThemeGradientColors
    var shortNote: ChartNoteRect?
    var longNote: ChartLongNoteRect?
}

@MainActor
private final class ChartLabelOverlay: NSView {
    weak var surface: ChartSurfaceView?
    private var cachedFonts: [FontCacheKey: NSFont] = [:]

    private struct FontCacheKey: Hashable {
        var name: String
        var size: CGFloat
        var bold: Bool
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let surface else { return }
        surface.rubberBandWasStroked = false
        let layout = surface.chartLayout
        let viewport = surface.viewport

        if !surface.hasMetalRenderer {
            layout.theme.visual.background.nsColor.setFill()
            bounds.fill()
            drawFallbackGeometry(layout: layout, viewport: viewport)
        }
        if layout.showColumnCaption {
            drawLaneLabels(layout: layout, viewport: viewport)
        }
        if layout.showMeasureNumber {
            drawMeasureLabels(layout: layout, viewport: viewport)
        }
        drawNoteLabels(layout: layout, viewport: viewport)
        drawErrorIcons(layout: layout, viewport: viewport)
        drawTimeSelectionLabels(layout: layout, viewport: viewport)
        drawDragPreview()
        if !surface.hasMetalRenderer {
            surface.drawMiniMapFallback()
        }
        // 覆盖层随鼠标更新，不触发 Metal 静态几何重建。
        drawOverlayGuides(layout: layout, viewport: viewport)
    }

    private func drawFallbackGeometry(layout: ChartLayout, viewport: CGRect) {
        for lane in layout.lanes where !lane.channel.isEmpty {
            guard let frame = layout.laneFrames[lane.channel] else { continue }
            if layout.fillsColumnBackground(lane) {
                let background = surface?.highlightsLane(lane.channel) == true
                    ? highlight(lane.backgroundColor)
                    : lane.backgroundColor
                background.setFill()
                LegacyChartPaint.columnBackground(laneLeft: frame.minX - viewport.minX, laneWidth: frame.width, height: bounds.height).fill()
            }
            if layout.showVerticalLine {
                layout.theme.visual.verticalLine.nsColor.setFill()
                CGRect(x: LegacyChartPaint.columnVerticalLineX(laneLeft: frame.minX - viewport.minX), y: 0, width: 1, height: bounds.height).fill()
            }
        }
        let gridX = max(0, layout.gridLeadingX - viewport.minX)
        for line in layout.gridLines(in: viewport) {
            color(for: line, theme: layout.theme).setFill()
            CGRect(x: gridX, y: line.y - viewport.minY, width: max(0, bounds.width - gridX), height: line.kind == .measure ? 1 : 0.5).fill()
        }
        if let surface {
            surface.drawMasterLaneFallback()
            surface.drawSoundLaneWaveformFallback()
        }
        if let surface {
            layout.theme.visual.bgmWaveform.nsColor.setFill()
            for rect in surface.waveformPixelRects() {
                rect.fill()
            }
        }
        if let fill = surface?.timeSelectionFill() {
            layout.theme.visual.timeSelectionSelection.nsColor.setFill()
            fill.offsetBy(dx: -viewport.minX, dy: -viewport.minY).fill()
        }
        if let surface {
            for item in surface.currentPresentedPaint() {
                if let note = item.shortNote {
                    drawLegacyGradient(note, colors: item.colors, viewport: viewport)
                    drawNoteOutline(note.rect.offsetBy(dx: -viewport.minX, dy: -viewport.minY), color: item.colors.bright.nsColor)
                    if item.selected {
                        drawSelectionOutline(note.selection.offsetBy(dx: -viewport.minX, dy: -viewport.minY), layout: layout)
                    }
                } else if let longNote = item.longNote {
                    drawLegacyGradient(longNote, colors: item.colors, viewport: viewport)
                    drawNoteOutline(longNote.outline.offsetBy(dx: -viewport.minX, dy: -viewport.minY), color: item.colors.bright.nsColor)
                    if item.selected {
                        drawSelectionOutline(longNote.selection.offsetBy(dx: -viewport.minX, dy: -viewport.minY), layout: layout)
                    }
                }
            }
        }
    }

    private func drawOverlayGuides(layout: ChartLayout, viewport: CGRect) {
        guard let surface else { return }
        if let lines = surface.timeSelectionLineYs() {
            layout.theme.visual.timeSelectionCursor.nsColor.setFill()
            CGRect(x: 0, y: lines.end - viewport.minY, width: bounds.width, height: 1).fill()
            layout.theme.visual.timeSelectionHalf.nsColor.setFill()
            CGRect(x: 0, y: lines.half - viewport.minY, width: bounds.width, height: 1).fill()
            layout.theme.visual.timeSelectionCursor.nsColor.setFill()
            CGRect(x: 0, y: lines.start - viewport.minY, width: bounds.width, height: 1).fill()
        }
        if let hover = surface.timeSelectionHoverRect() {
            layout.theme.visual.timeSelectionMouseOver.nsColor.setStroke()
            let path = NSBezierPath(rect: hover.offsetBy(dx: -viewport.minX, dy: -viewport.minY))
            path.lineWidth = 1
            path.stroke()
        }
        if let band = surface.bmsonRubberBandFrame() {
            surface.rubberBandWasStroked = true
            layout.theme.visual.selectionBox.nsColor.setStroke()
            let path = NSBezierPath(rect: band.offsetBy(dx: -viewport.minX, dy: -viewport.minY))
            path.lineWidth = 1
            path.stroke()
        }
        let color = surface.hoverUsesEndPen
            ? layout.theme.visual.noteMouseOverEnd.nsColor
            : layout.theme.visual.noteMouseOver.nsColor
        for outline in surface.noteHoverOutlines() {
            color.setStroke()
            let path = NSBezierPath(rect: outline.offsetBy(dx: -viewport.minX, dy: -viewport.minY))
            path.lineWidth = 1
            path.stroke()
        }
        if let mouseY = surface.mouseGuideY {
            NSColor.white.setFill()
            CGRect(x: 0, y: mouseY - viewport.minY, width: bounds.width, height: 1).fill()
        }
    }

    private func drawErrorIcons(layout: ChartLayout, viewport: CGRect) {
        guard let surface, surface.errorCheckEnabled, !surface.errorAnchors.isEmpty else { return }
        guard let image = LegacyChromeIcons.image(named: LegacyErrorCheck.imageName) else { return }
        let noteHeight = CGFloat(layout.theme.visual.noteHeight)
        for anchor in surface.errorAnchors {
            let channel = layout.displayChannel(for: anchor.channel)
            guard let lane = layout.laneFrames[channel] else { continue }
            let rect = LegacyErrorCheck.iconRect(
                laneLeft: lane.minX - viewport.minX,
                laneWidth: lane.width,
                anchorY: layout.y(forBeat: anchor.beat) - viewport.minY,
                noteHeight: noteHeight
            )
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        }
    }

    private func drawTimeSelectionLabels(layout: ChartLayout, viewport: CGRect) {
        guard let surface, surface.tool == .timeSelect else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font(layout.theme.visual.timeSelectionBPMFont),
            .foregroundColor: layout.theme.visual.timeSelectionBPM.nsColor
        ]
        let fontHeight = CGFloat(layout.theme.visual.timeSelectionBPMFont.logicalPixelSize)
        for item in surface.timeSelectionBPMLabels() {
            let point = CGPoint(x: 2, y: item.y - viewport.minY - fontHeight + 3)
            item.text.draw(at: point, withAttributes: attributes)
        }
    }

    private func drawDragPreview() {
        guard let surface, !surface.dragPreviewPaths.isEmpty else { return }
        let joined = LegacyWavList.dragPreviewText(surface.dragPreviewPaths)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let alpha = CGFloat((LegacyWavList.dragPreviewARGB >> 24) & 0xFF) / 255
        let attributes: [NSAttributedString.Key: Any] = [
            .font: LegacyChromeFont.segoe,
            .foregroundColor: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha),
            .paragraphStyle: style
        ]
        let text = joined as NSString
        let size = text.size(withAttributes: attributes)
        let rect = CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: ceil(size.width),
            height: ceil(size.height)
        )
        text.draw(in: rect, withAttributes: attributes)
    }

    private func color(for line: ChartGridLine, theme: ChartTheme) -> NSColor {
        switch line.kind {
        case .measure: return theme.visual.measureLine.nsColor
        case .grid: return theme.visual.grid.nsColor
        case .sub: return theme.visual.subGrid.nsColor
        }
    }

    private func highlight(_ color: NSColor) -> NSColor {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        func clamp(_ value: CGFloat) -> CGFloat { min(1, max(0, value * 2)) }
        return NSColor(
            calibratedRed: clamp(rgb.redComponent),
            green: clamp(rgb.greenComponent),
            blue: clamp(rgb.blueComponent),
            alpha: clamp(rgb.alphaComponent)
        )
    }

    private func drawLaneLabels(layout: ChartLayout, viewport: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font(layout.theme.visual.columnTitleFont),
            .foregroundColor: layout.theme.visual.columnTitle.nsColor
        ]
        for lane in layout.lanes where !lane.channel.isEmpty {
            guard let frame = layout.laneFrames[lane.channel] else { continue }
            let origin = LegacyChartPaint.columnTitleOrigin(laneLeft: frame.minX - viewport.minX)
            lane.title.draw(at: origin, withAttributes: attributes)
        }
    }

    private func drawMeasureLabels(layout: ChartLayout, viewport: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font(layout.theme.visual.measureFont),
            .foregroundColor: layout.measureLabelColor
        ]
        let fontHeight = (attributes[.font] as? NSFont)?.pointSize ?? 9
        let visible = layout.visibleMeasures(in: viewport, viewHeight: bounds.height, labelPadding: fontHeight + 16)
        for measure in visible {
            let y = layout.y(forBeat: measure.start) - viewport.minY - fontHeight
            guard y > -16 && y < bounds.maxY else { continue }
            layout.measureCaption(for: measure).draw(at: CGPoint(x: -viewport.minX, y: y), withAttributes: attributes)
        }
    }

    private func drawNoteLabels(layout: ChartLayout, viewport: CGRect) {
        guard let surface else { return }
        for item in surface.currentPresentedPaint() {
            if let note = item.shortNote {
                let lane = lane(for: note.event, layout: layout)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font(layout.theme.visual.noteFont),
                    .foregroundColor: lane?.textColor ?? NSColor.black
                ]
                surface.noteCaption(token: note.event.token, channel: note.event.channel).draw(
                    at: CGPoint(x: note.labelOrigin.x - viewport.minX, y: note.labelOrigin.y - viewport.minY),
                    withAttributes: attributes
                )
            } else if let longNote = item.longNote {
                let lane = lane(for: longNote.note, layout: layout)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font(layout.theme.visual.noteFont),
                    .foregroundColor: lane?.longTextColor ?? NSColor.black
                ]
                surface.noteCaption(token: longNote.note.start.token, channel: longNote.note.channel).draw(
                    at: CGPoint(x: longNote.labelOrigin.x - viewport.minX, y: longNote.labelOrigin.y - viewport.minY),
                    withAttributes: attributes
                )
            }
        }
    }

    private func lane(for event: ChartEventSnapshot, layout: ChartLayout) -> ChartLane? {
        layout.lanes.first { $0.channel == layout.displayChannel(for: event.channel) }
    }

    private func lane(for note: LongNoteSnapshot, layout: ChartLayout) -> ChartLane? {
        layout.lanes.first { $0.channel == layout.displayChannel(for: note.channel) }
    }

    private func drawLegacyGradient(_ note: ChartNoteRect, colors: ThemeGradientColors, viewport: CGRect) {
        drawLegacyGradient(
            fill: note.fill.offsetBy(dx: -viewport.minX, dy: -viewport.minY),
            start: CGPoint(x: note.gradientStart.x - viewport.minX, y: note.gradientStart.y - viewport.minY),
            end: CGPoint(x: note.gradientEnd.x - viewport.minX, y: note.gradientEnd.y - viewport.minY),
            colors: colors
        )
    }

    private func drawLegacyGradient(_ note: ChartLongNoteRect, colors: ThemeGradientColors, viewport: CGRect) {
        drawLegacyGradient(
            fill: note.fill.offsetBy(dx: -viewport.minX, dy: -viewport.minY),
            start: CGPoint(x: note.gradientStart.x - viewport.minX, y: note.gradientStart.y - viewport.minY),
            end: CGPoint(x: note.gradientEnd.x - viewport.minX, y: note.gradientEnd.y - viewport.minY),
            colors: colors
        )
    }

    private func drawLegacyGradient(fill: CGRect, start: CGPoint, end: CGPoint, colors: ThemeGradientColors) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.clip(to: fill)
        NSGradient(starting: colors.bright.nsColor, ending: colors.dark.nsColor)?
            .draw(from: start, to: end, options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation])
        context.restoreGState()
    }

    private func drawNoteOutline(_ rect: CGRect, color: NSColor) {
        color.setStroke()
        let path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = 1
        path.stroke()
    }

    private func drawSelectionOutline(_ rect: CGRect, layout: ChartLayout) {
        layout.theme.visual.noteSelected.nsColor.setStroke()
        let path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = 1
        path.stroke()
    }

    private func font(_ themeFont: ThemeFont) -> NSFont {
        let size = CGFloat(themeFont.logicalPixelSize)
        let bold = themeFont.style & 1 != 0
        let key = FontCacheKey(name: themeFont.name, size: size, bold: bold)
        if let cached = cachedFonts[key] { return cached }
        let base = NSFont(name: themeFont.name, size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        let resolved: NSFont
        if bold {
            let descriptor = base.fontDescriptor.withSymbolicTraits(base.fontDescriptor.symbolicTraits.union(.bold))
            resolved = NSFont(descriptor: descriptor, size: size) ?? base
        } else {
            resolved = base
        }
        cachedFonts[key] = resolved
        return resolved
    }

    func drawFallbackForProbe() {
        guard let surface else { return }
        drawFallbackGeometry(layout: surface.chartLayout, viewport: surface.viewport)
    }
}

@MainActor
final class ChartSurfaceView: NSView {
    private let metalView: PassiveMetalView
    private let renderer: ChartRenderer?
    private let labels = ChartLabelOverlay()
    private var offset = CGPoint.zero
    var scrollOffset: CGPoint { offset }
    var onBecomeActive: (() -> Void)?
    private var snapshot = ChartSnapshot.empty
    private var longNotes = LongNoteSnapshotSet.empty
    var currentLongNotes: LongNoteSnapshotSet { longNotes }
    private var theme = ChartTheme.defaultTheme
    private var side: ChartSide = .onePlayer
    private var pixelsPerQuarterBeat: CGFloat = 48
    private var division = 16
    private var subDivision = 4
    private var showGrid = true
    private var showSubGrid = true
    private var showMeasureBar = true
    private var showBackground = true
    private var showMeasureNumber = true
    private var showVerticalLine = true
    private var showColumnCaption = true
    var snapEnabled = true
    var disableVerticalMove = false
    var timeSelection = TimeSelection.legacyDefault {
        didSet { rebuildGeometry() }
    }
    var errorCheckEnabled = true {
        didSet { rebuildGeometry() }
    }
    var errorAnchors: [ErrorAnchor] = [] {
        didSet { rebuildGeometry() }
    }
    var hoverDidChange: (() -> Void)?
    var hoverLaneChannel: String?
    var hoverUsesEndPen = false
    var mouseGuideY: CGFloat?
    /// 普通底栏用的鼠标 / 悬停快照。时间选择不读这些。
    private(set) var statusMouseVPosition: Double = 0
    private(set) var statusColumnTitle = ""
    private(set) var statusHasColumn = false
    private(set) var statusPointerInside = false
    private(set) var statusHoverVPosition: Double = 0
    private(set) var statusHoverColumnTitle = ""
    private(set) var statusHoverValue: Double = 0
    private(set) var statusHoverLength: Double = 0
    private(set) var statusHoverHidden = false
    private(set) var statusHoverNumeric = false
    private(set) var statusHoverLongNote = false
    private(set) var statusWriteLength: Double = 0
    var statusHoverHasError: Bool { hoverHasError }
    /// BMSON 预览播放头。有值时白线跟延迟后的拍走，不跟鼠标。
    private var previewPlayheadBeat: Double?
    var headerBPM = 120.0
    var bpmEvents: [(vPosition: Double, value: Double)] = []
    var stopEvents: [(vPosition: Double, value: Double)] = []
    private var waveform: LegacyWaveform.Buffer?
    private var waveformLocked = true
    private var waveformPosition = LegacyWaveform.defaultPosition
    private var waveformLeft = LegacyWaveform.defaultLeft
    private var waveformWidth = LegacyWaveform.defaultWidth
    private var waveformPrecision = LegacyWaveform.defaultPrecision
    var timeSelectionDidChange: ((TimeSelection) -> Void)?
    var toggleSnapRequested: (() -> Void)?
    var toggleDisableVerticalMoveRequested: (() -> Void)?
    var applySlashDivisionRequested: (() -> Void)?
    var doubleDivisionRequested: (() -> Void)?
    var halfDivisionRequested: (() -> Void)?
    var moveDigitRequested: ((Int, Bool) -> Void)?
    var moveArrowRequested: ((LegacyArrowMove.Direction, Bool) -> Void)?
    var heightNudgeRequested: ((Bool) -> Void)?
    var wavStepRequested: ((Int) -> Void)?
    var convertShortcutRequested: ((ChartConvert.ConvertShortcut) -> Void)?
    var timeSelectKeyRequested: ((ChartTool) -> Void)?
    var timeSelectionCommandRequested: ((TimeSelectionCommand) -> Void)?
    private(set) var timeStretchOrigin: TimeSelection?
    private var hoverEvent: ChartEventSnapshot?
    private var hoverLongNote: LongNoteSnapshot?
    private var timeHoverLine: TimeSelectionLine = .none
    private var timeDragLine: TimeSelectionLine?
    private var dragSource: ChartEventSnapshot?
    private var dragStartPoint: CGPoint?
    private var dragAnchorOffsetY: CGFloat = 0
    private var didDrag = false
    private var longDrag: LongNoteDrag?
    private var pendingLongWrite: PendingLongWrite?
    private var pendingCtrlToggleEvent: ChartEventSnapshot?
    private var pendingCtrlToggleLong: LongNoteSnapshot?
    private var ctrlCopyPreview: (shorts: [ChartDuplicate.ShortCopy], longs: [ChartDuplicate.LongCopy])?
    /// 选择工具拖动时的落点。松手前不写文档。
    private var movePreview: (shorts: [ChartDuplicate.ShortCopy], longs: [ChartDuplicate.LongCopy])?
    /// 长音端点拖动的预览。原长音先藏起来，避免原位和新长度叠在一起。
    private var endpointPreview: LongNoteSnapshot?
    /// 这次拖动已经把幽灵画进几何。结束时要再画一次文档里的音；已排队的刷新会合并掉。
    private var dragPaintNeedsRestore = false
    /// BMS 空白拖框。BMSON 仍用 `bmsonRubberBand`。
    private var bmsMarqueeOrigin: CGPoint?
    private var bmsMarqueeRect: CGRect?
    private var lastViewMouse = CGPoint.zero
    private var suppressNextMouseUp = false
    private(set) var presentedNotes: [ChartPresentedNote] = []
    private(set) var presentedPaintPasses = 0
    fileprivate(set) var rubberBandWasStroked = false

    private var showsTwoPlayerColumns = true
    private var hiddenPlayChannels: Set<String> = []
    private var bgmColumnCount = 0
    private var showsScrollColumn = false
    private var showsBPMColumn = false
    private var showsStopColumn = false
    private var showsBGAColumns = false
    private var showMasterLane = false
    var showsMasterLane: Bool { showMasterLane }
    private var soundChannelLanes: [ChartLane] = []
    private var onePlayerOrder: [(String, Int)]?
    private var twoPlayerOrder: [(String, Int)]?
    private var playSkinColors: [String: ChartPlaySkinColor] = [:]
    private(set) var chartLayout = ChartLayout(
        snapshot: .empty,
        longNotes: .empty,
        theme: .defaultTheme,
        side: .onePlayer,
        pixelsPerQuarterBeat: 48,
        division: 16
    )
    private(set) var viewport = CGRect.zero
    /// AppKit 的鼠标事件可远快于显示刷新；把重复的重建合并到下一次主循环。
    private var geometryRebuildScheduled = false
    var hasMetalRenderer: Bool { renderer?.isAvailable == true }
    var tool: ChartTool = .select
    var ntInputEnabled = true
    var wheelStep: CGFloat = 96
    var pageStep: CGFloat = 384
    var focusOnMouseEnter = false
    var disableFirstClick = false
    var stopPreviewOnClick = true
    /// 对应工具条 `TBPreviewOnClick`。默认开，和原版一样。
    var previewOnClick = true
    /// 点中发声列上的音符时，把 `#WAVxx` 交给内置预听。
    var previewNoteRequested: ((String) -> Void)?
    /// `#WAVxx` → 文件名。给同标签匹配和点音符预听用。
    var wavTable: [String: String] = [:]
    var bmpTable: [String: String] = [:]
    /// `DDFileName`：拖文件到主窗口或 WAV / BMP 列表时画在编辑区正中。
    var dragPreviewPaths: [String] = [] {
        didSet { labels.needsDisplay = true }
    }
    /// 鼠标所在拍，给 Preview 窗的 Play Here。
    private(set) var lastPointerBeat: Double = 0
    /// 打开 BMSON 且指针在谱面上时，对照 `SequenceViewCursor` 的脉冲、通道和命中。
    private(set) var bmsonCursor: BmsONECursor?
    var chartEvents: [ChartEventSnapshot] { snapshot.events }
    var chartLongNotes: [LongNoteSnapshot] { longNotes.notes }
    var bmsonSnapHitTestInEdit = false
    var bmsonSnapSelectionInEdit = true
    var bmsonViewMode = BmsONEViewMode.resolve("")
    private var bmsonRubberBand: BmsonRubberBand?
    private var bmsonRubberBandRect: CGRect?
    var middleButtonMoveMethod = 0
    var middleDeltaRelease = 10
    var gxHeight: CGFloat = 1
    var gxWidth: CGFloat = 1
    var chartClicked: (() -> Void)?
    /// 对应工具条 `TBShowFileName`。没有文件名时仍画 token。
    var isShowFileNameEnabled: (() -> Bool)?

    func invalidateNoteLabels() {
        labels.needsDisplay = true
        needsDisplay = true
    }

    func setPreviewPlayheadBeat(_ beat: Double?) {
        previewPlayheadBeat = beat
        if let beat {
            applyPlayheadLine(beat: beat)
        }
        rebuildGeometry()
    }

    private func applyPlayheadLine(beat: Double) {
        mouseGuideY = LegacyTimeSelection.lineY(
            vPosition: TimeSelection.vPosition(beat: beat),
            contentHeight: chartLayout.contentSize.height,
            pixelsPerQuarterBeat: pixelsPerQuarterBeat
        )
    }
    private var tracking: NSTrackingArea?
    private var middleAutoScrolling = false
    private var middleOriginScreen = CGPoint.zero
    private var middleDragOrigin = CGPoint.zero
    private var middleDragStartOffset = CGPoint.zero
    private var middleDragging = false
    private var middleTimer: Timer?
    var selectedEvent: ChartEventSnapshot? {
        didSet { rebuildGeometry() }
    }
    var selectedLongNote: LongNoteSnapshot? {
        didSet { rebuildGeometry() }
    }
    var selectedEvents: Set<ChartEventSnapshot> = []
    var selectedLongNotes: Set<LongNoteSnapshot> = []

    func isSelected(_ event: ChartEventSnapshot) -> Bool {
        event == selectedEvent || selectedEvents.contains(event)
    }

    func isSelected(_ note: LongNoteSnapshot) -> Bool {
        note == selectedLongNote || selectedLongNotes.contains(note)
    }

    func selectedChartItems() -> (events: Set<ChartEventSnapshot>, longNotes: Set<LongNoteSnapshot>) {
        var events = selectedEvents
        if let selectedEvent { events.insert(selectedEvent) }
        var longNotes = selectedLongNotes
        if let selectedLongNote { longNotes.insert(selectedLongNote) }
        return (events, longNotes)
    }

    /// `PanelVScroll`：可见区底边对应的 vpos 取负。滚动为 0 时拍 0 在底边。
    func panelVScroll() -> Double {
        let yBottom = offset.y + bounds.height - 1
        return -TimeSelection.vPosition(beat: chartLayout.beat(atY: yBottom))
    }

    func clipboardPasteBaseVPosition() -> Double {
        LegacyClipboard.pasteBaseVPosition(scrollVS: panelVScroll())
    }

    func selectAllNotes() {
        applySelection(events: selectAllEnabledEvents(), longNotes: selectAllEnabledLongNotes())
        guard tool == .timeSelect else { return }
        let greatest = LegacyTimeSelection.greatestVPosition(
            notes: selectAllGreatestCandidates(),
            ntInput: ntInputEnabled
        )
        timeSelection = LegacyTimeSelection.selectAllTimeSelection(
            greatestVPosition: greatest,
            currentHalf: timeSelection.half,
            bottoms: LegacyTimeSelection.measureBottoms(
                measures: snapshot.measures.map { (start: $0.start, length: $0.length) }
            )
        )
        timeSelectionDidChange?(timeSelection)
    }

    private func selectAllEnabledEvents() -> Set<ChartEventSnapshot> {
        let pairedLines = Set(longNotes.notes.flatMap { [$0.start.sourceLine, $0.end.sourceLine] })
        return Set(snapshot.events.filter { event in
            event.token != "00"
                && !pairedLines.contains(event.sourceLine)
                && LegacyTimeSelection.selectAllIncludesNote(
                    columnEnabled: selectAllColumnEnabled(channel: event.channel)
                )
        })
    }

    private func selectAllEnabledLongNotes() -> Set<LongNoteSnapshot> {
        Set(longNotes.notes.filter { note in
            LegacyTimeSelection.selectAllIncludesNote(
                columnEnabled: selectAllColumnEnabled(channel: note.channel)
            )
        })
    }

    /// 对照 `CalculateGreatestVPosition`：所有谱面音都算，不看列开关。头 BPM 不在列表里。
    private func selectAllGreatestCandidates() -> [(vPosition: Double, length: Double)] {
        let pairedLines = Set(longNotes.notes.flatMap { [$0.start.sourceLine, $0.end.sourceLine] })
        var notes: [(vPosition: Double, length: Double)] = []
        for event in snapshot.events where event.token != "00" && !pairedLines.contains(event.sourceLine) {
            notes.append((TimeSelection.vPosition(beat: event.beat), 0))
        }
        for note in longNotes.notes {
            let start = TimeSelection.vPosition(beat: note.start.beat)
            let end = TimeSelection.vPosition(beat: note.end.beat)
            if ntInputEnabled {
                notes.append((start, max(0, end - start)))
            } else {
                notes.append((start, 0))
                notes.append((end, 0))
            }
        }
        return notes
    }

    /// View 关掉的列没有车道。B 列用 `niB` 的宽度。BMSON 声道列只要画出来就算启用。
    private func selectAllColumnEnabled(channel: String) -> Bool {
        let display = chartLayout.displayChannel(for: channel)
        let laneVisible = chartLayout.lanes.contains { $0.channel == display }
        let index = EditorColumn.index(forChannel: channel)
        if index == EditorColumn.measure {
            return laneVisible
        }
        let themeIndex = min(index, EditorColumn.bgm)
        let width = chartLayout.theme.column(at: themeIndex)?.width ?? 0
        return LegacyTimeSelection.isEnabledAfterAll(
            isVisible: laneVisible,
            isNoteCol: LegacyTimeSelection.isNoteColumn(legacyIndex: themeIndex),
            width: width
        )
    }

    var copyChartRequested: (() -> Void)?
    var cutChartRequested: (() -> Void)?
    var pasteChartRequested: (() -> Void)?
    var deleteChartRequested: (() -> Void)?
    var selectAllChartRequested: (() -> Void)?
    var ctrlEditRequested: ((LegacyCtrlEdit.Action) -> Void)?

    @objc func copy(_ sender: Any?) { copyChartRequested?() }
    @objc func cut(_ sender: Any?) { cutChartRequested?() }
    @objc func paste(_ sender: Any?) { pasteChartRequested?() }
    @objc func delete(_ sender: Any?) { deleteChartRequested?() }
    @objc override func selectAll(_ sender: Any?) { selectAllChartRequested?() }

    func highlightsLane(_ channel: String) -> Bool {
        if hoverLaneChannel == channel {
            return true
        }
        return appliesBmsonSnap
            && channel == BmsonSoundLane.displayChannel(index: bmsonCurrentChannelIndex)
    }

    /// 声道列第一下只改当前声道。不是声道列、或已经是当前列，返回 true。
    func activateSoundChannelLaneIfNeeded(at point: CGPoint) -> Bool {
        guard appliesBmsonSnap,
              let channel = chartLayout.lane(at: point)?.channel,
              let index = BmsonSoundLane.index(display: channel)
        else {
            return true
        }
        return activateSoundChannelLaneRequested?(index) ?? true
    }

    func applyBmsonNoteDarken(applies: Bool, enabled: Bool, currentChannel: Int) {
        appliesBmsonNoteDarken = applies
        darkensInactiveBmsonChannels = enabled
        bmsonCurrentChannelIndex = currentChannel
        rebuildGeometry()
    }

    func applyBmsonSnap(
        applies: Bool,
        resolution: Int,
        fineGrid: BmsONEGridSize,
        bars: [Int64],
        snapHitTestInEdit: Bool = false,
        snapSelectionInEdit: Bool = true,
        viewMode: BmsONEViewMode = BmsONEViewMode.resolve("")
    ) {
        appliesBmsonSnap = applies
        bmsonResolution = resolution
        bmsonFineGrid = fineGrid
        bmsonBarPulses = bars
        bmsonSnapHitTestInEdit = snapHitTestInEdit
        bmsonSnapSelectionInEdit = snapSelectionInEdit
        bmsonViewMode = viewMode
        if !applies {
            bmsonCursor = nil
            bmsonRubberBand = nil
            bmsonRubberBandRect = nil
        }
    }

    func applyMasterOverlay(
        showLane: Bool,
        showMiniMap: Bool,
        pinned: Bool,
        opacity: Double,
        waveform: BmsONEMasterWaveformCache?
    ) {
        let laneChanged = showMasterLane != showLane
        showMasterLane = showLane
        self.showMiniMap = showMiniMap
        miniMapPinned = pinned
        miniMapOpacity = opacity
        masterWaveform = waveform
        if laneChanged {
            update(
                snapshot: snapshot,
                longNotes: longNotes,
                theme: theme,
                side: side,
                pixelsPerQuarterBeat: pixelsPerQuarterBeat,
                division: division,
                showMasterLane: showLane
            )
        } else {
            rebuildGeometry()
        }
    }

    func applyLaneWaveform(_ state: BmsonLaneWaveform.State?) {
        laneWaveform = state
        rebuildGeometry()
    }

    func paintedBmsonColors(_ colors: ThemeGradientColors, identity: Int) -> ThemeGradientColors {
        let enabled = appliesBmsonNoteDarken && darkensInactiveBmsonChannels
        let active = BmsONENoteDarken.isPaintedActive(
            identity: identity,
            currentChannel: bmsonCurrentChannelIndex,
            hoverIdentity: hoverPaintIdentity,
            identityStride: BmsonChartMapping.noteIdentityStride
        )
        return ThemeGradientColors(
            bright: ThemeColor(argb: BmsONENoteDarken.argb(colors.bright.argb, active: active, enabled: enabled)),
            dark: ThemeColor(argb: BmsONENoteDarken.argb(colors.dark.argb, active: active, enabled: enabled))
        )
    }

    private var hoverPaintIdentity: Int? {
        if let hoverLongNote { return hoverLongNote.start.sourceLine }
        if let hoverEvent { return hoverEvent.sourceLine }
        return nil
    }

    func applySelection(events: Set<ChartEventSnapshot>, longNotes: Set<LongNoteSnapshot>) {
        selectedEvents = events
        selectedLongNotes = longNotes
        selectedEvent = events.count == 1 && longNotes.isEmpty ? events.first : nil
        selectedLongNote = longNotes.count == 1 && events.isEmpty ? longNotes.first : nil
        rebuildGeometry()
        snapshotDidChange?(selectedEvent)
    }

    var snapshotDidChange: ((ChartEventSnapshot?) -> Void)?
    var contentSizeDidChange: ((CGSize, CGPoint) -> Void)?
    var writesBmsonContinue = false
    var appliesBmsonNoteDarken = false
    var appliesBmsonSnap = false
    var bmsonResolution = 240
    var bmsonFineGrid = BmsONESnap.defaultFineGrid
    var bmsonBarPulses: [Int64] = []
    var darkensInactiveBmsonChannels = BmsONENoteDarken.defaultEnabled
    var bmsonCurrentChannelIndex = 0
    var writeRequested: ((String, ChartMeasureSnapshot, Int, Bool) -> Void)?
    var writeAtPulseRequested: ((String, Int64, Bool) -> Void)?
    /// 声道列第一下只改当前声道。已经是当前列则返回 true，继续点写 / 点选。
    var activateSoundChannelLaneRequested: ((Int) -> Bool)?
    var moveRequested: ((ChartEventSnapshot, String, ChartMeasureSnapshot, Int) -> Bool)?
    var moveAtPulseRequested: ((ChartEventSnapshot, String, Int64) -> Bool)?
    var copyRequested: ((ChartEventSnapshot, String, Int, Int) -> Bool)?
    var copyAtVPositionRequested: ((ChartEventSnapshot, String, Double) -> Bool)?
    var copyLongAtVPositionRequested: ((LongNoteSnapshot, String, Double, Double) -> Bool)?
    /// 打开 BMSON 时一次交给文档 API，保证一笔撤销。
    var copyBatchAtVPositionRequested: (([ChartDuplicate.ShortCopy], [ChartDuplicate.LongCopy]) -> Bool)?
    /// 选择模式松手：搬走全部已选，不是只搬拖动源。
    var moveBatchAtVPositionRequested: (([ChartDuplicate.ShortCopy], [ChartDuplicate.LongCopy]) -> Bool)?
    var zoomWheelRequested: ((ChartZoomWheelEvent) -> Void)?
    var eraseRequested: ((ChartEventSnapshot) -> Void)?
    /// 选择工具双击：只改点中的短音，不开始拖动。
    var doubleClickNoteRequested: ((ChartEventSnapshot) -> Void)?
    /// 选择工具双击：只改点中的长音起点标签。
    var doubleClickLongNoteRequested: ((LongNoteSnapshot) -> Void)?
    /// Shift 右键：只改侧栏 WAV 选中，不删音。
    var wavSelectRequested: ((Int) -> Void)?
    var insertLongNoteRequested: ((String, ChartMeasureSnapshot, Int, ChartMeasureSnapshot, Int, Bool, Bool) -> Bool)?
    var insertLongAtPulseRequested: ((String, Int64, Int64, Bool) -> Bool)?
    var moveLongNoteRequested: ((LongNoteSnapshot, String, ChartMeasureSnapshot, Int) -> Bool)?
    var moveLongAtPulseRequested: ((LongNoteSnapshot, String, Int64) -> Bool)?
    var moveLongNoteStartRequested: ((LongNoteSnapshot, ChartMeasureSnapshot, Int) -> Bool)?
    var moveLongStartAtPulseRequested: ((LongNoteSnapshot, Int64) -> Bool)?
    var resizeLongNoteRequested: ((LongNoteSnapshot, ChartMeasureSnapshot, Int) -> Bool)?
    var resizeLongAtPulseRequested: ((LongNoteSnapshot, Int64) -> Bool)?
    var eraseLongNoteRequested: ((LongNoteSnapshot) -> Void)?
    var unsupportedGesture: ((String) -> Void)?
    /// 写入模式 + Command 点小节列。`remove` 为右键。拍已经对齐网格。
    var barLineEditRequested: ((Double, Bool) -> Bool)?
    /// 对照主控道按下：从该拍预览，不插小节线。
    var masterLanePreviewRequested: ((Double) -> Void)?
    var showMiniMap = false
    var miniMapPinned = false
    var miniMapOpacity = 0.67
    var masterWaveform: BmsONEMasterWaveformCache?
    var laneWaveform: BmsonLaneWaveform.State?
    private var lastViewMouseX: CGFloat = 0
    private var miniMapDrag: (originY: CGFloat, originOffsetY: CGFloat)?

    override init(frame frameRect: NSRect = .zero) {
        let device = MTLCreateSystemDefaultDevice()
        metalView = PassiveMetalView(frame: .zero, device: device)
        renderer = device.map(ChartRenderer.init(device:))
        super.init(frame: frameRect)

        wantsLayer = true
        configureMetalView()
        labels.translatesAutoresizingMaskIntoConstraints = false
        labels.surface = self
        addSubview(metalView)
        addSubview(labels)
        NSLayoutConstraint.activate([
            metalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            metalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            metalView.topAnchor.constraint(equalTo: topAnchor),
            metalView.bottomAnchor.constraint(equalTo: bottomAnchor),
            labels.leadingAnchor.constraint(equalTo: leadingAnchor),
            labels.trailingAnchor.constraint(equalTo: trailingAnchor),
            labels.topAnchor.constraint(equalTo: topAnchor),
            labels.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        rebuildGeometry()
        contentSizeDidChange?(chartLayout.contentSize, offset)
        refreshTrackingArea()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        refreshTrackingArea()
    }

    override func mouseEntered(with event: NSEvent) {
        if focusOnMouseEnter {
            window?.makeFirstResponder(self)
        }
        onBecomeActive?()
        super.mouseEntered(with: event)
    }

    func update(
        snapshot: ChartSnapshot,
        longNotes: LongNoteSnapshotSet,
        theme: ChartTheme,
        side: ChartSide,
        pixelsPerQuarterBeat: CGFloat,
        division: Int,
        subDivision: Int? = nil,
        showGrid: Bool? = nil,
        showSubGrid: Bool? = nil,
        showMeasureBar: Bool? = nil,
        showBackground: Bool? = nil,
        showMeasureNumber: Bool? = nil,
        showVerticalLine: Bool? = nil,
        showColumnCaption: Bool? = nil,
        showsTwoPlayerColumns: Bool? = nil,
        bgmColumnCount: Int? = nil,
        showsScrollColumn: Bool? = nil,
        showsBPMColumn: Bool? = nil,
        showsStopColumn: Bool? = nil,
        showsBGAColumns: Bool? = nil,
        gxWidth: CGFloat? = nil,
        showMasterLane: Bool? = nil,
        hiddenPlayChannels: Set<String>? = nil,
        soundChannelLanes: [ChartLane]? = nil,
        onePlayerOrder: [(String, Int)]? = nil,
        twoPlayerOrder: [(String, Int)]? = nil,
        playSkinColors: [String: ChartPlaySkinColor]? = nil
    ) {
        let priorSelection = selectedEvent
        let priorLongSelection = selectedLongNote
        let priorEvents = selectedEvents
        let priorLongNotes = selectedLongNotes
        let centerBeat = visibleCenterBeat()
        cancelDrag()
        self.side = side
        self.pixelsPerQuarterBeat = pixelsPerQuarterBeat
        self.division = clampGrid(division)
        if let subDivision { self.subDivision = clampGrid(subDivision) }
        if let showGrid { self.showGrid = showGrid }
        if let showSubGrid { self.showSubGrid = showSubGrid }
        if let showMeasureBar { self.showMeasureBar = showMeasureBar }
        if let showBackground { self.showBackground = showBackground }
        if let showMeasureNumber { self.showMeasureNumber = showMeasureNumber }
        if let showVerticalLine { self.showVerticalLine = showVerticalLine }
        if let showColumnCaption { self.showColumnCaption = showColumnCaption }
        if let showsTwoPlayerColumns { self.showsTwoPlayerColumns = showsTwoPlayerColumns }
        if let bgmColumnCount { self.bgmColumnCount = max(0, bgmColumnCount) }
        if let showsScrollColumn { self.showsScrollColumn = showsScrollColumn }
        if let showsBPMColumn { self.showsBPMColumn = showsBPMColumn }
        if let showsStopColumn { self.showsStopColumn = showsStopColumn }
        if let showsBGAColumns { self.showsBGAColumns = showsBGAColumns }
        if let gxWidth { self.gxWidth = max(0.000_1, gxWidth) }
        if let showMasterLane { self.showMasterLane = showMasterLane }
        if let hiddenPlayChannels { self.hiddenPlayChannels = hiddenPlayChannels }
        if let soundChannelLanes { self.soundChannelLanes = soundChannelLanes }
        self.onePlayerOrder = onePlayerOrder
        self.twoPlayerOrder = twoPlayerOrder
        if let playSkinColors { self.playSkinColors = playSkinColors }
        chartLayout = ChartLayout(
            snapshot: snapshot,
            longNotes: longNotes,
            theme: theme,
            side: side,
            pixelsPerQuarterBeat: pixelsPerQuarterBeat,
            division: self.division,
            subDivision: self.subDivision,
            showGrid: self.showGrid,
            showSubGrid: self.showSubGrid,
            showMeasureBar: self.showMeasureBar,
            showBackground: self.showBackground,
            showMeasureNumber: self.showMeasureNumber,
            showVerticalLine: self.showVerticalLine,
            showColumnCaption: self.showColumnCaption,
            showsTwoPlayerColumns: self.showsTwoPlayerColumns,
            bgmColumnCount: self.bgmColumnCount,
            showsScrollColumn: self.showsScrollColumn,
            showsBPMColumn: self.showsBPMColumn,
            showsStopColumn: self.showsStopColumn,
            showsBGAColumns: self.showsBGAColumns,
            gxWidth: self.gxWidth,
            showMasterLane: self.showMasterLane,
            hiddenPlayChannels: self.hiddenPlayChannels,
            soundChannelLanes: self.soundChannelLanes,
            onePlayerOrder: self.onePlayerOrder,
            twoPlayerOrder: self.twoPlayerOrder,
            playSkinColors: self.playSkinColors
        )
        self.snapshot = chartLayout.snapshot
        self.longNotes = longNotes
        self.theme = theme
        middleDeltaRelease = theme.visual.middleDeltaRelease
        gxHeight = max(0.000_1, pixelsPerQuarterBeat / MainWindowChrome.defaultPixelsPerQuarterBeat)
        let background = theme.visual.background.nsColor.usingColorSpace(.deviceRGB) ?? theme.visual.background.nsColor
        metalView.clearColor = MTLClearColor(
            red: Double(background.redComponent),
            green: Double(background.greenComponent),
            blue: Double(background.blueComponent),
            alpha: Double(background.alphaComponent)
        )
        selectedEvents = Set(priorEvents.compactMap { rebind($0, in: self.snapshot) })
        selectedLongNotes = Set(priorLongNotes.compactMap { rebind($0, in: longNotes) })
        selectedEvent = rebind(priorSelection, in: self.snapshot)
        selectedLongNote = rebind(priorLongSelection, in: longNotes)
        offset = boundedOffset(CGPoint(
            x: offset.x,
            y: chartLayout.contentSize.height - CGFloat(centerBeat) * pixelsPerQuarterBeat - bounds.height / 2
        ))
        rebuildGeometry()
        contentSizeDidChange?(chartLayout.contentSize, offset)
    }

    func setOffset(_ proposed: CGPoint) {
        offset = boundedOffset(proposed)
        rebuildGeometry()
        contentSizeDidChange?(chartLayout.contentSize, offset)
    }

    func setSide(_ side: ChartSide) {
        update(snapshot: snapshot, longNotes: longNotes, theme: theme, side: side, pixelsPerQuarterBeat: pixelsPerQuarterBeat, division: division)
    }

    func setDivision(_ division: Int) {
        update(snapshot: snapshot, longNotes: longNotes, theme: theme, side: side, pixelsPerQuarterBeat: pixelsPerQuarterBeat, division: division)
    }

    func setSubDivision(_ subDivision: Int) {
        update(snapshot: snapshot, longNotes: longNotes, theme: theme, side: side, pixelsPerQuarterBeat: pixelsPerQuarterBeat, division: division, subDivision: subDivision)
    }

    func setGridVisibility(
        showGrid: Bool? = nil,
        showSubGrid: Bool? = nil,
        showMeasureBar: Bool? = nil,
        showBackground: Bool? = nil,
        showMeasureNumber: Bool? = nil,
        showVerticalLine: Bool? = nil,
        showColumnCaption: Bool? = nil
    ) {
        update(
            snapshot: snapshot,
            longNotes: longNotes,
            theme: theme,
            side: side,
            pixelsPerQuarterBeat: pixelsPerQuarterBeat,
            division: division,
            showGrid: showGrid,
            showSubGrid: showSubGrid,
            showMeasureBar: showMeasureBar,
            showBackground: showBackground,
            showMeasureNumber: showMeasureNumber,
            showVerticalLine: showVerticalLine,
            showColumnCaption: showColumnCaption
        )
    }

    func setZoom(_ zoom: CGFloat) {
        update(snapshot: snapshot, longNotes: longNotes, theme: theme, side: side, pixelsPerQuarterBeat: zoom, division: division)
    }

    func setColumnScale(_ scale: CGFloat) {
        update(
            snapshot: snapshot,
            longNotes: longNotes,
            theme: theme,
            side: side,
            pixelsPerQuarterBeat: pixelsPerQuarterBeat,
            division: division,
            gxWidth: scale
        )
    }

    func setVerticalFraction(_ value: CGFloat) {
        let maximum = max(0, chartLayout.contentSize.height - bounds.height)
        setOffset(CGPoint(x: offset.x, y: maximum * value))
    }

    func setHorizontalFraction(_ value: CGFloat) {
        let maximum = max(0, chartLayout.contentSize.width - bounds.width)
        setOffset(CGPoint(x: maximum * value, y: offset.y))
    }

    func resetToMeasureZero() {
        setOffset(CGPoint(x: 0, y: max(0, chartLayout.contentSize.height - bounds.height)))
        selectedEvent = nil
        selectedLongNote = nil
        selectedEvents = []
        selectedLongNotes = []
    }

    func scrollToMeasure(_ measure: Int) {
        guard let vs = LegacyGotoMeasure.scrollVS(measure: measure) else { return }
        let beat = TimeSelection.beat(vPosition: -vs)
        setOffset(CGPoint(
            x: offset.x,
            y: chartLayout.contentSize.height - bounds.height - CGFloat(beat) * pixelsPerQuarterBeat
        ))
    }

    func setWaveform(left: [Float], right: [Float], sampleRate: Int) {
        var buffer = waveform ?? LegacyWaveform.Buffer(left: [], right: [], sampleRate: sampleRate)
        buffer.left = left
        buffer.right = right
        buffer.sampleRate = sampleRate
        buffer.locked = waveformLocked
        buffer.position = waveformPosition
        buffer.leftInset = waveformLeft
        buffer.width = waveformWidth
        buffer.precision = waveformPrecision
        waveform = buffer
        rebuildGeometry()
    }

    func setWaveformDisplay(left: Int, width: Int, precision: Int) {
        waveformLeft = LegacyWaveform.clampLeft(left)
        waveformWidth = LegacyWaveform.clampWidth(width)
        waveformPrecision = LegacyWaveform.clampPrecision(precision)
        guard var buffer = waveform else { return }
        buffer.leftInset = waveformLeft
        buffer.width = waveformWidth
        buffer.precision = waveformPrecision
        waveform = buffer
        rebuildGeometry()
    }

    func clearWaveform() {
        waveform = nil
        rebuildGeometry()
    }

    func setWaveformLocked(_ locked: Bool) {
        waveformLocked = locked
        guard var buffer = waveform else { return }
        buffer.locked = locked
        waveform = buffer
        rebuildGeometry()
    }

    func setWaveformPosition(_ position: Double) {
        waveformPosition = LegacyWaveform.clampPosition(position)
        guard var buffer = waveform else { return }
        buffer.position = waveformPosition
        waveform = buffer
        rebuildGeometry()
    }

    func waveformPixelRects() -> [CGRect] {
        guard let buffer = waveform, buffer.sampleRate > 0 else { return [] }
        let precision = LegacyWaveform.clampPrecision(buffer.precision)
        let height = max(0, Int(bounds.height.rounded(.towardZero)))
        let count = LegacyWaveform.sampleCount(height: height, precision: precision)
        guard count > 0 else { return [] }
        let lock = LegacyWaveform.drawingPosition(
            locked: buffer.locked,
            fieldPosition: buffer.position,
            firstBGMVPosition: firstBGMVPosition()
        )
        let segments = LegacyWaveform.segments(
            headBPM: headerBPM,
            bpmEvents: bpmEvents.map { ($0.vPosition, $0.value) },
            lockPosition: lock
        )
        let samples = LegacyWaveform.SampleLookup(segments: segments, sampleRate: buffer.sampleRate)
        var rects: [CGRect] = []
        rects.reserveCapacity(count * 2)
        for index in 0..<count {
            let y = LegacyWaveform.pointY(index: index, precision: precision)
            let contentY = CGFloat(y) + viewport.minY
            let vpos = TimeSelection.vPosition(beat: chartLayout.beat(atY: contentY))
            let sample = Int(samples.sampleIndex(vPosition: vpos))
            let leftX = sample >= 0 && sample < buffer.left.count
                ? LegacyWaveform.pointX(sample: buffer.left[sample], width: buffer.width, left: buffer.leftInset)
                : Double(buffer.leftInset)
            let rightX = sample >= 0 && sample < buffer.right.count
                ? LegacyWaveform.pointX(sample: buffer.right[sample], width: buffer.width, left: buffer.leftInset)
                : Double(buffer.leftInset)
            rects.append(CGRect(x: leftX, y: y, width: 1, height: 1))
            rects.append(CGRect(x: rightX, y: y, width: 1, height: 1))
        }
        return rects
    }

    private func firstBGMVPosition() -> Double? {
        var found: Double?
        for event in snapshot.events {
            guard ChartBGM.lane(display: event.channel) != nil else { continue }
            let vpos = TimeSelection.vPosition(beat: event.beat)
            if found == nil || vpos < found! {
                found = vpos
            }
        }
        return found
    }

    func cancelDrag() {
        let restorePaint = dragPaintNeedsRestore
        dragSource = nil
        dragStartPoint = nil
        didDrag = false
        longDrag = nil
        pendingLongWrite = nil
        pendingCtrlToggleEvent = nil
        pendingCtrlToggleLong = nil
        ctrlCopyPreview = nil
        movePreview = nil
        endpointPreview = nil
        dragPaintNeedsRestore = false
        timeDragLine = nil
        timeStretchOrigin = nil
        bmsonRubberBand = nil
        bmsonRubberBandRect = nil
        bmsMarqueeOrigin = nil
        bmsMarqueeRect = nil
        if var cursor = bmsonCursor {
            cursor.rangeBegin = nil
            cursor.rangeEnd = nil
            bmsonCursor = cursor
        }
        if restorePaint {
            rebuildGeometry()
        }
    }

    var hasHoverNote: Bool { hoverEvent != nil || hoverLongNote != nil }

    var hoverHasError: Bool {
        if let hoverLongNote {
            return errorAnchors.contains(ErrorAnchor(channel: hoverLongNote.channel, beat: hoverLongNote.start.beat))
        }
        if let hoverEvent {
            return errorAnchors.contains(ErrorAnchor(channel: hoverEvent.channel, beat: hoverEvent.beat))
        }
        return false
    }

    func applyTimeSelection(_ next: TimeSelection) {
        timeSelection = LegacyTimeSelection.validate(next, maxVPosition: currentMaxVPosition())
        timeSelectionDidChange?(timeSelection)
        selectNotes(in: timeSelection)
    }

    func timeSelectionFill() -> CGRect? {
        guard tool == .timeSelect else { return nil }
        return LegacyTimeSelection.fillRect(
            start: timeSelection.start,
            length: timeSelection.length,
            contentHeight: chartLayout.contentSize.height,
            pixelsPerQuarterBeat: pixelsPerQuarterBeat,
            width: max(bounds.width, chartLayout.contentSize.width)
        )
    }

    func timeSelectionLineYs() -> (start: CGFloat, half: CGFloat, end: CGFloat)? {
        guard tool == .timeSelect else { return nil }
        return (
            LegacyTimeSelection.lineY(vPosition: timeSelection.start, contentHeight: chartLayout.contentSize.height, pixelsPerQuarterBeat: pixelsPerQuarterBeat),
            LegacyTimeSelection.lineY(vPosition: timeSelection.halfPosition, contentHeight: chartLayout.contentSize.height, pixelsPerQuarterBeat: pixelsPerQuarterBeat),
            LegacyTimeSelection.lineY(vPosition: timeSelection.start + timeSelection.length, contentHeight: chartLayout.contentSize.height, pixelsPerQuarterBeat: pixelsPerQuarterBeat)
        )
    }

    func timeSelectionHoverRect() -> CGRect? {
        guard tool == .timeSelect, let lines = timeSelectionLineYs() else { return nil }
        let y: CGFloat
        switch timeHoverLine {
        case .start: y = lines.start
        case .half: y = lines.half
        case .end: y = lines.end
        case .none: return nil
        }
        return LegacyTimeSelection.timeHoverRect(lineY: y, width: max(bounds.width, chartLayout.contentSize.width))
    }

    func noteHoverOutlines() -> [CGRect] {
        guard tool == .select || tool == .timeSelect else { return [] }
        let flags = NSEvent.modifierFlags
        if LegacyLabelMatch.modifierMultiselectActive(
            control: flags.contains(.control),
            shift: flags.contains(.shift)
        ), let token = hoverLabelToken() {
            let matches = notesMatchingHoveredLabel(token)
            return matches.events.compactMap(shortNoteHoverOutline)
                + matches.longNotes.compactMap(longNoteHoverOutline)
        }
        if let hoverLongNote, let outline = longNoteHoverOutline(hoverLongNote) {
            return [outline]
        }
        if let hoverEvent, let outline = shortNoteHoverOutline(hoverEvent) {
            return [outline]
        }
        return []
    }

    private func hoverLabelToken() -> String? {
        if let hoverLongNote { return hoverLongNote.start.token }
        if let hoverEvent { return hoverEvent.token }
        return nil
    }

    private func shortNoteHoverOutline(_ event: ChartEventSnapshot) -> CGRect? {
        guard let lane = chartLayout.laneFrames[chartLayout.displayChannel(for: event.channel)] else { return nil }
        return LegacyTimeSelection.noteHoverOutline(
            laneLeft: lane.minX,
            laneWidth: lane.width,
            anchorY: chartLayout.y(forBeat: event.beat),
            noteHeight: CGFloat(theme.visual.noteHeight)
        )
    }

    private func longNoteHoverOutline(_ note: LongNoteSnapshot) -> CGRect? {
        guard let lane = chartLayout.laneFrames[chartLayout.displayChannel(for: note.channel)] else { return nil }
        return LegacyTimeSelection.longNoteHoverOutline(
            laneLeft: lane.minX,
            laneWidth: lane.width,
            startAnchorY: chartLayout.y(forBeat: note.start.beat),
            endAnchorY: chartLayout.y(forBeat: note.end.beat),
            noteHeight: CGFloat(theme.visual.noteHeight)
        )
    }

    /// 表里有文件名就用；没有就空串，同标签匹配会回退到 token。
    private func wavFileName(forToken token: String) -> String {
        LegacyPreviewAudio.fileName(forToken: token, in: wavTable) ?? ""
    }

    private func bmpFileName(forToken token: String) -> String {
        LegacyPreviewAudio.fileName(forToken: token, in: bmpTable) ?? ""
    }

    func noteCaption(token: String, channel: String) -> String {
        LegacyLabelMatch.noteCaption(
            token: token,
            channel: channel,
            showFileName: showFileNameEnabled,
            wavName: wavFileName(forToken: token),
            bmpName: bmpFileName(forToken: token)
        )
    }

    private var showFileNameEnabled: Bool { isShowFileNameEnabled?() ?? false }

    private func selectableShortEvents() -> [ChartEventSnapshot] {
        let longLines = Set(longNotes.notes.flatMap { [$0.start.sourceLine, $0.end.sourceLine] })
        return snapshot.events.filter { $0.token != "00" && !longLines.contains($0.sourceLine) }
    }

    private func notesMatchingHoveredLabel(_ hoverToken: String) -> (
        events: [ChartEventSnapshot],
        longNotes: [LongNoteSnapshot]
    ) {
        let hoverFileName = wavFileName(forToken: hoverToken)
        let showFileName = showFileNameEnabled
        var fileNames: [String: String] = [hoverToken: hoverFileName]
        func fileName(for token: String) -> String {
            if let cached = fileNames[token] { return cached }
            let name = wavFileName(forToken: token)
            fileNames[token] = name
            return name
        }
        let events = selectableShortEvents().filter { event in
            LegacyLabelMatch.isLabelMatch(
                hoverToken: hoverToken,
                candidateToken: event.token,
                showFileName: showFileName,
                hoverFileName: hoverFileName,
                candidateFileName: fileName(for: event.token)
            )
        }
        let longs = longNotes.notes.filter { note in
            LegacyLabelMatch.isLabelMatch(
                hoverToken: hoverToken,
                candidateToken: note.start.token,
                showFileName: showFileName,
                hoverFileName: hoverFileName,
                candidateFileName: fileName(for: note.start.token)
            )
        }
        return (events, longs)
    }

    /// 对照 `DoubleClickNoteIndex`。只在选择工具；没命中返回 false。
    private func handleSelectDoubleClick(at point: CGPoint) -> Bool {
        if let hit = chartLayout.hitTestLongNote(point) {
            doubleClickLongNoteRequested?(hit.note)
            return true
        }
        if let hit = chartLayout.hitTest(point) {
            doubleClickNoteRequested?(hit)
            return true
        }
        return false
    }

    private func handleSelectModifierClick(at point: CGPoint, shift: Bool) {
        let hitLong = chartLayout.hitTestLongNote(point)?.note
        let hitEvent = hitLong == nil ? chartLayout.hitTest(point) : nil
        switch LegacyLabelMatch.selectClick(control: true, shift: shift, hitNote: hitLong != nil || hitEvent != nil) {
        case .addMatchingLabel:
            addSelectionMatchingHoveredLabel(at: point)
        case .toggle:
            pendingCtrlToggleLong = hitLong
            pendingCtrlToggleEvent = hitEvent
            dragStartPoint = point
            didDrag = false
        case .marqueeKeep:
            dragStartPoint = point
            didDrag = false
        case .replace, .marqueeClear:
            break
        }
    }

    private func commitCtrlCopyIfNeeded(at point: CGPoint) {
        guard snapshot.editable else { return }
        updateCtrlCopyPreview(at: point)
        guard let preview = ctrlCopyPreview else { return }
        if let copyBatchAtVPositionRequested {
            _ = copyBatchAtVPositionRequested(preview.shorts, preview.longs)
        } else {
            for copy in preview.shorts {
                if let copyAtVPositionRequested {
                    _ = copyAtVPositionRequested(copy.event, copy.channel, copy.vPosition)
                } else {
                    let location = LegacyClipboard.location(vPosition: copy.vPosition)
                    let slot = chartLayout.division > 0
                        ? Int(location.numerator * Int64(chartLayout.division) / location.denominator)
                        : 0
                    _ = copyRequested?(copy.event, copy.channel, location.measure, slot)
                }
            }
            for copy in preview.longs {
                _ = copyLongAtVPositionRequested?(copy.note, copy.channel, copy.vPosition, copy.length)
            }
        }
        selectCopiedNotes(preview)
        ctrlCopyPreview = nil
    }

    private func updateCtrlCopyPreview(at point: CGPoint) {
        guard let plan = ctrlCopyPlan(at: point) else {
            if ctrlCopyPreview != nil {
                ctrlCopyPreview = nil
                dragPaintNeedsRestore = false
                rebuildGeometry()
            }
            return
        }
        ctrlCopyPreview = plan
        dragPaintNeedsRestore = true
        rebuildGeometry()
    }

    private func ctrlCopyPlan(at point: CGPoint) -> (shorts: [ChartDuplicate.ShortCopy], longs: [ChartDuplicate.LongCopy])? {
        guard snapshot.editable else { return nil }
        guard let lane = chartLayout.lane(at: point), lane.editable else { return nil }
        let mouseV = resolvedVPosition(at: point, snap: snapEnabled).value
        let selected = selectedChartItems()
        let lanes = chartLayout.lanes.map(\.channel)
        if let source = pendingCtrlToggleEvent {
            let shorts = ChartDuplicate.notesToCopy(selected: selected.events, origin: source)
            let longs = Array(selected.longNotes)
            return ChartDuplicate.plan(
                shorts: shorts,
                longs: longs,
                originChannel: source.channel,
                originVPosition: ChartDuplicate.vPosition(beat: source.beat),
                originLength: 0,
                mouseChannel: lane.channel,
                mouseVPosition: mouseV,
                lanes: lanes,
                ntInput: ntInputEnabled,
                disableVerticalMove: disableVerticalMove
            )
        }
        if let source = pendingCtrlToggleLong {
            let shorts = Array(selected.events)
            let longs = ChartDuplicate.notesToCopy(selected: selected.longNotes, origin: source)
            let length = ChartDuplicate.vPosition(beat: source.end.beat) - ChartDuplicate.vPosition(beat: source.start.beat)
            return ChartDuplicate.plan(
                shorts: shorts,
                longs: longs,
                originChannel: source.channel,
                originVPosition: ChartDuplicate.vPosition(beat: source.start.beat),
                originLength: length,
                mouseChannel: lane.channel,
                mouseVPosition: mouseV,
                lanes: lanes,
                ntInput: ntInputEnabled,
                disableVerticalMove: disableVerticalMove
            )
        }
        return nil
    }

    /// 对照 `OnSelectModeMoveNotes`：已选短音 + 长音 + 鼠标源，位移与 Ctrl 复制同一套夹紧。
    private func selectMovePlan(at point: CGPoint) -> (shorts: [ChartDuplicate.ShortCopy], longs: [ChartDuplicate.LongCopy])? {
        guard snapshot.editable else { return nil }
        guard let lane = chartLayout.lane(at: point), lane.editable else { return nil }
        let mouseV = resolvedVPosition(at: point, snap: snapEnabled).value
        let selected = selectedChartItems()
        let lanes = chartLayout.lanes.map(\.channel)
        if let source = dragSource {
            let shorts = ChartDuplicate.notesToCopy(selected: selected.events, origin: source)
            let longs = Array(selected.longNotes)
            return ChartDuplicate.plan(
                shorts: shorts,
                longs: longs,
                originChannel: source.channel,
                originVPosition: ChartDuplicate.vPosition(beat: source.beat),
                originLength: 0,
                mouseChannel: lane.channel,
                mouseVPosition: mouseV,
                lanes: lanes,
                ntInput: ntInputEnabled,
                disableVerticalMove: disableVerticalMove
            )
        }
        if let source = longDrag?.note, longDrag?.part == .body {
            let shorts = Array(selected.events)
            let longs = ChartDuplicate.notesToCopy(selected: selected.longNotes, origin: source)
            let length = ChartDuplicate.vPosition(beat: source.end.beat) - ChartDuplicate.vPosition(beat: source.start.beat)
            return ChartDuplicate.plan(
                shorts: shorts,
                longs: longs,
                originChannel: source.channel,
                originVPosition: ChartDuplicate.vPosition(beat: source.start.beat),
                originLength: length,
                mouseChannel: lane.channel,
                mouseVPosition: mouseV,
                lanes: lanes,
                ntInput: ntInputEnabled,
                disableVerticalMove: disableVerticalMove
            )
        }
        return nil
    }

    fileprivate func currentPresentedPaint() -> [PresentedPaint] {
        syncDragHideIndex()
        var items: [PresentedPaint] = []
        var summary: [ChartPresentedNote] = []
        func addShort(_ note: ChartNoteRect, ghost: Bool, selected: Bool) {
            let colors = paintedBmsonColors(metalBaseColors(for: note.event), identity: note.event.sourceLine)
            items.append(PresentedPaint(
                ghost: ghost,
                selected: selected,
                colors: colors,
                shortNote: note,
                longNote: nil
            ))
            summary.append(ChartPresentedNote(
                ghost: ghost,
                longNote: false,
                channel: note.event.channel,
                beat: note.event.beat,
                endBeat: note.event.beat,
                token: note.event.token,
                contentRect: note.rect
            ))
        }
        func addLong(_ note: ChartLongNoteRect, ghost: Bool, selected: Bool) {
            let colors = paintedBmsonColors(metalLongColors(for: note.note), identity: note.note.start.sourceLine)
            items.append(PresentedPaint(
                ghost: ghost,
                selected: selected,
                colors: colors,
                shortNote: nil,
                longNote: note
            ))
            summary.append(ChartPresentedNote(
                ghost: ghost,
                longNote: true,
                channel: note.note.channel,
                beat: note.note.start.beat,
                endBeat: note.note.end.beat,
                token: note.note.start.token,
                contentRect: note.outline
            ))
        }
        for note in chartLayout.visibleNoteRects(in: viewport) where !hidesDraggedShort(note.event) {
            addShort(note, ghost: false, selected: isSelected(note.event))
        }
        for note in chartLayout.visibleLongNoteRects(in: viewport) where !hidesDraggedLong(note.note) {
            addLong(note, ghost: false, selected: isSelected(note.note))
        }
        for note in ghostShortRects() where note.rect.intersects(viewport) {
            addShort(note, ghost: true, selected: true)
        }
        for note in ghostLongRects() where note.outline.intersects(viewport) || note.fill.intersects(viewport) {
            addLong(note, ghost: true, selected: true)
        }
        presentedNotes = summary
        presentedPaintPasses += 1
        return items
    }

    private var draggedShortIdentities: Set<ChartEventSnapshot> = []
    private var draggedLongIdentities: Set<LongNoteSnapshot> = []

    private func syncDragHideIndex() {
        guard didDrag, let movePreview else {
            draggedShortIdentities = []
            draggedLongIdentities = []
            return
        }
        draggedShortIdentities = Set(movePreview.shorts.map(\.event))
        draggedLongIdentities = Set(movePreview.longs.map(\.note))
    }

    private func hidesDraggedShort(_ event: ChartEventSnapshot) -> Bool {
        guard didDrag, movePreview != nil else { return false }
        return draggedShortIdentities.contains(event)
    }

    private func hidesDraggedLong(_ note: LongNoteSnapshot) -> Bool {
        if didDrag, movePreview != nil, draggedLongIdentities.contains(note) {
            return true
        }
        if didDrag, endpointPreview != nil, longDrag?.note == note, longDrag?.part != .body {
            return true
        }
        return false
    }

    private func ghostShortRects() -> [ChartNoteRect] {
        var copies: [ChartDuplicate.ShortCopy] = []
        if let ctrlCopyPreview {
            copies.append(contentsOf: ctrlCopyPreview.shorts)
        }
        if didDrag, let movePreview {
            copies.append(contentsOf: movePreview.shorts)
        }
        return copies.compactMap { chartLayout.eventRect(ChartDuplicate.previewEvent($0)) }
    }

    private func ghostLongRects() -> [ChartLongNoteRect] {
        var notes: [LongNoteSnapshot] = []
        if let ctrlCopyPreview {
            notes.append(contentsOf: ctrlCopyPreview.longs.map(ChartDuplicate.previewLong))
        }
        if didDrag, let movePreview {
            notes.append(contentsOf: movePreview.longs.map(ChartDuplicate.previewLong))
        }
        if didDrag, let endpointPreview {
            notes.append(endpointPreview)
        }
        return notes.compactMap { chartLayout.longNoteRect($0) }
    }

    private func activeAnchorOffset() -> CGFloat {
        if let longDrag { return longDrag.anchorOffsetY }
        return dragAnchorOffsetY
    }

    private func updateMovePreview(at point: CGPoint) {
        let anchored = ChartInput.pointForAnchor(from: point, anchorOffsetY: activeAnchorOffset())
        guard let plan = selectMovePlan(at: anchored) else {
            if movePreview != nil {
                movePreview = nil
                dragPaintNeedsRestore = false
                rebuildGeometry()
            }
            return
        }
        movePreview = plan
        endpointPreview = nil
        dragPaintNeedsRestore = true
        rebuildGeometry()
    }

    private func updateEndpointPreview(at point: CGPoint) {
        guard let preview = endpointPreviewNote(at: point) else {
            if endpointPreview != nil {
                endpointPreview = nil
                dragPaintNeedsRestore = false
                rebuildGeometry()
            }
            return
        }
        endpointPreview = preview
        movePreview = nil
        dragPaintNeedsRestore = true
        rebuildGeometry()
    }

    private func endpointBeats(for drag: LongNoteDrag, at point: CGPoint) -> (start: Double, end: Double)? {
        guard drag.part != .body else { return nil }
        let anchor = ChartInput.pointForAnchor(from: point, anchorOffsetY: drag.anchorOffsetY)
        let beat: Double
        if appliesBmsonSnap {
            beat = BmsonChartMapping.beat(
                pulse: bmsonWritePulse(at: anchor, snap: snapEnabled),
                resolution: bmsonResolution
            )
        } else {
            guard let target = snapTarget(at: anchor, lockingBeat: nil) else { return nil }
            beat = target.measure.start + Double(target.slot) * 4.0 / Double(max(1, chartLayout.division))
        }
        let start = drag.part == .startCap ? beat : drag.note.start.beat
        let end = drag.part == .endCap ? beat : drag.note.end.beat
        return (start, end)
    }

    private func endpointPreviewNote(at point: CGPoint) -> LongNoteSnapshot? {
        guard let drag = longDrag, let beats = endpointBeats(for: drag, at: point) else { return nil }
        let start = beats.start
        let end = beats.end
        if end - start <= 0.000_001 { return nil }
        if abs(start - drag.note.start.beat) < 0.000_001 && abs(end - drag.note.end.beat) < 0.000_001 {
            return nil
        }
        return LongNoteSnapshot(
            channel: drag.note.channel,
            start: LongNoteEndpointSnapshot(
                measure: drag.note.start.measure,
                fractionNumerator: drag.note.start.fractionNumerator,
                fractionDenominator: drag.note.start.fractionDenominator,
                beat: start,
                token: drag.note.start.token,
                sourceLine: -1
            ),
            end: LongNoteEndpointSnapshot(
                measure: drag.note.end.measure,
                fractionNumerator: drag.note.end.fractionNumerator,
                fractionDenominator: drag.note.end.fractionDenominator,
                beat: end,
                token: drag.note.end.token,
                sourceLine: -2
            ),
            encoding: drag.note.encoding
        )
    }

    private func clearTransientPreviews() {
        let hadPreview = movePreview != nil || endpointPreview != nil || ctrlCopyPreview != nil
        movePreview = nil
        endpointPreview = nil
        ctrlCopyPreview = nil
        if hadPreview {
            dragPaintNeedsRestore = false
            rebuildGeometry()
        }
    }

    private func refreshSelectDragPresentation(at point: CGPoint) {
        guard tool == .select else { return }
        if !didDrag {
            clearTransientPreviews()
            return
        }
        if pendingCtrlToggleEvent != nil || pendingCtrlToggleLong != nil {
            updateCtrlCopyPreview(at: point)
            return
        }
        if bmsMarqueeOrigin != nil {
            updateBmsMarquee(to: point)
            return
        }
        if bmsonRubberBand != nil {
            updateBmsonRubberBand(at: point)
            return
        }
        if let longDrag, longDrag.part != .body {
            updateEndpointPreview(at: point)
            return
        }
        if dragSource != nil || longDrag?.part == .body {
            updateMovePreview(at: point)
        }
    }

    private func chartPoint(forView view: CGPoint) -> CGPoint {
        CGPoint(x: view.x + offset.x, y: view.y + offset.y)
    }

    func synchronizePresentation() {
        geometryRebuildScheduled = false
        performGeometryRebuild()
        labels.display()
    }

    /// 有 Metal 时正常刷新不走回退身体。探测另画一次回退路径，确认它和金属用同一份音符。
    func exerciseFallbackPaint() {
        viewport = CGRect(origin: offset, size: bounds.size)
        let pixelsWide = max(Int(bounds.width.rounded(.towardZero)), 1)
        let pixelsHigh = max(Int(bounds.height.rounded(.towardZero)), 1)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            labels.drawFallbackForProbe()
            return
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        labels.drawFallbackForProbe()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// 框选边在覆盖层上。返回边框附近非透明像素数，用来确认这条绘制真的发生了。
    func rubberBandBitmapHitCount() -> Int {
        guard let band = bmsonRubberBandFrame(), bounds.width > 1, bounds.height > 1 else { return 0 }
        let pixelsWide = max(Int(bounds.width.rounded(.towardZero)), 1)
        let pixelsHigh = max(Int(bounds.height.rounded(.towardZero)), 1)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return 0 }
        labels.cacheDisplay(in: labels.bounds, to: rep)
        let viewBand = band.offsetBy(dx: -viewport.minX, dy: -viewport.minY)
        let guideY = mouseGuideY.map { Int(($0 - viewport.minY).rounded(.towardZero)) }
        func isStroke(_ color: NSColor?) -> Bool {
            guard let color, let rgb = color.usingColorSpace(.deviceRGB) else { return false }
            return rgb.alphaComponent > 0.2
                && rgb.redComponent > 0.55
                && rgb.greenComponent > 0.55
                && rgb.blueComponent > 0.55
        }
        func hits(atX x: Int, y: Int) -> Bool {
            guard x >= 0, y >= 0, x < pixelsWide, y < pixelsHigh else { return false }
            if let guideY, abs(y - guideY) <= 2 || abs(y - (pixelsHigh - 1 - guideY)) <= 2 {
                return false
            }
            return isStroke(rep.colorAt(x: x, y: y))
                || isStroke(rep.colorAt(x: x, y: pixelsHigh - 1 - y))
        }
        var count = 0
        let left = Int(viewBand.minX.rounded(.towardZero))
        let right = Int(viewBand.maxX.rounded(.towardZero))
        let top = Int(viewBand.minY.rounded(.towardZero))
        let bottom = Int(viewBand.maxY.rounded(.towardZero))
        var y = top
        while y <= bottom {
            if hits(atX: left, y: y) || hits(atX: left + 1, y: y) || hits(atX: right, y: y) || hits(atX: right - 1, y: y) {
                count += 1
            }
            y += 3
        }
        return count
    }

    private func selectCopiedNotes(_ preview: (shorts: [ChartDuplicate.ShortCopy], longs: [ChartDuplicate.LongCopy])) {
        var events: Set<ChartEventSnapshot> = []
        for copy in preview.shorts {
            let beat = ChartDuplicate.beat(vPosition: copy.vPosition)
            if let found = snapshot.events.first(where: {
                $0.channel == copy.channel
                    && $0.token == copy.event.token
                    && abs($0.beat - beat) < 0.000_001
            }) {
                events.insert(found)
            }
        }
        var longs: Set<LongNoteSnapshot> = []
        for copy in preview.longs {
            let startBeat = ChartDuplicate.beat(vPosition: copy.vPosition)
            if let found = longNotes.notes.first(where: {
                $0.channel == copy.channel
                    && $0.start.token == copy.note.start.token
                    && abs($0.start.beat - startBeat) < 0.000_001
            }) {
                longs.insert(found)
            }
        }
        applySelection(events: events, longNotes: longs)
    }

    private func commitCtrlToggleIfNeeded() {
        if let note = pendingCtrlToggleLong {
            let current = selectedChartItems()
            applySelection(
                events: current.events,
                longNotes: LegacyLabelMatch.toggling(selected: current.longNotes, item: note)
            )
            return
        }
        if let event = pendingCtrlToggleEvent {
            let current = selectedChartItems()
            applySelection(
                events: LegacyLabelMatch.toggling(selected: current.events, item: event),
                longNotes: current.longNotes
            )
        }
    }

    private func addSelectionMatchingHoveredLabel(at point: CGPoint) {
        let hoverToken: String
        if let hit = chartLayout.hitTestLongNote(point) {
            hoverLongNote = hit.note
            hoverEvent = nil
            hoverUsesEndPen = hit.part != .body
            hoverToken = hit.note.start.token
        } else if let event = chartLayout.hitTest(point) {
            hoverEvent = event
            hoverLongNote = nil
            hoverUsesEndPen = false
            hoverToken = event.token
        } else {
            return
        }
        let matches = notesMatchingHoveredLabel(hoverToken)
        let current = selectedChartItems()
        applySelection(
            events: LegacyLabelMatch.selectingAdds(selected: current.events, matching: matches.events),
            longNotes: LegacyLabelMatch.selectingAdds(selected: current.longNotes, matching: matches.longNotes)
        )
    }

    /// Control+Shift+A：用当前 `KMouseOver` 的 token 做 OR 加选，不清已选。
    private func addSelectionMatchingCurrentHover() {
        guard let token = hoverLabelToken() else { return }
        let matches = notesMatchingHoveredLabel(token)
        let current = selectedChartItems()
        applySelection(
            events: LegacyLabelMatch.selectingAdds(selected: current.events, matching: matches.events),
            longNotes: LegacyLabelMatch.selectingAdds(selected: current.longNotes, matching: matches.longNotes)
        )
    }

    func timeSelectionBPMLabels() -> [(text: String, y: CGFloat)] {
        guard tool == .timeSelect else { return [] }
        func label(_ vPosition: Double) -> (String, CGFloat) {
            let bpm = LegacyTimeSelection.bpmAt(vPosition: vPosition, header: headerBPM, events: bpmEvents)
            let y = LegacyTimeSelection.lineY(
                vPosition: vPosition,
                contentHeight: chartLayout.contentSize.height,
                pixelsPerQuarterBeat: pixelsPerQuarterBeat
            )
            return (LegacyTimeSelection.formatField(bpm), y)
        }
        return [
            label(timeSelection.start),
            label(timeSelection.halfPosition),
            label(timeSelection.start + timeSelection.length)
        ]
    }

    private func currentMaxVPosition() -> Double {
        let end = chartLayout.snapshot.measures.map { $0.start + $0.length }.max() ?? 4
        return LegacyTimeSelection.maxVPosition(chartEndBeat: end)
    }

    private func clampGrid(_ value: Int) -> Int {
        min(1920, max(1, value))
    }

    private func snapTarget(
        at point: CGPoint,
        lockingBeat beat: Double?
    ) -> (measure: ChartMeasureSnapshot, slot: Int)? {
        let query: CGPoint
        if disableVerticalMove, let beat {
            query = CGPoint(x: point.x, y: chartLayout.y(forBeat: beat))
        } else {
            query = point
        }
        return chartLayout.snapTarget(at: query)
    }

    private func resolvedVPosition(at point: CGPoint, snap: Bool) -> (value: Double, note: Double?) {
        let note = chartLayout.hitTest(point).map { TimeSelection.vPosition(beat: $0.beat) }
            ?? chartLayout.hitTestLongNote(point).map { TimeSelection.vPosition(beat: $0.note.start.beat) }
        if let note {
            return (note, note)
        }
        if appliesBmsonSnap {
            let beat = BmsonChartMapping.beat(pulse: bmsonWritePulse(at: point, snap: snap), resolution: bmsonResolution)
            return (TimeSelection.vPosition(beat: beat), nil)
        }
        let raw = TimeSelection.vPosition(beat: chartLayout.beat(atY: point.y))
        if snap, let target = chartLayout.snapTarget(at: point) {
            let beat = target.measure.start + Double(target.slot) * 4.0 / Double(max(1, chartLayout.division))
            return (TimeSelection.vPosition(beat: beat), nil)
        }
        return (raw, nil)
    }

    private func bmsonWritePulse(at point: CGPoint, snap: Bool) -> Int64 {
        BmsONESnap.writePulse(
            time: chartLayout.beat(atY: point.y) * Double(max(1, bmsonResolution)),
            snap: snap,
            bars: bmsonBarPulses,
            resolution: bmsonResolution,
            fineGrid: bmsonFineGrid
        )
    }

    /// 写入模式勾上 Snap 就吸格。选择模式默认不吸，除非 Preferences 勾了 snapped hit test。
    /// 停在已有音符上时用音符脉冲，对照 `SetExistingSoundNote`。
    private func updateBmsonCursor(at point: CGPoint) {
        guard appliesBmsonSnap else {
            bmsonCursor = nil
            return
        }
        if bmsonRubberBand != nil, didDrag {
            updateBmsonRubberBand(at: point)
            return
        }
        let writeMode = tool == .write || tool == .longNote
        if let event = chartLayout.hitTest(point) {
            bmsonCursor = BmsONECursor(
                pulse: BmsonChartMapping.pulse(beat: event.beat, resolution: bmsonResolution),
                channel: event.channel,
                writeMode: writeMode,
                inMeasureArea: false,
                hitLength: 0
            )
            return
        }
        if let long = chartLayout.hitTestLongNote(point) {
            let start = BmsonChartMapping.pulse(beat: long.note.start.beat, resolution: bmsonResolution)
            let end = BmsonChartMapping.pulse(beat: long.note.end.beat, resolution: bmsonResolution)
            bmsonCursor = BmsONECursor(
                pulse: start,
                channel: long.note.channel,
                writeMode: writeMode,
                inMeasureArea: false,
                hitLength: max(0, end - start)
            )
            return
        }
        let snap = snapEnabled && (writeMode || bmsonSnapHitTestInEdit)
        bmsonCursor = BmsONECursor(
            pulse: bmsonWritePulse(at: point, snap: snap),
            channel: hoverLaneChannel,
            writeMode: writeMode,
            inMeasureArea: chartLayout.isMeasureArea(point),
            hitLength: nil
        )
    }

    @discardableResult
    private func beginSelectRubberBand(at point: CGPoint) -> Bool {
        if appliesBmsonSnap {
            return beginBmsonRubberBand(at: point)
        }
        guard tool == .select else { return false }
        guard chartLayout.hitTest(point) == nil, chartLayout.hitTestLongNote(point) == nil else {
            return false
        }
        bmsMarqueeOrigin = point
        bmsMarqueeRect = nil
        if dragStartPoint == nil {
            dragStartPoint = point
        }
        return true
    }

    private func updateBmsMarquee(to point: CGPoint) {
        guard let origin = bmsMarqueeOrigin else { return }
        bmsMarqueeRect = ChartInput.marqueeRect(from: origin, to: point)
        labels.needsDisplay = true
    }

    private func commitBmsMarquee(shift: Bool) {
        guard let rect = bmsMarqueeRect else { return }
        let pairedLines = Set(longNotes.notes.flatMap { [$0.start.sourceLine, $0.end.sourceLine] })
        var events = selectedEvents
        if let selectedEvent { events.insert(selectedEvent) }
        var longs = selectedLongNotes
        if let selectedLongNote { longs.insert(selectedLongNote) }
        for note in longNotes.notes {
            guard let painted = chartLayout.longNoteRect(note) else { continue }
            let hit = painted.outline.intersects(rect)
                || painted.fill.intersects(rect)
                || painted.startCap.intersects(rect)
                || painted.endCap.intersects(rect)
            guard hit else { continue }
            if shift {
                if longs.contains(note) {
                    longs.remove(note)
                } else {
                    longs.insert(note)
                }
            } else {
                longs.insert(note)
            }
        }
        for event in snapshot.events {
            if pairedLines.contains(event.sourceLine) { continue }
            guard let painted = chartLayout.eventRect(event), painted.rect.intersects(rect) else { continue }
            if shift {
                if events.contains(event) {
                    events.remove(event)
                } else {
                    events.insert(event)
                }
            } else {
                events.insert(event)
            }
        }
        applySelection(events: events, longNotes: longs)
    }

    @discardableResult
    private func beginBmsonRubberBand(at point: CGPoint) -> Bool {
        guard appliesBmsonSnap, tool == .select else { return false }
        guard chartLayout.hitTest(point) == nil, chartLayout.hitTestLongNote(point) == nil else {
            return false
        }
        guard let channel = chartLayout.lane(at: point)?.channel else { return false }
        guard let kind = BmsONEStatus.rubberBandKind(channel: channel, mode: bmsonViewMode) else {
            return false
        }
        let rawTime = chartLayout.beat(atY: point.y) * Double(max(1, bmsonResolution))
        bmsonRubberBand = BmsonRubberBand(
            kind: kind,
            originChannel: channel,
            originPulse: BmsONEStatus.rubberBandOriginPulse(
                time: rawTime,
                snapToGrid: snapEnabled,
                snapSelection: bmsonSnapSelectionInEdit,
                bars: bmsonBarPulses,
                resolution: bmsonResolution,
                fineGrid: bmsonFineGrid
            )
        )
        bmsonRubberBandRect = nil
        if dragStartPoint == nil {
            dragStartPoint = point
        }
        return true
    }

    private func updateBmsonRubberBand(at point: CGPoint) {
        guard let band = bmsonRubberBand else { return }
        let rawTime = chartLayout.beat(atY: point.y) * Double(max(1, bmsonResolution))
        let times = BmsONEStatus.rubberBandTimes(
            origin: band.originPulse,
            time: rawTime,
            snapToGrid: snapEnabled,
            snapSelection: bmsonSnapSelectionInEdit,
            bars: bmsonBarPulses,
            resolution: bmsonResolution,
            fineGrid: bmsonFineGrid
        )
        let visual = chartLayout.lanes.map(\.channel).filter {
            BmsONEStatus.rubberBandKind(channel: $0, mode: bmsonViewMode) == band.kind
        }
        let hovered = chartLayout.lane(at: point)?.channel
        let current = BmsONEStatus.clampedRubberBandChannel(
            current: hovered.flatMap { channel in
                visual.contains(where: { $0.caseInsensitiveCompare(channel) == .orderedSame })
                    ? channel
                    : nil
            },
            visualOrder: visual,
            pointX: point.x,
            frames: chartLayout.laneFrames
        ) ?? band.originChannel
        let channels = BmsONEStatus.rubberBandChannels(
            origin: band.originChannel,
            current: current,
            visualOrder: visual
        )
        bmsonCursor = BmsONECursor(
            pulse: Int64(times.cursor),
            channel: nil,
            writeMode: false,
            inMeasureArea: false,
            hitLength: nil,
            rangeBegin: Int64(times.begin),
            rangeEnd: Int64(times.end)
        )
        bmsonRubberBandRect = rubberBandRect(begin: times.begin, end: times.end, channels: channels)
    }

    private func commitBmsonRubberBand(at point: CGPoint, shift: Bool) {
        guard let band = bmsonRubberBand else { return }
        updateBmsonRubberBand(at: point)
        let rawTime = chartLayout.beat(atY: point.y) * Double(max(1, bmsonResolution))
        let times = BmsONEStatus.rubberBandTimes(
            origin: band.originPulse,
            time: rawTime,
            snapToGrid: snapEnabled,
            snapSelection: bmsonSnapSelectionInEdit,
            bars: bmsonBarPulses,
            resolution: bmsonResolution,
            fineGrid: bmsonFineGrid
        )
        let visual = chartLayout.lanes.map(\.channel).filter {
            BmsONEStatus.rubberBandKind(channel: $0, mode: bmsonViewMode) == band.kind
        }
        let hovered = chartLayout.lane(at: point)?.channel
        let current = BmsONEStatus.clampedRubberBandChannel(
            current: hovered.flatMap { channel in
                visual.contains(where: { $0.caseInsensitiveCompare(channel) == .orderedSame })
                    ? channel
                    : nil
            },
            visualOrder: visual,
            pointX: point.x,
            frames: chartLayout.laneFrames
        ) ?? band.originChannel
        let channels = Set(
            BmsONEStatus.rubberBandChannels(
                origin: band.originChannel,
                current: current,
                visualOrder: visual
            ).map { $0.uppercased() }
        )
        let pairedLines = Set(longNotes.notes.flatMap { [$0.start.sourceLine, $0.end.sourceLine] })
        var events = selectedEvents
        if let selectedEvent { events.insert(selectedEvent) }
        var longs = selectedLongNotes
        if let selectedLongNote { longs.insert(selectedLongNote) }
        if band.kind != .bpm {
            for note in longNotes.notes {
                let display = ChartLayout.displayChannel(note.channel).uppercased()
                guard channels.contains(display) else { continue }
                let start = BmsonChartMapping.pulse(beat: note.start.beat, resolution: bmsonResolution)
                let end = BmsonChartMapping.pulse(beat: note.end.beat, resolution: bmsonResolution)
                guard BmsONEStatus.containsNote(
                    location: start,
                    length: max(0, end - start),
                    begin: times.begin,
                    end: times.end
                ) else { continue }
                if shift {
                    if longs.contains(note) {
                        longs.remove(note)
                    } else {
                        longs.insert(note)
                    }
                } else {
                    longs.insert(note)
                }
            }
        }
        for event in snapshot.events {
            let display = ChartLayout.displayChannel(event.channel).uppercased()
            guard channels.contains(display) else { continue }
            if pairedLines.contains(event.sourceLine) { continue }
            let pulse = BmsonChartMapping.pulse(beat: event.beat, resolution: bmsonResolution)
            let included: Bool
            if band.kind == .bpm {
                included = BmsONEStatus.containsEvent(location: pulse, begin: times.begin, end: times.end)
            } else {
                included = BmsONEStatus.containsNote(location: pulse, length: 0, begin: times.begin, end: times.end)
            }
            guard included else { continue }
            if shift {
                if events.contains(event) {
                    events.remove(event)
                } else {
                    events.insert(event)
                }
            } else {
                events.insert(event)
            }
        }
        applySelection(events: events, longNotes: longs)
    }

    private func rubberBandRect(begin: Int, end: Int, channels: [String]) -> CGRect? {
        let frames = channels.compactMap { chartLayout.laneFrames[$0] }
        guard let first = frames.first else { return nil }
        let left = frames.map(\.minX).min() ?? first.minX
        let right = frames.map(\.maxX).max() ?? first.maxX
        let resolution = Double(max(1, bmsonResolution))
        let y0 = chartLayout.y(forBeat: Double(begin) / resolution)
        let y1 = chartLayout.y(forBeat: Double(end) / resolution)
        let minY = min(y0, y1)
        let maxY = max(y0, y1)
        return CGRect(x: left, y: minY, width: max(1, right - left), height: max(1, maxY - minY))
    }

    func bmsonRubberBandFrame() -> CGRect? {
        guard didDrag else { return nil }
        if bmsonRubberBand != nil {
            return bmsonRubberBandRect
        }
        if bmsMarqueeOrigin != nil {
            return bmsMarqueeRect
        }
        return nil
    }

    private func selectNotes(in selection: TimeSelection) {
        guard tool == .timeSelect else { return }
        let events = Set(snapshot.events.filter {
            LegacyTimeSelection.contains(
                vPosition: TimeSelection.vPosition(beat: $0.beat),
                selection: selection,
                ntInput: ntInputEnabled
            )
        })
        let longNotes = Set(self.longNotes.notes.filter {
            LegacyTimeSelection.contains(
                vPosition: TimeSelection.vPosition(beat: $0.start.beat),
                length: TimeSelection.vPosition(beat: $0.end.beat) - TimeSelection.vPosition(beat: $0.start.beat),
                selection: selection,
                ntInput: ntInputEnabled
            )
        })
        selectedEvents = events
        selectedLongNotes = longNotes
        selectedEvent = events.count == 1 && longNotes.isEmpty ? events.first : nil
        selectedLongNote = longNotes.count == 1 && events.isEmpty ? longNotes.first : nil
        snapshotDidChange?(selectedEvent)
    }

    func applyEditorSettings(_ settings: EditorSettings) {
        wheelStep = CGFloat(settings.wheelStep)
        pageStep = CGFloat(settings.pageStep)
        focusOnMouseEnter = settings.mouseEnterFocus
        disableFirstClick = settings.firstClickDisabled
        stopPreviewOnClick = settings.stopPreviewOnClick
        middleButtonMoveMethod = settings.middleButtonMoveMethod
    }

    private func refreshTrackingArea() {
        if let tracking {
            removeTrackingArea(tracking)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseDown(with event: NSEvent) {
        if stopMiddleAutoScrollIfActive() {
            return
        }
        onBecomeActive?()
        let wasFirstResponder = window?.firstResponder === self
        window?.makeFirstResponder(self)
        if disableFirstClick && !wasFirstResponder {
            return
        }
        let view = viewPoint(for: event)
        lastViewMouse = view
        lastViewMouseX = view.x
        suppressNextMouseUp = false
        if handleMiniMapMouseDown(at: view) {
            return
        }
        if stopPreviewOnClick {
            chartClicked?()
        }
        let point = chartPoint(for: event)
        if handleMasterLaneMouseDown(at: point) {
            return
        }
        if !activateSoundChannelLaneIfNeeded(at: point) {
            return
        }
        lastPointerBeat = TimeSelection.beat(vPosition: resolvedVPosition(at: point, snap: snapEnabled).value)
        // 原版先 PanelPreviewNoteIndex，再按当前模式处理点击。
        previewClickedNote(at: point)
        // `OnSelectModeLeftClick`：`Clicks = 2` 在 Ctrl / Shift 之前，带 Control 仍改标签。
        if tool == .select, event.clickCount >= 2, handleSelectDoubleClick(at: point) {
            cancelDrag()
            return
        }
        if event.modifierFlags.contains(.control) {
            let shift = event.modifierFlags.contains(.shift)
            if tool == .select {
                handleSelectModifierClick(at: point, shift: shift)
                if chartLayout.hitTest(point) == nil && chartLayout.hitTestLongNote(point) == nil {
                    beginSelectRubberBand(at: point)
                }
                return
            }
            if tool == .write {
                if writesBmsonContinue {
                    writeShortNote(at: point, continueFlag: BmsonWriteContinue.flag(shiftHeld: shift))
                } else {
                    writeShortNote(at: point, hidden: !shift, mine: shift)
                }
                return
            }
            unsupportedGesture?("Hidden and mine note modifiers are not available in this editor yet.")
            return
        }
        if tryEditBmsonBarLine(at: point, event: event, remove: false) {
            return
        }
        switch tool {
        case .timeSelect:
            beginTimeSelection(at: point, modifiers: event.modifierFlags)
        case .write:
            if event.modifierFlags.contains(.shift) || ntInputEnabled {
                beginWriteGesture(at: point, continueFlag: writeContinueFlag(from: event))
                return
            }
            writeShortNote(at: point, continueFlag: writeContinueFlag(from: event))
        case .longNote:
            beginLongWrite(at: point, continueFlag: writeContinueFlag(from: event))
        case .select:
            if let hit = chartLayout.hitTestLongNote(point) {
                if !isSelected(hit.note) {
                    selectedEvent = nil
                    selectedEvents = []
                    selectedLongNotes = []
                    selectedLongNote = hit.note
                }
                dragSource = nil
                let anchorOffset: CGFloat
                if let rect = chartLayout.longNoteRect(hit.note) {
                    switch hit.part {
                    case .startCap:
                        anchorOffset = rect.startCap.maxY - point.y
                    case .endCap:
                        anchorOffset = rect.endCap.maxY - point.y
                    case .body:
                        anchorOffset = rect.startCap.maxY - point.y
                    }
                } else {
                    anchorOffset = 0
                }
                longDrag = LongNoteDrag(
                    note: hit.note,
                    part: hit.part,
                    startPoint: point,
                    anchorOffsetY: anchorOffset
                )
            } else if let hit = chartLayout.hitTest(point) {
                if !isSelected(hit) {
                    selectedLongNote = nil
                    selectedLongNotes = []
                    selectedEvents = []
                    selectedEvent = hit
                }
                dragSource = hit
                longDrag = nil
                if let rect = chartLayout.eventRect(hit)?.rect {
                    dragAnchorOffsetY = rect.maxY - point.y
                }
            } else {
                selectedLongNote = nil
                selectedLongNotes = []
                selectedEvents = []
                selectedEvent = nil
                dragSource = nil
                longDrag = nil
                beginSelectRubberBand(at: point)
            }
            dragStartPoint = point
            didDrag = false
            snapshotDidChange?(selectedEvent)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let view = viewPoint(for: event)
        lastViewMouse = view
        lastViewMouseX = view.x
        if handleMiniMapMouseDragged(at: view) {
            return
        }
        let point = chartPoint(for: event)
        if tool == .timeSelect, let timeDragLine {
            let snap = snapEnabled && !event.modifierFlags.contains(.control)
            let resolved = resolvedVPosition(at: point, snap: snap)
            applyTimeSelection(LegacyTimeSelection.drag(
                to: resolved.value,
                snapped: snap ? resolved.value : nil,
                current: timeSelection,
                line: timeDragLine,
                noteVPosition: resolved.note
            ))
            updatePointerState(at: point)
            return
        }
        guard let dragStartPoint else { return }
        didDrag = ChartInput.isDrag(from: dragStartPoint, to: point)
        refreshSelectDragPresentation(at: point)
        updatePointerState(at: point)
    }

    override func mouseMoved(with event: NSEvent) {
        let view = viewPoint(for: event)
        lastViewMouse = view
        let wasShowing = currentMiniMapFrame() != nil
        lastViewMouseX = view.x
        if (currentMiniMapFrame() != nil) != wasShowing {
            rebuildGeometry()
        }
        updatePointerState(at: chartPoint(for: event))
    }

    override func mouseExited(with event: NSEvent) {
        let wasHoveringLane = hoverLaneChannel != nil
        let wasShowing = currentMiniMapFrame() != nil
        lastViewMouseX = 0
        if wasShowing && !miniMapPinned {
            rebuildGeometry()
        }
        hoverEvent = nil
        hoverLongNote = nil
        hoverLaneChannel = nil
        statusPointerInside = false
        statusHasColumn = false
        statusHoverVPosition = 0
        statusHoverColumnTitle = ""
        statusHoverValue = 0
        statusHoverLength = 0
        statusHoverHidden = false
        statusHoverNumeric = false
        statusHoverLongNote = false
        statusWriteLength = 0
        if bmsonRubberBand != nil {
            rebuildGeometry()
            hoverDidChange?()
            super.mouseExited(with: event)
            return
        }
        bmsonCursor = nil
        if let beat = previewPlayheadBeat {
            applyPlayheadLine(beat: beat)
        } else {
            mouseGuideY = nil
        }
        timeHoverLine = .none
        hoverUsesEndPen = false
        if wasHoveringLane {
            rebuildGeometry()
        } else {
            labels.needsDisplay = true
        }
        hoverDidChange?()
        super.mouseExited(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if miniMapDrag != nil {
            miniMapDrag = nil
            return
        }
        defer { cancelDrag() }
        if suppressNextMouseUp {
            suppressNextMouseUp = false
            return
        }
        if tool == .timeSelect {
            commitTimeStretchIfNeeded()
        }
        let point = chartPoint(for: event)
        if let pendingLongWrite {
            if didDrag, ntInputEnabled || tool == .longNote {
                commitLongWrite(pendingLongWrite, at: point)
            } else if !didDrag {
                writeShortNote(at: pendingLongWrite.startPoint, continueFlag: pendingLongWrite.continueFlag)
            }
            return
        }
        if tool == .select, !didDrag {
            commitCtrlToggleIfNeeded()
            return
        }
        if bmsonRubberBand != nil {
            if didDrag {
                commitBmsonRubberBand(at: point, shift: event.modifierFlags.contains(.shift))
            }
            bmsonRubberBand = nil
            bmsonRubberBandRect = nil
            updatePointerState(at: point)
            return
        }
        if bmsMarqueeOrigin != nil {
            if didDrag {
                updateBmsMarquee(to: point)
                commitBmsMarquee(shift: event.modifierFlags.contains(.shift))
            }
            bmsMarqueeOrigin = nil
            bmsMarqueeRect = nil
            updatePointerState(at: point)
            return
        }
        guard tool == .select, didDrag else { return }
        if pendingCtrlToggleEvent != nil || pendingCtrlToggleLong != nil {
            commitCtrlCopyIfNeeded(at: point)
            return
        }
        if let longDrag, longDrag.part != .body {
            commitLongDrag(longDrag, at: point)
            return
        }
        guard snapshot.editable else { return }
        let anchorOffset: CGFloat
        if let longDrag, longDrag.part == .body {
            anchorOffset = longDrag.anchorOffsetY
        } else {
            anchorOffset = dragAnchorOffsetY
        }
        let anchorPoint = ChartInput.pointForAnchor(from: point, anchorOffsetY: anchorOffset)
        if moveBatchAtVPositionRequested != nil,
           dragSource != nil || longDrag?.part == .body {
            if let plan = selectMovePlan(at: anchorPoint) {
                guard moveBatchAtVPositionRequested?(plan.shorts, plan.longs) == true else { return }
                selectCopiedNotes(plan)
            }
            return
        }
        guard let source = dragSource else {
            if let longDrag {
                commitLongDrag(longDrag, at: point)
            }
            return
        }
        guard let lane = chartLayout.lane(at: anchorPoint), lane.editable else { return }
        let sourceLinesBeforeMove = Set(snapshot.events.map(\.sourceLine))
        let moved: Bool
        let destinationMeasure: ChartMeasureSnapshot
        if appliesBmsonSnap {
            let pulse = disableVerticalMove
                ? BmsonChartMapping.pulse(beat: source.beat, resolution: bmsonResolution)
                : bmsonWritePulse(at: anchorPoint, snap: snapEnabled)
            moved = moveAtPulseRequested?(source, lane.channel, pulse) == true
            destinationMeasure = chartLayout.measure(at: anchorPoint)
                ?? ChartMeasureSnapshot(measure: source.measure, start: source.beat, length: 4)
        } else {
            guard let target = snapTarget(at: anchorPoint, lockingBeat: source.beat) else { return }
            moved = moveRequested?(source, lane.channel, target.measure, target.slot) == true
            destinationMeasure = target.measure
        }
        guard moved else { return }
        if let movedEvent = ChartSelection.movedEvent(
            from: source,
            toMeasure: destinationMeasure,
            channel: lane.channel,
            excludingSourceLines: sourceLinesBeforeMove,
            in: snapshot
        ) {
            selectedEvent = movedEvent
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 122 {
            timeSelectKeyRequested?(.timeSelect)
            return
        }
        if event.keyCode == 120 {
            timeSelectKeyRequested?(.select)
            return
        }
        if event.keyCode == 99 {
            timeSelectKeyRequested?(.write)
            return
        }
        if event.keyCode == 0,
           !event.modifierFlags.contains(.command),
           event.modifierFlags.contains(.control),
           event.modifierFlags.contains(.shift) {
            if (tool == .select || tool == .timeSelect),
               LegacyLabelMatch.hoverASelects(
                   control: true,
                   shift: true,
                   command: false,
                   hasHover: hasHoverNote
               ) {
                addSelectionMatchingCurrentHover()
            }
            return
        }
        if let action = LegacyCtrlEdit.action(
            keyCode: event.keyCode,
            control: event.modifierFlags.contains(.control),
            shift: event.modifierFlags.contains(.shift),
            option: event.modifierFlags.contains(.option),
            command: event.modifierFlags.contains(.command)
        ) {
            ctrlEditRequested?(action)
            return
        }
        if event.keyCode == 5 && !event.modifierFlags.contains(.command) {
            toggleSnapRequested?()
            return
        }
        if event.keyCode == 2 && !event.modifierFlags.contains(.command) {
            toggleDisableVerticalMoveRequested?()
            return
        }
        if event.keyCode == 43 && !event.modifierFlags.contains(.command) {
            doubleDivisionRequested?()
            return
        }
        if event.keyCode == 47 && !event.modifierFlags.contains(.command) {
            halfDivisionRequested?()
            return
        }
        if event.keyCode == 44 && !event.modifierFlags.contains(.command) {
            applySlashDivisionRequested?()
            return
        }
        if !event.modifierFlags.contains(.command),
           let digit = LegacyMoveNotes.digit(fromKeyCode: event.keyCode) {
            moveDigitRequested?(digit, event.modifierFlags.contains(.shift))
            return
        }
        if !event.modifierFlags.contains(.command),
           let direction = LegacyArrowMove.direction(fromKeyCode: event.keyCode) {
            moveArrowRequested?(direction, event.modifierFlags.contains(.control))
            return
        }
        if event.keyCode == 24 && !event.modifierFlags.contains(.command) {
            heightNudgeRequested?(true)
            return
        }
        if event.keyCode == 27 && !event.modifierFlags.contains(.command) {
            heightNudgeRequested?(false)
            return
        }
        if event.keyCode == 69 && !event.modifierFlags.contains(.command) {
            wavStepRequested?(1)
            return
        }
        if event.keyCode == 78 && !event.modifierFlags.contains(.command) {
            wavStepRequested?(-1)
            return
        }
        if !event.modifierFlags.contains(.command),
           let shortcut = ChartConvert.convertShortcut(fromKeyCode: event.keyCode) {
            convertShortcutRequested?(shortcut)
            return
        }
        if event.keyCode == 53 {
            suppressNextMouseUp = dragStartPoint != nil
            cancelDrag()
            rebuildGeometry()
            hoverDidChange?()
            return
        }
        if event.keyCode == 115 && !event.modifierFlags.contains(.command) {
            let maxOffset = Double(max(0, chartLayout.contentSize.height - bounds.height))
            setOffset(CGPoint(x: offset.x, y: LegacyPanelScroll.homeOffsetY(maxOffset: maxOffset)))
            return
        }
        if event.keyCode == 119 && !event.modifierFlags.contains(.command) {
            let maxOffset = Double(max(0, chartLayout.contentSize.height - bounds.height))
            setOffset(CGPoint(x: offset.x, y: LegacyPanelScroll.endOffsetY(maxOffset: maxOffset)))
            return
        }
        if event.keyCode == 116 {
            setOffset(CGPoint(x: offset.x, y: offset.y - pageStep))
            return
        }
        if event.keyCode == 121 {
            setOffset(CGPoint(x: offset.x, y: offset.y + pageStep))
            return
        }
        if event.keyCode == 51 || event.keyCode == 117 {
            let items = selectedChartItems()
            if longNotes.editable {
                for note in items.longNotes {
                    eraseLongNoteRequested?(note)
                }
            }
            if snapshot.editable {
                for event in items.events {
                    eraseRequested?(event)
                }
            }
            if !items.longNotes.isEmpty || !items.events.isEmpty { return }
        }
        super.keyDown(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
        // 按住 Ctrl+Shift 时立刻重画同标签悬停框，不用再挪鼠标。
        rebuildGeometry()
        hoverDidChange?()
        super.flagsChanged(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return }
        if stopMiddleAutoScrollIfActive() {
            return
        }
        window?.makeFirstResponder(self)
        let viewPoint = convert(event.locationInWindow, from: nil)
        if middleButtonMoveMethod == 1 {
            middleDragging = true
            middleDragOrigin = viewPoint
            middleDragStartOffset = offset
        } else {
            middleAutoScrolling = true
            middleOriginScreen = NSEvent.mouseLocation
            startMiddleTimer()
        }
    }

    override func otherMouseDragged(with event: NSEvent) {
        guard middleDragging else { return }
        let viewPoint = convert(event.locationInWindow, from: nil)
        setOffset(LegacyMiddleButton.dragOffset(
            current: viewPoint,
            origin: middleDragOrigin,
            startOffset: middleDragStartOffset,
            gxHeight: gxHeight,
            gxWidth: gxWidth
        ))
    }

    override func otherMouseUp(with event: NSEvent) {
        if middleDragging {
            middleDragging = false
        }
        if middleAutoScrolling {
            let current = NSEvent.mouseLocation
            if LegacyMiddleButton.shouldReleaseAutoScroll(
                deltaX: middleOriginScreen.x - current.x,
                deltaY: middleOriginScreen.y - current.y,
                threshold: middleDeltaRelease
            ) {
                stopMiddleAutoScroll()
            }
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        if stopMiddleAutoScrollIfActive() {
            return
        }
        if tryEditBmsonBarLine(at: chartPoint(for: event), event: event, remove: true) {
            return
        }
        handleRightClickNote(with: event)
    }

    /// 对照 `DeselectOrRemove`。只动点中的那一颗。带 Control 不当成删音。
    private func handleRightClickNote(with event: NSEvent) {
        let control = event.modifierFlags.contains(.control)
        let shift = event.modifierFlags.contains(.shift)
        let point = chartPoint(for: event)
        let longHit = chartLayout.hitTestLongNote(point)
        let shortHit = longHit == nil ? chartLayout.hitTest(point) : nil
        let hitNote = longHit != nil || shortHit != nil
        switch LegacyWavList.rightClickNoteAction(shift: shift, control: control, hitNote: hitNote) {
        case .ignore:
            if control {
                mouseDown(with: event)
            } else {
                super.rightMouseDown(with: event)
            }
        case .selectWav:
            let channel: String
            let token: String
            if let long = longHit {
                channel = long.note.channel
                token = long.note.start.token
            } else if let short = shortHit {
                channel = short.channel
                token = short.token
            } else {
                return
            }
            wavSelectRequested?(
                LegacyWavList.rightClickWavSlot(
                    valueDiv10000: LegacyWavList.rightClickValueDiv10000(channel: channel, token: token)
                )
            )
        case .remove:
            if let long = longHit {
                eraseLongNoteRequested?(long.note)
            } else if let short = shortHit {
                eraseRequested?(short)
            }
        }
    }

    override func scrollWheel(with event: NSEvent) {
        _ = stopMiddleAutoScrollIfActive()
        if event.modifierFlags.contains(.control) {
            let request = ChartZoomWheelEvent(
                notches: ChartZoom.wheelNotches(
                    scrollingDeltaY: event.scrollingDeltaY,
                    precise: event.hasPreciseScrollingDeltas
                ),
                pixelDeltaY: event.scrollingDeltaY,
                hasPrecisePixels: event.hasPreciseScrollingDeltas
            )
            if request.hasPrecisePixels ? request.pixelDeltaY != 0 : request.notches != 0 {
                zoomWheelRequested?(request)
            }
            return
        }
        if event.hasPreciseScrollingDeltas {
            applyWheelScroll(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY)
            return
        }
        let vertical = event.scrollingDeltaY == 0 ? 0 : (event.scrollingDeltaY > 0 ? wheelStep : -wheelStep)
        let horizontal = event.scrollingDeltaX == 0 ? 0 : (event.scrollingDeltaX > 0 ? wheelStep : -wheelStep)
        applyWheelScroll(deltaX: horizontal, deltaY: vertical)
    }

    private func applyWheelScroll(deltaX: CGFloat, deltaY: CGFloat) {
        setOffset(CGPoint(x: offset.x - deltaX, y: offset.y - deltaY))
        guard let dragStartPoint, tool == .select else { return }
        let point = chartPoint(forView: lastViewMouse)
        didDrag = ChartInput.isDrag(from: dragStartPoint, to: point)
        refreshSelectDragPresentation(at: point)
        updatePointerState(at: point)
    }

    @discardableResult
    private func stopMiddleAutoScrollIfActive() -> Bool {
        guard middleAutoScrolling else { return false }
        stopMiddleAutoScroll()
        return true
    }

    private func stopMiddleAutoScroll() {
        middleAutoScrolling = false
        middleTimer?.invalidate()
        middleTimer = nil
    }

    private func startMiddleTimer() {
        middleTimer?.invalidate()
        let interval = TimeInterval(LegacyMiddleButton.timerIntervalMilliseconds) / 1000
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickMiddleAutoScroll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        middleTimer = timer
    }

    private func tickMiddleAutoScroll() {
        guard middleAutoScrolling else {
            stopMiddleAutoScroll()
            return
        }
        let delta = LegacyMiddleButton.autoScrollDeltaFromCocoaScreen(
            current: NSEvent.mouseLocation,
            origin: middleOriginScreen,
            gxHeight: gxHeight,
            gxWidth: gxWidth
        )
        setOffset(CGPoint(x: offset.x + delta.x, y: offset.y + delta.y))
    }

    private func configureMetalView() {
        metalView.translatesAutoresizingMaskIntoConstraints = false
        metalView.clearColor = MTLClearColor(red: 0.025, green: 0.03, blue: 0.045, alpha: 1)
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.enableSetNeedsDisplay = true
        metalView.isPaused = true
        metalView.delegate = renderer
    }

    private func viewPoint(for event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    private func chartPoint(for event: NSEvent) -> CGPoint {
        let local = viewPoint(for: event)
        return CGPoint(x: local.x + offset.x, y: local.y + offset.y)
    }

    private func handleMiniMapMouseDown(at view: CGPoint) -> Bool {
        guard let frame = currentMiniMapFrame(), frame.contains(view) else { return false }
        let height = max(Int(frame.height.rounded(.towardZero)), 1)
        let viewLength = masterWaveform?.viewLength
            ?? BmsONEMasterView.viewLength(actualLength: 0, resolution: max(bmsonResolution, 1))
        let zoom = BmsONEMasterView.zoomY(
            pixelsPerQuarterBeat: pixelsPerQuarterBeat,
            resolution: max(masterWaveform?.resolution ?? bmsonResolution, 1)
        )
        let bar = currentMiniMapViewportBar()
        let y = Int((view.y - frame.minY).rounded(.towardZero))
        if y < bar.yEnd || y >= bar.yBegin {
            let dy = y - (bar.yEnd + bar.yBegin) / 2
            let ds = BmsONEMasterView.miniMapScrollDelta(
                dy: dy,
                zoomY: zoom,
                viewLength: viewLength,
                height: height
            )
            setOffset(CGPoint(x: offset.x, y: offset.y + CGFloat(ds)))
        }
        miniMapDrag = (originY: view.y, originOffsetY: offset.y)
        return true
    }

    private func handleMiniMapMouseDragged(at view: CGPoint) -> Bool {
        guard let drag = miniMapDrag else { return false }
        let height = max(Int(bounds.height.rounded(.towardZero)), 1)
        let viewLength = masterWaveform?.viewLength
            ?? BmsONEMasterView.viewLength(actualLength: 0, resolution: max(bmsonResolution, 1))
        let zoom = BmsONEMasterView.zoomY(
            pixelsPerQuarterBeat: pixelsPerQuarterBeat,
            resolution: max(masterWaveform?.resolution ?? bmsonResolution, 1)
        )
        let dy = Int((view.y - drag.originY).rounded(.towardZero))
        let ds = BmsONEMasterView.miniMapScrollDelta(
            dy: dy,
            zoomY: zoom,
            viewLength: viewLength,
            height: height
        )
        setOffset(CGPoint(x: offset.x, y: drag.originOffsetY + CGFloat(ds)))
        return true
    }

    private func handleMasterLaneMouseDown(at point: CGPoint) -> Bool {
        guard chartLayout.isMasterLane(point) else { return false }
        let beat = max(0, chartLayout.beat(atY: point.y))
        lastPointerBeat = beat
        masterLanePreviewRequested?(beat)
        return true
    }

    private func visibleCenterBeat() -> Double {
        guard chartLayout.contentSize.height > 0, pixelsPerQuarterBeat > 0 else { return 0 }
        return Double((chartLayout.contentSize.height - offset.y - bounds.height / 2) / pixelsPerQuarterBeat)
    }

    private func rebind(_ event: ChartEventSnapshot?, in snapshot: ChartSnapshot) -> ChartEventSnapshot? {
        guard let event else { return nil }
        return snapshot.events.first {
            $0.measure == event.measure && $0.channel == event.channel
                && $0.fractionNumerator == event.fractionNumerator
                && $0.fractionDenominator == event.fractionDenominator
        }
    }

    private func rebind(_ note: LongNoteSnapshot?, in snapshot: LongNoteSnapshotSet) -> LongNoteSnapshot? {
        guard let note else { return nil }
        return snapshot.notes.first {
            $0.channel == note.channel
                && $0.start.measure == note.start.measure
                && $0.start.fractionNumerator == note.start.fractionNumerator
                && $0.start.fractionDenominator == note.start.fractionDenominator
                && $0.end.measure == note.end.measure
                && $0.end.fractionNumerator == note.end.fractionNumerator
                && $0.end.fractionDenominator == note.end.fractionDenominator
        }
    }

    private func beginTimeSelection(at point: CGPoint, modifiers: NSEvent.ModifierFlags) {
        let snap = snapEnabled && !modifiers.contains(.control)
        let resolved = resolvedVPosition(at: point, snap: snap)
        let lines = timeSelectionLineYs()
        let pointerY = point.y
        let threshold = CGFloat(theme.visual.timeSelectionDeltaMouseOver)
        let line = lines.map {
            LegacyTimeSelection.hitLine(
                pointerY: pointerY,
                startY: $0.start,
                halfY: $0.half,
                endY: $0.end,
                threshold: threshold
            )
        } ?? .none
        // 原版 vSelAdjust 在按下时按 Shift 锁住。先记下当时的选区，松手再写谱。
        // 拖动过程只改线，不每帧重建谱。
        if modifiers.contains(.shift), line != .none {
            timeStretchOrigin = timeSelection
        } else {
            timeStretchOrigin = nil
        }
        timeDragLine = line
        timeHoverLine = line
        dragStartPoint = point
        applyTimeSelection(LegacyTimeSelection.begin(
            at: resolved.value,
            snapped: snap ? resolved.value : nil,
            current: timeSelection,
            line: line
        ))
        updatePointerState(at: point)
    }

    private func commitTimeStretchIfNeeded() {
        // 松手时不再看 Shift：原版用按下时的 vSelAdjust，中途松开 Shift 仍会写回。
        guard let origin = timeStretchOrigin,
              let line = timeDragLine,
              line != .none
        else { return }
        switch line {
        case .half:
            let delta = timeSelection.halfPosition - origin.halfPosition
            timeSelectionCommandRequested?(.stretchHalf(delta: delta))
        case .start, .end:
            guard origin.length != 0 else { return }
            timeSelectionCommandRequested?(.expand(ratio: timeSelection.length / origin.length))
        case .none:
            break
        }
    }

    private struct HoverOutlineKey: Equatable {
        var token: String
        var channel: String
        var beat: Double
        var longNote: Bool
        var endPen: Bool
        var multiselect: Bool
    }

    private func hoverOutlineKey() -> HoverOutlineKey? {
        let flags = NSEvent.modifierFlags
        let multiselect = LegacyLabelMatch.modifierMultiselectActive(
            control: flags.contains(.control),
            shift: flags.contains(.shift)
        )
        if let note = hoverLongNote {
            return HoverOutlineKey(
                token: note.start.token,
                channel: note.channel,
                beat: note.start.beat,
                longNote: true,
                endPen: hoverUsesEndPen,
                multiselect: multiselect
            )
        }
        if let event = hoverEvent {
            return HoverOutlineKey(
                token: event.token,
                channel: event.channel,
                beat: event.beat,
                longNote: false,
                endPen: false,
                multiselect: multiselect
            )
        }
        return nil
    }

    private struct PendingLongStartKey: Equatable {
        var channel: String
        var measure: Int
        var slot: Int
    }

    private func pendingLongStartKey() -> PendingLongStartKey? {
        guard let pending = pendingLongWrite else { return nil }
        return PendingLongStartKey(
            channel: pending.channel,
            measure: pending.target.measure.measure,
            slot: pending.target.slot
        )
    }

    private func updatePointerState(at point: CGPoint) {
        let previousLane = hoverLaneChannel
        let previousGuide = mouseGuideY
        let previousHover = hoverOutlineKey()
        let previousTimeHover = timeHoverLine
        let previousCursor = bmsonCursor
        let previousPending = pendingLongStartKey()
        let previousMove = movePreview
        hoverLaneChannel = chartLayout.lane(at: point)?.channel
        updateBmsonCursor(at: point)
        let snapped = resolvedVPosition(at: point, snap: snapEnabled)
        lastPointerBeat = TimeSelection.beat(vPosition: snapped.value)
        refreshLegacyStatusPointer(at: point, mouseVPosition: snapped.value)
        if let beat = previewPlayheadBeat {
            applyPlayheadLine(beat: beat)
        } else {
            mouseGuideY = LegacyTimeSelection.lineY(
                vPosition: snapped.value,
                contentHeight: chartLayout.contentSize.height,
                pixelsPerQuarterBeat: pixelsPerQuarterBeat
            )
        }
        if tool == .select || tool == .timeSelect {
            if let longNote = chartLayout.hitTestLongNote(point) {
                hoverLongNote = longNote.note
                hoverEvent = nil
                hoverUsesEndPen = longNote.part != .body
            } else {
                hoverLongNote = nil
                hoverEvent = chartLayout.hitTest(point)
                hoverUsesEndPen = false
            }
        } else {
            hoverEvent = nil
            hoverLongNote = nil
            hoverUsesEndPen = false
        }
        if tool == .timeSelect, let lines = timeSelectionLineYs() {
            timeHoverLine = LegacyTimeSelection.hitLine(
                pointerY: point.y,
                startY: lines.start,
                halfY: lines.half,
                endY: lines.end,
                threshold: CGFloat(theme.visual.timeSelectionDeltaMouseOver)
            )
        } else {
            timeHoverLine = .none
        }
        let laneChanged = previousLane != hoverLaneChannel
        let hoverChanged = hoverOutlineKey() != previousHover
        let pendingChanged = pendingLongStartKey() != previousPending
        let moveChanged = movePreview?.shorts != previousMove?.shorts
            || movePreview?.longs != previousMove?.longs
        let indicatorChanged = mouseGuideY != previousGuide
            || timeHoverLine != previousTimeHover
            || bmsonCursor != previousCursor
        // 列底色属于 Metal 静态层，只在跨列时重建。空白处微移不重画文字。
        if laneChanged {
            rebuildGeometry()
        } else if hoverChanged || pendingChanged || moveChanged || indicatorChanged {
            labels.needsDisplay = true
        }
        hoverDidChange?()
    }

    private func refreshLegacyStatusPointer(at point: CGPoint, mouseVPosition: Double) {
        statusPointerInside = true
        statusMouseVPosition = mouseVPosition
        if let lane = chartLayout.lane(at: point) {
            statusColumnTitle = lane.title
            statusHasColumn = true
        } else if chartLayout.isMeasureArea(point) {
            statusColumnTitle = theme.column(at: 0)?.title ?? "Measure"
            statusHasColumn = true
        } else {
            statusColumnTitle = ""
            statusHasColumn = false
        }
        if let longNote = chartLayout.hitTestLongNote(point) {
            let vpos = TimeSelection.vPosition(beat: longNote.note.start.beat)
            statusHoverVPosition = vpos
            statusHoverColumnTitle = statusColumnTitle(for: longNote.note.channel)
            statusHoverValue = statusNoteValue(
                channel: longNote.note.channel,
                token: longNote.note.start.token,
                vPosition: vpos
            )
            statusHoverLength = max(
                0,
                TimeSelection.vPosition(beat: longNote.note.end.beat) - vpos
            )
            statusHoverHidden = LegacyMyO2.isChannelHidden(longNote.note.channel)
            statusHoverNumeric = ChartConvert.isNumericChannel(longNote.note.channel)
            statusHoverLongNote = true
            statusWriteLength = statusHoverLength
        } else if let event = chartLayout.hitTest(point) {
            let vpos = TimeSelection.vPosition(beat: event.beat)
            statusHoverVPosition = vpos
            statusHoverColumnTitle = statusColumnTitle(for: event.channel)
            statusHoverValue = statusNoteValue(channel: event.channel, token: event.token, vPosition: vpos)
            statusHoverLength = 0
            statusHoverHidden = event.kind == "hiddenNote" || LegacyMyO2.isChannelHidden(event.channel)
            statusHoverNumeric = ChartConvert.isNumericChannel(event.channel)
            statusHoverLongNote = ChartConvert.isLongChannel(event.channel)
            statusWriteLength = 0
        } else {
            statusHoverVPosition = mouseVPosition
            statusHoverColumnTitle = statusColumnTitle
            statusHoverValue = 0
            statusHoverLength = 0
            statusHoverHidden = false
            statusHoverNumeric = false
            statusHoverLongNote = false
            statusWriteLength = 0
        }
        if let pending = pendingLongWrite, didDrag {
            let start = TimeSelection.vPosition(beat: pending.target.measure.start)
                + Double(pending.target.slot) * 4.0 / Double(max(1, chartLayout.division)) * 48
            statusWriteLength = abs(mouseVPosition - start)
        }
    }

    private func statusColumnTitle(for channel: String) -> String {
        let display = chartLayout.displayChannel(for: channel)
        if let lane = chartLayout.lanes.first(where: { $0.channel == display }) {
            return lane.title
        }
        if ChartBGM.lane(display: display) != nil {
            return display
        }
        return theme.columns.first { $0.title == display }?.title ?? display
    }

    private func statusNoteValue(channel: String, token: String, vPosition: Double) -> Double {
        let upper = channel.uppercased()
        if upper == "03", let hex = Int(token, radix: 16) {
            return Double(hex) * 10_000
        }
        if upper == "08", let bpm = bpmEvents.first(where: { abs($0.vPosition - vPosition) < 0.000_001 }) {
            return bpm.value * 10_000
        }
        if upper == "09", let stop = stopEvents.first(where: { abs($0.vPosition - vPosition) < 0.000_001 }) {
            return stop.value * 10_000
        }
        return Double(BMS36Token.decode(token)) * 10_000
    }

    /// 原版 `PanelPreviewNoteIndex`：点中发声列上的音符才预听。
    private func previewClickedNote(at point: CGPoint) {
        guard previewOnClick else { return }
        let token: String
        let channel: String
        if let hit = chartLayout.hitTestLongNote(point) {
            token = hit.note.start.token
            channel = hit.note.channel
        } else if let event = chartLayout.hitTest(point) {
            token = event.token
            channel = event.channel
        } else {
            return
        }
        guard LegacyPreviewAudio.isAudibleChannel(channel) else { return }
        previewNoteRequested?(token)
    }

    private func writeContinueFlag(from event: NSEvent) -> Bool {
        writesBmsonContinue ? BmsonWriteContinue.flag(shiftHeld: event.modifierFlags.contains(.shift)) : false
    }

    private func beginWriteGesture(at point: CGPoint, continueFlag: Bool) {
        guard snapshot.editable else {
            unsupportedGesture?(snapshot.editingReason)
            return
        }
        guard chartLayout.lane(at: point) != nil else { return }
        if !appliesBmsonSnap, chartLayout.snapTarget(at: point) == nil { return }
        if longNotes.editable {
            beginLongWrite(at: point, continueFlag: continueFlag)
            return
        }
        dragStartPoint = point
        didDrag = false
        pendingLongWrite = nil
        writeShortNote(at: point, continueFlag: continueFlag)
    }

    /// 对照 `WriteModeContext::MeasureArea_MousePress`。Qt 在 macOS 上把 Ctrl 换成 Command。
    @discardableResult
    private func tryEditBmsonBarLine(at point: CGPoint, event: NSEvent, remove: Bool) -> Bool {
        guard barLineEditRequested != nil else { return false }
        guard tool == .write, event.modifierFlags.contains(.command) else { return false }
        guard chartLayout.isMeasureArea(point) else { return false }
        let snap = snapEnabled
        let resolved = resolvedVPosition(at: point, snap: snap)
        var beat = TimeSelection.beat(vPosition: resolved.value)
        if !event.modifierFlags.contains(.option) {
            beat = absorbedBarBeat(at: point, snapped: beat)
        }
        _ = barLineEditRequested?(beat, remove)
        return true
    }

    /// 上一根线在点击上方 16 像素以内时吸过去。对照 `Time2Y(i.key()) - 16`。
    private func absorbedBarBeat(at point: CGPoint, snapped: Double) -> Double {
        let starts = snapshot.measures.map(\.start).filter { $0 <= snapped }.sorted()
        guard let previous = starts.last else { return snapped }
        if chartLayout.y(forBeat: previous) - 16 <= point.y {
            return previous
        }
        return snapped
    }

    private func writeShortNote(
        at point: CGPoint,
        hidden: Bool = false,
        mine: Bool = false,
        continueFlag: Bool = false
    ) {
        guard snapshot.editable else {
            unsupportedGesture?(snapshot.editingReason)
            return
        }
        guard let lane = chartLayout.lane(at: point), lane.editable else { return }
        if !activateSoundChannelLaneIfNeeded(at: point) {
            return
        }
        let channel = ChartWriteChannel.source(display: lane.channel, hidden: hidden, mine: mine)
        if appliesBmsonSnap {
            writeAtPulseRequested?(channel, bmsonWritePulse(at: point, snap: snapEnabled), continueFlag)
            return
        }
        guard let target = chartLayout.snapTarget(at: point) else { return }
        writeRequested?(
            channel,
            target.measure,
            target.slot,
            continueFlag
        )
    }

    private func beginLongWrite(at point: CGPoint, continueFlag: Bool) {
        guard snapshot.editable, longNotes.editable else {
            unsupportedGesture?(longNotes.editingReason.isEmpty ? snapshot.editingReason : longNotes.editingReason)
            return
        }
        guard let lane = chartLayout.lane(at: point), lane.editable else { return }
        if BmsonSoundLane.index(display: lane.channel) != nil {
            writeShortNote(at: point, continueFlag: continueFlag)
            return
        }
        guard let target = chartLayout.snapTarget(at: point) else { return }
        pendingLongWrite = PendingLongWrite(
            channel: sourceLongChannel(for: lane.channel),
            target: target,
            startPoint: point,
            continueFlag: continueFlag
        )
        dragStartPoint = point
        didDrag = false
    }

    private func commitLongWrite(_ pending: PendingLongWrite, at point: CGPoint) {
        guard didDrag,
              let lane = chartLayout.lane(at: point),
              chartLayout.displayChannel(for: pending.channel) == lane.channel
        else { return }
        if appliesBmsonSnap {
            let startPulse = bmsonWritePulse(at: pending.startPoint, snap: snapEnabled)
            let endPulse = bmsonWritePulse(at: point, snap: snapEnabled)
            guard startPulse != endPulse else {
                unsupportedGesture?("Drag to a different grid position to create a long note.")
                return
            }
            let sourceLines = longSourceLines()
            guard insertLongAtPulseRequested?(
                pending.channel,
                min(startPulse, endPulse),
                max(startPulse, endPulse),
                pending.continueFlag
            ) == true else {
                return
            }
            selectedLongNote = newlyCreatedLongNote(
                channel: pending.channel,
                excluding: sourceLines
            )
            selectedEvent = nil
            return
        }
        guard let release = chartLayout.snapTarget(at: point) else { return }
        let start: (measure: ChartMeasureSnapshot, slot: Int)
        let end: (measure: ChartMeasureSnapshot, slot: Int)
        if chartLayout.anchorY(for: pending.target) > chartLayout.anchorY(for: release) {
            start = pending.target
            end = release
        } else {
            start = release
            end = pending.target
        }
        guard chartLayout.anchorY(for: start) != chartLayout.anchorY(for: end) else {
            unsupportedGesture?("Drag to a different grid position to create a long note.")
            return
        }
        let sourceLines = longSourceLines()
        guard insertLongNoteRequested?(
            pending.channel,
            start.measure,
            start.slot,
            end.measure,
            end.slot,
            longNotes.lnobjToken.isEmpty,
            pending.continueFlag
        ) == true else {
            return
        }
        selectedLongNote = newlyCreatedLongNote(
            channel: pending.channel,
            excluding: sourceLines
        )
        selectedEvent = nil
    }

    private func commitLongDrag(_ drag: LongNoteDrag, at point: CGPoint) {
        guard longNotes.editable else {
            unsupportedGesture?(longNotes.editingReason)
            return
        }
        if drag.part != .body {
            guard let beats = endpointBeats(for: drag, at: point),
                  beats.end - beats.start > 0.000_001 else {
                return
            }
        }
        let anchorPoint = ChartInput.pointForAnchor(from: point, anchorOffsetY: drag.anchorOffsetY)
        let lockBeat = drag.part == .body ? drag.note.start.beat : nil
        let sourceLines = longSourceLines()
        let succeeded: Bool
        if appliesBmsonSnap {
            let pulse: Int64
            if drag.part == .body, disableVerticalMove {
                pulse = BmsonChartMapping.pulse(beat: drag.note.start.beat, resolution: bmsonResolution)
            } else {
                pulse = bmsonWritePulse(at: anchorPoint, snap: snapEnabled)
            }
            switch drag.part {
            case .body:
                guard let lane = chartLayout.lane(at: anchorPoint) else { return }
                succeeded = moveLongAtPulseRequested?(
                    drag.note,
                    sourceLongChannel(for: lane.channel),
                    pulse
                ) == true
            case .startCap:
                succeeded = moveLongStartAtPulseRequested?(drag.note, pulse) == true
            case .endCap:
                succeeded = resizeLongAtPulseRequested?(drag.note, pulse) == true
            }
        } else {
            guard let target = snapTarget(at: anchorPoint, lockingBeat: lockBeat) else { return }
            switch drag.part {
            case .body:
                guard let lane = chartLayout.lane(at: anchorPoint) else { return }
                succeeded = moveLongNoteRequested?(
                    drag.note,
                    sourceLongChannel(for: lane.channel),
                    target.measure,
                    target.slot
                ) == true
            case .startCap:
                succeeded = moveLongNoteStartRequested?(drag.note, target.measure, target.slot) == true
            case .endCap:
                succeeded = resizeLongNoteRequested?(drag.note, target.measure, target.slot) == true
            }
        }
        guard succeeded else { return }
        selectedLongNote = updatedLongNote(drag.note, part: drag.part, excluding: sourceLines)
            ?? rebind(drag.note, in: longNotes)
        selectedEvent = nil
    }

    private func longSourceLines() -> Set<Int> {
        Set(longNotes.notes.flatMap { [$0.start.sourceLine, $0.end.sourceLine] })
    }

    private func newlyCreatedLongNote(channel: String, excluding sourceLines: Set<Int>) -> LongNoteSnapshot? {
        longNotes.notes.last {
            $0.channel == channel
                && !sourceLines.contains($0.start.sourceLine)
                && !sourceLines.contains($0.end.sourceLine)
        }
    }

    private func updatedLongNote(
        _ prior: LongNoteSnapshot,
        part: LongNoteHitPart,
        excluding sourceLines: Set<Int>
    ) -> LongNoteSnapshot? {
        longNotes.notes.last { candidate in
            switch part {
            case .body:
                return !sourceLines.contains(candidate.start.sourceLine)
                    && !sourceLines.contains(candidate.end.sourceLine)
                    && candidate.start.token == prior.start.token
                    && candidate.end.token == prior.end.token
            case .startCap:
                return !sourceLines.contains(candidate.start.sourceLine)
                    && candidate.end.sourceLine == prior.end.sourceLine
                    && candidate.end.token == prior.end.token
            case .endCap:
                return candidate.start.sourceLine == prior.start.sourceLine
                    && !sourceLines.contains(candidate.end.sourceLine)
                    && candidate.start.token == prior.start.token
            }
        }
    }

    private func sourceLongChannel(for displayChannel: String) -> String {
        guard longNotes.lnobjToken.isEmpty, displayChannel.count == 2 else { return displayChannel }
        let characters = Array(displayChannel)
        switch characters[0] {
        case "1": return "5\(characters[1])"
        case "2": return "6\(characters[1])"
        default: return displayChannel
        }
    }

    private func boundedOffset(_ proposed: CGPoint) -> CGPoint {
        let maximumX = max(0, chartLayout.contentSize.width - bounds.width)
        let maximumY = max(0, chartLayout.contentSize.height - bounds.height)
        return CGPoint(x: max(0, min(proposed.x, maximumX)), y: max(0, min(proposed.y, maximumY)))
    }

    private func rebuildGeometry() {
        guard !geometryRebuildScheduled else { return }
        geometryRebuildScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.geometryRebuildScheduled = false
            self.performGeometryRebuild()
        }
    }

    private func performGeometryRebuild() {
        viewport = CGRect(origin: offset, size: bounds.size)
        guard viewport.width > 0, viewport.height > 0 else { return }
        guard hasMetalRenderer, let device = metalView.device else {
            labels.needsDisplay = true
            return
        }

        let geometry = visibleGeometry()
        renderer?.replaceGeometry(
            geometry.quads,
            gradients: geometry.gradients,
            overlays: geometry.overlays,
            viewport: bounds.size,
            device: device
        )
        metalView.setNeedsDisplay(metalView.bounds)
        labels.needsDisplay = true
    }

    private func metalBaseColors(for event: ChartEventSnapshot) -> ThemeGradientColors {
        if event.kind == "mine" {
            return ThemeGradientColors(bright: ThemeColor(argb: 0xFFFF0000), dark: ThemeColor(argb: 0xFFFF0000))
        }
        if let lane = chartLayout.lanes.first(where: { $0.channel == chartLayout.displayChannel(for: event.channel) }) {
            return event.kind == "hiddenNote" ? lane.hiddenColors : lane.normalColors
        }
        return ThemeGradientColors(bright: ThemeColor(argb: 0xFFFF00FF), dark: ThemeColor(argb: 0xFF7F007F))
    }

    private func metalLongColors(for note: LongNoteSnapshot) -> ThemeGradientColors {
        if let lane = chartLayout.lanes.first(where: { $0.channel == chartLayout.displayChannel(for: note.channel) }) {
            return lane.longColors
        }
        return ThemeGradientColors(bright: ThemeColor(argb: 0xFFFF00FF), dark: ThemeColor(argb: 0xFF7F007F))
    }

    private func visibleGeometry() -> (
        quads: [(CGRect, NSColor)],
        gradients: [LegacyGradientPrimitive],
        overlays: [(CGRect, NSColor)]
    ) {
        var quads: [(CGRect, NSColor)] = []
        var gradients: [LegacyGradientPrimitive] = []
        var overlays: [(CGRect, NSColor)] = []
        func appendBox(_ rect: CGRect, color: NSColor) {
            overlays.append((CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 1), color))
            overlays.append((CGRect(x: rect.minX, y: rect.maxY - 1, width: rect.width, height: 1), color))
            overlays.append((CGRect(x: rect.minX, y: rect.minY, width: 1, height: rect.height), color))
            overlays.append((CGRect(x: rect.maxX - 1, y: rect.minY, width: 1, height: rect.height), color))
        }
        func appendGradient(fill: CGRect, start: CGPoint, end: CGPoint, colors: ThemeGradientColors, outline: CGRect) {
            gradients.append(LegacyGradientPrimitive(
                fill: fill.offsetBy(dx: -viewport.minX, dy: -viewport.minY),
                start: CGPoint(x: start.x - viewport.minX, y: start.y - viewport.minY),
                end: CGPoint(x: end.x - viewport.minX, y: end.y - viewport.minY),
                colors: colors
            ))
            appendBox(outline.offsetBy(dx: -viewport.minX, dy: -viewport.minY), color: colors.bright.nsColor)
        }
        for lane in chartLayout.lanes where !lane.channel.isEmpty {
            guard let frame = chartLayout.laneFrames[lane.channel] else { continue }
            let background = LegacyChartPaint.columnBackground(
                laneLeft: frame.minX - viewport.minX,
                laneWidth: frame.width,
                height: bounds.height
            )
            if chartLayout.fillsColumnBackground(lane) {
                let color = highlightsLane(lane.channel)
                    ? highlight(lane.backgroundColor)
                    : lane.backgroundColor
                quads.append((background, color))
            }
            if chartLayout.showVerticalLine {
                quads.append((
                    CGRect(x: LegacyChartPaint.columnVerticalLineX(laneLeft: frame.minX - viewport.minX), y: 0, width: 1, height: bounds.height),
                    chartLayout.theme.visual.verticalLine.nsColor
                ))
            }
        }
        let gridX = max(0, chartLayout.gridLeadingX - viewport.minX)
        for line in chartLayout.gridLines(in: viewport) {
            let rect = CGRect(
                x: gridX,
                y: line.y - viewport.minY,
                width: max(0, bounds.width - gridX),
                height: line.kind == .measure ? 1 : 0.5
            )
            quads.append((rect, color(for: line, theme: chartLayout.theme)))
        }
        appendMasterLane(to: &quads)
        appendSoundLaneWaveforms(to: &quads)
        if chartLayout.showMasterLane {
            for line in chartLayout.gridLines(in: viewport) {
                let x = chartLayout.masterLaneFrame.minX - viewport.minX
                quads.append((
                    CGRect(
                        x: x,
                        y: line.y - viewport.minY,
                        width: chartLayout.masterLaneFrame.width,
                        height: line.kind == .measure ? 1 : 0.5
                    ),
                    color(for: line, theme: chartLayout.theme)
                ))
            }
        }
        let waveformColor = chartLayout.theme.visual.bgmWaveform.nsColor
        for rect in waveformPixelRects() {
            quads.append((rect, waveformColor))
        }
        if let fill = timeSelectionFill() {
            quads.append((fill.offsetBy(dx: -viewport.minX, dy: -viewport.minY), chartLayout.theme.visual.timeSelectionSelection.nsColor))
        }
        for item in currentPresentedPaint() {
            if let note = item.shortNote {
                appendGradient(fill: note.fill, start: note.gradientStart, end: note.gradientEnd, colors: item.colors, outline: note.rect)
                if item.selected {
                    appendBox(note.selection.offsetBy(dx: -viewport.minX, dy: -viewport.minY), color: chartLayout.theme.visual.noteSelected.nsColor)
                }
            } else if let longNote = item.longNote {
                appendGradient(fill: longNote.fill, start: longNote.gradientStart, end: longNote.gradientEnd, colors: item.colors, outline: longNote.outline)
                if item.selected {
                    appendBox(longNote.selection.offsetBy(dx: -viewport.minX, dy: -viewport.minY), color: chartLayout.theme.visual.noteSelected.nsColor)
                }
            }
        }
        appendMiniMap(to: &quads)
        return (quads, gradients, overlays)
    }

    private func appendMasterLane(to quads: inout [(CGRect, NSColor)]) {
        guard chartLayout.showMasterLane else { return }
        let frame = chartLayout.masterLaneFrame
        let x = frame.minX - viewport.minX
        quads.append((
            CGRect(x: x, y: 0, width: frame.width, height: bounds.height),
            ThemeColor(argb: BmsONEMasterView.masterBackground).nsColor
        ))
        appendWaveform(
            to: &quads,
            x: x,
            width: frame.width,
            height: bounds.height,
            miniMap: false,
            opacity: 1,
            rowAtViewY: { viewY in
                masterRow(contentY: viewport.minY + CGFloat(viewY))
            }
        )
    }

    private func appendMiniMap(to quads: inout [(CGRect, NSColor)]) {
        guard let frame = currentMiniMapFrame() else { return }
        let alpha = miniMapPinned ? 1.0 : miniMapOpacity
        let background = ThemeColor(argb: BmsONEMasterView.miniMapBackground).nsColor
            .withAlphaComponent(alpha)
        quads.append((frame, background))
        let viewLength = masterWaveform?.viewLength
            ?? BmsONEMasterView.viewLength(actualLength: 0, resolution: max(bmsonResolution, 1))
        let height = max(Int(frame.height.rounded(.towardZero)), 1)
        appendWaveform(
            to: &quads,
            x: frame.minX,
            width: frame.width,
            height: frame.height,
            miniMap: true,
            opacity: alpha,
            rowAtViewY: { viewY in
                let loopY = height - 1 - viewY
                let t = BmsONEMasterView.miniMapTime(y: loopY, height: height, viewLength: viewLength)
                let t2 = BmsONEMasterView.miniMapTime(y: loopY + 1, height: height, viewLength: viewLength)
                return masterWaveform?.row(from: t, to: t2) ?? .empty
            }
        )
        let bar = currentMiniMapViewportBar()
        let barRect = CGRect(
            x: frame.minX,
            y: frame.minY + CGFloat(bar.yEnd),
            width: frame.width,
            height: max(1, CGFloat(bar.yBegin - bar.yEnd + 1))
        )
        quads.append((barRect, ThemeColor(argb: BmsONEMasterView.viewportFill).nsColor.withAlphaComponent(alpha)))
    }

    private func appendWaveform(
        to quads: inout [(CGRect, NSColor)],
        x: CGFloat,
        width: CGFloat,
        height: CGFloat,
        miniMap: Bool,
        opacity: Double,
        rowAtViewY: (Int) -> BmsONEMasterRow
    ) {
        let rows = max(Int(height.rounded(.towardZero)), 0)
        let center = x + width / 2
        let half = width / 2
        for viewY in 0..<rows {
            let row = rowAtViewY(viewY)
            let peak = ThemeColor(argb: BmsONEMasterView.peakColor(available: row.available)).nsColor
                .withAlphaComponent(opacity)
            let rms = ThemeColor(argb: BmsONEMasterView.rmsColor(available: row.available, miniMap: miniMap)).nsColor
                .withAlphaComponent(opacity)
            appendStereoLine(to: &quads, center: center, half: half, y: CGFloat(viewY), left: row.peakL, right: row.peakR, color: peak)
            appendStereoLine(to: &quads, center: center, half: half, y: CGFloat(viewY), left: row.rmsL, right: row.rmsR, color: rms)
        }
    }

    private func appendStereoLine(
        to quads: inout [(CGRect, NSColor)],
        center: CGFloat,
        half: CGFloat,
        y: CGFloat,
        left: Float,
        right: Float,
        color: NSColor
    ) {
        let leftX = center - half * CGFloat(left)
        let rightX = center + half * CGFloat(right)
        quads.append((CGRect(x: leftX, y: y, width: max(1, center - leftX), height: 1), color))
        quads.append((CGRect(x: center, y: y, width: max(1, rightX - center), height: 1), color))
    }

    private func masterRow(contentY: CGFloat) -> BmsONEMasterRow {
        guard let cache = masterWaveform else { return .empty }
        let t = Int(chartLayout.beat(atY: contentY) * Double(cache.resolution))
        let t2 = Int(chartLayout.beat(atY: contentY - 1) * Double(cache.resolution))
        return cache.row(from: t, to: t2)
    }

    func currentMiniMapFrame() -> CGRect? {
        guard showMiniMap, appliesBmsonSnap else { return nil }
        if !BmsONEMasterView.showsUnpinnedMiniMap(
            mouseX: lastViewMouseX,
            boundsWidth: bounds.width,
            pinned: miniMapPinned
        ) {
            return nil
        }
        return CGRect(
            x: bounds.width - BmsONEMasterView.miniMapWidth,
            y: 0,
            width: BmsONEMasterView.miniMapWidth,
            height: bounds.height
        )
    }

    private func currentMiniMapViewportBar() -> (yEnd: Int, yBegin: Int) {
        let viewLength = masterWaveform?.viewLength
            ?? BmsONEMasterView.viewLength(actualLength: 0, resolution: max(bmsonResolution, 1))
        let height = max(Int(bounds.height.rounded(.towardZero)), 1)
        let resolution = Double(max(masterWaveform?.resolution ?? bmsonResolution, 1))
        let tEnd = chartLayout.beat(atY: viewport.minY) * resolution
        let tBegin = chartLayout.beat(atY: viewport.minY + bounds.height) * resolution
        return BmsONEMasterView.viewportBar(
            tBegin: tBegin,
            tEnd: tEnd,
            height: height,
            viewLength: viewLength
        )
    }

    private func appendSoundLaneWaveforms(to quads: inout [(CGRect, NSColor)]) {
        guard appliesBmsonSnap, let state = laneWaveform else { return }
        let resolution = max(state.resolution, 1)
        for (index, channel) in state.channels.enumerated() {
            let name = BmsonSoundLane.displayChannel(index: index)
            guard let frame = chartLayout.laneFrames[name], frame.width > 1,
                  frame.maxX > viewport.minX, frame.minX < viewport.maxX else { continue }
            let x = frame.minX - viewport.minX
            let width = max(Int(frame.width.rounded(.towardZero)), 0)
            if state.drawsWaveform {
                let rows = max(Int(bounds.height.rounded(.towardZero)), 0)
                for viewY in 0..<rows {
                    let contentY = viewport.minY + CGFloat(viewY)
                    let ticks = chartLayout.beat(atY: contentY) * Double(resolution)
                    let nextTicks = chartLayout.beat(atY: contentY - 1) * Double(resolution)
                    guard let rms = BmsonLaneWaveform.rms(
                        ticks: ticks,
                        nextTicks: nextTicks,
                        channel: channel,
                        resolution: resolution
                    ), let span = BmsonLaneWaveform.span(
                        width: width,
                        left: rms.left,
                        right: rms.right
                    ) else {
                        continue
                    }
                    let color = ThemeColor(
                        argb: 0xFF000000 | BmsonLaneWaveform.colorSorted(notes: channel.notes, ticks: ticks)
                    ).nsColor
                    quads.append((
                        CGRect(
                            x: x + CGFloat(span.left),
                            y: CGFloat(viewY),
                            width: CGFloat(span.right - span.left),
                            height: 1
                        ),
                        color
                    ))
                }
            } else {
                let tBottom = Int(chartLayout.beat(atY: viewport.maxY) * Double(resolution))
                let tTop = Int(chartLayout.beat(atY: viewport.minY) * Double(resolution))
                let band = BmsonLaneWaveform.activityBand(width: width)
                for activity in BmsonLaneWaveform.activities(
                    cache: channel.cache,
                    notes: channel.notes,
                    tBegin: min(tBottom, tTop),
                    tEnd: max(tBottom, tTop)
                ) {
                    let y1 = chartLayout.y(forBeat: Double(activity.tBegin) / Double(resolution))
                    let y2 = chartLayout.y(forBeat: Double(activity.tEnd) / Double(resolution))
                    let top = min(y1, y2) - viewport.minY
                    let height = abs(y1 - y2)
                    let color = ThemeColor(
                        argb: 0xFF000000 | (activity.keyLane
                            ? BmsonLaneWaveform.keyColor
                            : BmsonLaneWaveform.bgmColor)
                    ).nsColor
                    quads.append((
                        CGRect(
                            x: x + CGFloat(band.left),
                            y: top,
                            width: CGFloat(band.right - band.left),
                            height: max(1, height)
                        ),
                        color
                    ))
                }
            }
        }
    }

    func drawSoundLaneWaveformFallback() {
        var quads: [(CGRect, NSColor)] = []
        appendSoundLaneWaveforms(to: &quads)
        for (rect, color) in quads {
            color.setFill()
            rect.fill()
        }
    }

    func drawMasterLaneFallback() {
        var quads: [(CGRect, NSColor)] = []
        appendMasterLane(to: &quads)
        if chartLayout.showMasterLane {
            for line in chartLayout.gridLines(in: viewport) {
                quads.append((
                    CGRect(
                        x: chartLayout.masterLaneFrame.minX - viewport.minX,
                        y: line.y - viewport.minY,
                        width: chartLayout.masterLaneFrame.width,
                        height: line.kind == .measure ? 1 : 0.5
                    ),
                    color(for: line, theme: chartLayout.theme)
                ))
            }
        }
        for (rect, color) in quads {
            color.setFill()
            rect.fill()
        }
    }

    func drawMiniMapFallback() {
        var quads: [(CGRect, NSColor)] = []
        appendMiniMap(to: &quads)
        for (rect, color) in quads {
            color.setFill()
            rect.fill()
        }
    }

    private func color(for line: ChartGridLine, theme: ChartTheme) -> NSColor {
        switch line.kind {
        case .measure: return theme.visual.measureLine.nsColor
        case .grid: return theme.visual.grid.nsColor
        case .sub: return theme.visual.subGrid.nsColor
        }
    }

    private func highlight(_ color: NSColor) -> NSColor {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        func clamp(_ value: CGFloat) -> CGFloat { min(1, max(0, value * 2)) }
        return NSColor(
            calibratedRed: clamp(rgb.redComponent),
            green: clamp(rgb.greenComponent),
            blue: clamp(rgb.blueComponent),
            alpha: clamp(rgb.alphaComponent)
        )
    }
}

private struct BmsonRubberBand {
    let kind: BmsONERubberBandKind
    let originChannel: String
    let originPulse: Int
}

private struct PendingLongWrite {
    let channel: String
    let target: (measure: ChartMeasureSnapshot, slot: Int)
    let startPoint: CGPoint
    let continueFlag: Bool
}

private struct LongNoteDrag {
    let note: LongNoteSnapshot
    let part: LongNoteHitPart
    let startPoint: CGPoint
    let anchorOffsetY: CGFloat

    init(note: LongNoteSnapshot, part: LongNoteHitPart, startPoint: CGPoint, anchorOffsetY: CGFloat) {
        self.note = note
        self.part = part
        self.startPoint = startPoint
        self.anchorOffsetY = anchorOffsetY
    }
}
