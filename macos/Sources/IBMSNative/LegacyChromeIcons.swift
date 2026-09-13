import AppKit

@MainActor
enum LegacyChromeIcons {
    static func image(named name: String) -> NSImage? {
        let bundle = Bundle.main
        if let url = bundle.url(forResource: name, withExtension: "png", subdirectory: "LegacyChrome"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: image.size.width, height: image.size.height)
            image.isTemplate = false
            return image
        }
        if let image = NSImage(named: name) {
            return image
        }
        return nil
    }
}

@MainActor
enum LegacyChromeFont {
    static let segoe = NSFont.systemFont(ofSize: MainWindowChrome.segoeUINinePointPixels)
    static let segoeBold = NSFont.systemFont(ofSize: MainWindowChrome.segoeUINinePointPixels, weight: .semibold)
    static let list = NSFont.monospacedSystemFont(ofSize: MainWindowChrome.segoeUINinePointPixels, weight: .regular)
}
