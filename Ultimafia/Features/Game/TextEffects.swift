import SwiftUI

/// Advanced Text Effects (site PR #3090): `/wave hello` etc. The server strips the command and,
/// only for owners of the shop item, sends the message with `textEffect`; `content` stays plain.
/// Each effect plays once when the message first appears, then the text is normal. Old history
/// (over 30 s), reviews, re-shown rows and Reduce Motion show plain text.
nonisolated enum UMTextEffect: String, CaseIterable, Sendable {
    case wave, shake, glow, rainbow, slide, flash

    /// Server copy (shared/textEffects.js TEXT_EFFECTS).
    var summary: String {
        switch self {
        case .wave: "Each letter bounces once, in a wave."
        case .shake: "The message jitters briefly."
        case .glow: "The message pulses with a soft glow once."
        case .rainbow: "Colours sweep across the message once."
        case .slide: "The message slides in from the side."
        case .flash: "The message blinks twice."
        }
    }

    var icon: String {
        switch self {
        case .wave: "water.waves"
        case .shake: "waveform.path"
        case .glow: "sun.max"
        case .rainbow: "rainbow"
        case .slide: "arrow.right.to.line"
        case .flash: "bolt"
        }
    }

    var perLetter: Bool { self == .wave || self == .rainbow }

    /// Longest the effect can run (per-letter effects stagger up to 40 letters).
    var duration: Double {
        switch self {
        case .wave: 0.6 + 40 * 0.04
        case .rainbow: 0.9 + 40 * 0.03
        case .shake: 0.45
        case .glow: 1.2
        case .slide: 0.4
        case .flash: 0.9
        }
    }

    /// shared/textEffects.js parseTextEffect: `/name` or `/name text` (case-insensitive);
    /// nil when the draft is not a text-effect command (so /role etc. keep working).
    static func parse(_ content: String) -> (effect: UMTextEffect, text: String)? {
        guard content.hasPrefix("/") else { return nil }
        let body = content.dropFirst()
        let name = body.prefix { $0.isLetter && $0.isASCII }
        guard !name.isEmpty else { return nil }
        let rest = body.dropFirst(name.count)
        if let first = rest.first, !first.isWhitespace { return nil }
        guard let effect = UMTextEffect(rawValue: name.lowercased()) else { return nil }
        return (effect, rest.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static let freshWindow: TimeInterval = 30
}

/// Whether the signed-in user owns the shop item (GET user/info itemsOwned.textEffects); only
/// used to offer the commands in the slash bar. The server decides who gets an effect.
@MainActor
enum UMTextEffects {
    static var owned = false

    static func update(from user: UserInfo?) {
        let items = user?.itemsOwned?.asAny as? [String: Any] ?? [:]
        let v = items["textEffects"]
        owned = (v as? Double ?? 0) > 0 || (v as? Int ?? 0) > 0 || (v as? Bool ?? false)
    }

    /// First time each message id was drawn. An effect runs from then, so a row that is rebuilt
    /// mid-animation carries on and one shown again later is plain.
    private static var firstSeen: [String: Date] = [:]

    static func start(for line: ChatLine, now: Date = Date()) -> (UMTextEffect, Date)? {
        guard let raw = line.textEffect, let effect = UMTextEffect(rawValue: raw) else { return nil }
        guard now.timeIntervalSince(line.time) < UMTextEffect.freshWindow else { return nil }
        let start: Date
        if let seen = firstSeen[line.id] {
            start = seen
        } else {
            start = now
            firstSeen[line.id] = now
            if firstSeen.count > 500, let oldest = firstSeen.min(by: { $0.value < $1.value })?.key {
                firstSeen[oldest] = nil
            }
        }
        guard now.timeIntervalSince(start) < effect.duration + 0.1 else { return nil }
        return (effect, start)
    }
}

/// Per-letter progress read by EmoteText's text runs (wave, rainbow).
struct UMTextEffectFrame: Equatable {
    var effect: UMTextEffect
    var elapsed: Double
}

extension EnvironmentValues {
    @Entry var umTextEffectFrame: UMTextEffectFrame? = nil
}

/// Wave / rainbow, one glyph at a time (CSS: --te-i stagger, capped at 40 letters).
struct UMTextEffectRenderer: TextRenderer, Animatable {
    var frame: UMTextEffectFrame

    var animatableData: Double {
        get { frame.elapsed }
        set { frame.elapsed = newValue }
    }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        var index = 0
        for line in layout {
            for run in line {
                for glyph in run {
                    var copy = ctx
                    let i = Double(min(index, 40))
                    switch frame.effect {
                    case .wave:
                        let t = (frame.elapsed - i * 0.04) / 0.6
                        let em = glyph.typographicBounds.rect.height
                        copy.translateBy(x: 0, y: Self.waveOffset(t) * em)
                    case .rainbow:
                        let t = (frame.elapsed - i * 0.03) / 0.9
                        if t > 0, t < 1 { copy.addFilter(.colorMultiply(Self.rainbow(t))) }
                    default:
                        break
                    }
                    copy.draw(glyph)
                    index += 1
                }
            }
        }
    }

    /// te-wave: 0 → -0.35em at 40% → +0.05em at 70% → 0 (ease-out pieces).
    static func waveOffset(_ t: Double) -> Double {
        guard t > 0, t < 1 else { return 0 }
        func lerp(_ a: Double, _ b: Double, _ p: Double) -> Double { a + (b - a) * (1 - pow(1 - p, 2)) }
        if t < 0.4 { return lerp(0, -0.35, t / 0.4) }
        if t < 0.7 { return lerp(-0.35, 0.05, (t - 0.4) / 0.3) }
        return lerp(0.05, 0, (t - 0.7) / 0.3)
    }

    /// te-rainbow keyframes: red, gold, green, blue, purple, sweeping through once.
    static func rainbow(_ t: Double) -> Color {
        let stops: [Double] = [0, 45, 120, 200, 280]
        let p = min(max(t, 0), 0.9999) * Double(stops.count - 1)
        let k = Int(p)
        let hue = (stops[k] + (stops[min(k + 1, stops.count - 1)] - stops[k]) * (p - Double(k))) / 360
        return Color(hue: hue, saturation: 0.8, brightness: 1)
    }
}

/// Plays a message's effect once. Whole-message effects transform the row; per-letter ones pass a
/// frame down to EmoteText. Plain when there is no effect, it has finished, or Reduce Motion is on.
struct UMTextEffectModifier: ViewModifier {
    var line: ChatLine
    var enabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var active: (UMTextEffect, Date)?
    @State private var finished = false

    func body(content: Content) -> some View {
        if let (effect, start) = active, !finished, !reduceMotion {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSince(start)
                content
                    .environment(\.umTextEffectFrame, effect.perLetter ? UMTextEffectFrame(effect: effect, elapsed: t) : nil)
                    .offset(x: Self.offsetX(effect, t))
                    .opacity(Self.opacity(effect, t))
                    .shadow(color: Color(red: 1, green: 0.84, blue: 0.47).opacity(0.8 * Self.glow(effect, t)),
                            radius: 8 * Self.glow(effect, t))
            }
            .task {
                let left = effect.duration - Date().timeIntervalSince(start)
                if left > 0 { try? await Task.sleep(for: .seconds(left)) }
                finished = true
            }
        } else {
            content
                .onAppear {
                    guard enabled, active == nil, !finished, !reduceMotion else { return }
                    active = UMTextEffects.start(for: line)
                }
        }
    }

    static func offsetX(_ e: UMTextEffect, _ t: Double) -> CGFloat {
        switch e {
        case .shake:
            // te-shake: 0,-2,2,-2,2,-1,1,0 px over 0.45 s.
            let p = t / 0.45
            guard p > 0, p < 1 else { return 0 }
            let keys: [Double] = [0, -2, 2, -2, 2, -1, 1, 0]
            let stops: [Double] = [0, 0.15, 0.30, 0.45, 0.60, 0.75, 0.90, 1]
            for k in 1..<stops.count where p <= stops[k] {
                let f = (p - stops[k - 1]) / (stops[k] - stops[k - 1])
                return CGFloat(keys[k - 1] + (keys[k] - keys[k - 1]) * f)
            }
            return 0
        case .slide:
            // te-slide: from -1.5em, ease-out over 0.4 s.
            let p = min(max(t / 0.4, 0), 1)
            return CGFloat(-24 * pow(1 - p, 2))
        default:
            return 0
        }
    }

    static func opacity(_ e: UMTextEffect, _ t: Double) -> Double {
        switch e {
        case .slide:
            return min(max(t / 0.4, 0), 1)
        case .flash:
            // te-flash steps: blinks twice over 0.9 s.
            let p = t / 0.9
            if p < 0.15 || p >= 0.75 { return 1 }
            if p < 0.35 { return 0.15 }
            if p < 0.55 { return 1 }
            return 0.15
        default:
            return 1
        }
    }

    static func glow(_ e: UMTextEffect, _ t: Double) -> Double {
        guard e == .glow else { return 0 }
        let p = t / 1.2
        guard p > 0, p < 1 else { return 0 }
        return p < 0.45 ? p / 0.45 : (1 - p) / 0.55
    }
}

extension View {
    func umTextEffect(_ line: ChatLine, enabled: Bool) -> some View {
        modifier(UMTextEffectModifier(line: line, enabled: enabled && line.textEffect != nil))
    }
}
