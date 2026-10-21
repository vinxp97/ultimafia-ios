import SwiftUI

/// Cross-platform helpers. iPhone/iPad/Catalyst use UIKit directly; the native macOS build maps the
/// handful of UIKit names the shared code uses onto AppKit equivalents below.
extension View {
    /// Inline navigation title on iOS; macOS windows have no large titles.
    @ViewBuilder func umInlineTitle() -> some View {
        #if os(macOS)
        self
        #else
        self.navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

extension View {
    /// Show/hide the iOS navigation bar; a no-op in Mac windows (the window toolbar stays).
    @ViewBuilder func umNavigationBar(_ visibility: Visibility) -> some View {
        #if os(macOS)
        self
        #else
        self.toolbar(visibility, for: .navigationBar)
        #endif
    }
}

#if os(macOS)
/// Lets a UIViewRepresentable-style wrapper (makeUIView/updateUIView) serve as an NSViewRepresentable.
protocol UMViewRepresentable: NSViewRepresentable {
    func makeUIView(context: Context) -> NSViewType
    func updateUIView(_ view: NSViewType, context: Context)
}
extension UMViewRepresentable {
    func makeNSView(context: Context) -> NSViewType { makeUIView(context: context) }
    func updateNSView(_ view: NSViewType, context: Context) { updateUIView(view, context: context) }
}
#else
typealias UMViewRepresentable = UIViewRepresentable
#endif

extension View {
    /// Full-screen cover on iOS; a large sheet in a Mac window.
    @ViewBuilder func umFullScreenCover<Item: Identifiable, C: View>(
        item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> C
    ) -> some View {
        #if os(macOS)
        self.sheet(item: item) { content($0).frame(minWidth: 820, idealWidth: 1000, minHeight: 620, idealHeight: 760) }
        #else
        self.fullScreenCover(item: item, content: content)
        #endif
    }
}

extension ToolbarItemPlacement {
    /// Trailing navigation-bar slot on iOS; the window toolbar's primary slot on macOS.
    static var umTrailing: ToolbarItemPlacement {
        #if os(macOS)
        .primaryAction
        #else
        .topBarTrailing
        #endif
    }
}

#if os(macOS)
import AppKit

typealias UIImage = NSImage
typealias UIColor = NSColor
extension NSColor {
    static var label: NSColor { .labelColor }
    static var secondaryLabel: NSColor { .secondaryLabelColor }
}
typealias UIFont = NSFont

nonisolated extension NSImage {
    var cgImage: CGImage? { cgImage(forProposedRect: nil, context: nil, hints: nil) }
    var scale: CGFloat { 1 }
    convenience init(cgImage: CGImage) {
        self.init(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
    convenience init?(systemName: String) {
        self.init(systemSymbolName: systemName, accessibilityDescription: nil)
    }
    private func bitmap() -> NSBitmapImageRep? { cgImage.map { NSBitmapImageRep(cgImage: $0) } }
    func pngData() -> Data? { bitmap()?.representation(using: .png, properties: [:]) }
    func jpegData(compressionQuality: CGFloat) -> Data? {
        bitmap()?.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }
}

extension NSFont {
    static func preferredFont(forTextStyle style: NSFont.TextStyle) -> NSFont {
        NSFont.preferredFont(forTextStyle: style, options: [:])
    }
    var lineHeight: CGFloat { ceil(ascender - descender + leading) }
}

extension Image {
    init(uiImage: NSImage) { self.init(nsImage: uiImage) }
}

/// Minimal UIGraphicsImageRenderer for AppKit: draws into a bitmap at `format.scale`. Drawing is
/// in an unflipped context, which matches the whole-image draws the shared code does.
nonisolated final class UIGraphicsImageRendererFormat {
    var scale: CGFloat = 2
    var opaque = false
    var preferredRange = 0
    init() {}
    static func `default`() -> UIGraphicsImageRendererFormat { UIGraphicsImageRendererFormat() }
}

nonisolated final class UIGraphicsImageRendererContext {
    let cgContext: CGContext
    init(_ context: CGContext) { cgContext = context }
    func fill(_ rect: CGRect) { cgContext.fill(rect) }
}

nonisolated final class UIGraphicsImageRenderer {
    let size: CGSize
    let format: UIGraphicsImageRendererFormat
    init(size: CGSize, format: UIGraphicsImageRendererFormat = .init()) { self.size = size; self.format = format }
    convenience init(bounds: CGRect, format: UIGraphicsImageRendererFormat = .init()) {
        self.init(size: bounds.size, format: format)
    }

    func image(actions: (UIGraphicsImageRendererContext) -> Void) -> NSImage {
        let scale = max(format.scale, 1)
        let w = max(Int((size.width * scale).rounded(.up)), 1)
        let h = max(Int((size.height * scale).rounded(.up)), 1)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return NSImage(size: size)
        }
        ctx.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        actions(UIGraphicsImageRendererContext(ctx))
        NSGraphicsContext.restoreGraphicsState()
        guard let cg = ctx.makeImage() else { return NSImage(size: size) }
        return NSImage(cgImage: cg, size: size)
    }

    func pngData(actions: (UIGraphicsImageRendererContext) -> Void) -> Data {
        image(actions: actions).pngData() ?? Data()
    }
    func jpegData(withCompressionQuality q: CGFloat, actions: (UIGraphicsImageRendererContext) -> Void) -> Data {
        image(actions: actions).jpegData(compressionQuality: q) ?? Data()
    }
}

/// Haptics don't exist on Mac: no-op.
final class UIImpactFeedbackGenerator {
    enum FeedbackStyle { case light, medium, heavy, soft, rigid }
    init(style: FeedbackStyle = .medium) {}
    func impactOccurred() {}
    func impactOccurred(intensity: CGFloat) {}
    func prepare() {}
}

/// The few UIApplication calls the shared code makes, routed to AppKit.
@MainActor
final class UIApplication {
    static let shared = UIApplication()
    enum State { case active, inactive, background }
    static let openSettingsURLString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
    static let openNotificationSettingsURLString = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
    static let didBecomeActiveNotification = NSApplication.didBecomeActiveNotification
    static let willResignActiveNotification = NSApplication.willResignActiveNotification
    static let didEnterBackgroundNotification = NSApplication.didResignActiveNotification
    static let willEnterForegroundNotification = NSApplication.willBecomeActiveNotification
    var applicationState: State { NSApp?.isActive == true ? .active : .background }
    func open(_ url: URL, options: [String: Any] = [:], completionHandler: ((Bool) -> Void)? = nil) {
        completionHandler?(NSWorkspace.shared.open(url))
    }
}

/// iOS-only text input traits: accepted and ignored on Mac.
enum UMTextInputAutocapitalization { case never, words, sentences, characters }
enum UMKeyboardType { case `default`, asciiCapable, numberPad, decimalPad, emailAddress, URL, numbersAndPunctuation, phonePad, twitter, webSearch }
extension View {
    func textInputAutocapitalization(_ value: UMTextInputAutocapitalization?) -> some View { self }
    func keyboardType(_ value: UMKeyboardType) -> some View { self }
}

enum UIPasteboard {
    static let general = UMPasteboard()
}
final class UMPasteboard {
    var string: String? {
        get { NSPasteboard.general.string(forType: .string) }
        set {
            NSPasteboard.general.clearContents()
            if let newValue { NSPasteboard.general.setString(newValue, forType: .string) }
        }
    }
}
#endif

enum UMPlatformInfo {
    #if os(macOS) || targetEnvironment(macCatalyst)
    static let isMac = true
    #else
    static let isMac = false
    #endif
}
