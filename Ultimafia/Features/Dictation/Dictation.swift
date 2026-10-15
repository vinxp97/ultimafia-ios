import Foundation
import SwiftUI
import Speech
import AVFoundation
import QuartzCore
#if canImport(UIKit)
import UIKit
#endif

/// Chat dictation: on-device DictationTranscriber (SpeechAnalyzer), boosted with per-game contextual
/// strings (players, then setup roles, then terms; Apple caps these at ~100) and a static custom
/// language model (catalog roles, game terms, slash commands, templates) prepared once per app
/// version. Text streams into the composer and is never sent automatically.

/// Read from the audio queue and game sound code, so it lives outside the main actor.
nonisolated enum UMDictationAudio {
    nonisolated(unsafe) static var active = false
}

// MARK: - Vocabulary

struct DictationVocab: Equatable {
    var players: [String] = []
    var roles: [String] = []

    nonisolated static let terms = ["no lynch", "claim", "vote", "unvote", "lynch", "mafia", "village", "town",
                        "scum", "night kill", "whisper", "hammer", "confirmed", "self vote", "role block"]

    /// Tagged contextual strings in priority order, at most 100 phrases in total.
    var tagged: [(AnalysisContext.ContextualStringsTag, [String])] {
        var left = 100
        func take(_ xs: [String]) -> [String] {
            let t = Array(DictationVocab.unique(xs).prefix(max(left, 0)))
            left -= t.count
            return t
        }
        let p = take(players), r = take(roles), t = take(Self.terms)
        return [(.init("players"), p), (.init("roles"), r), (.init("terms"), t)]
    }

    nonisolated static func unique(_ xs: [String]) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for x in xs {
            let t = x.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, seen.insert(t.lowercased()).inserted else { continue }
            out.append(t)
        }
        return out
    }
}

// MARK: - Static custom language model

nonisolated enum UMSpeechLM {
    static let locale = Locale(identifier: "en_US")
    static let commands = ["vote", "unvote", "whisper", "shoot", "kick", "ban", "extend", "cry"]
    private static let versionKey = "um.dictation.lmVersion"
    static let prepMsKey = "um.dictation.lmPrepMs"
    /// You > Chat > Dictation. Off by default, per device.
    static let enabledKey = "um.dictationEnabled"
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    private nonisolated(unsafe) static var task: Task<Void, Never>?

    static var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "0")-\(info?["CFBundleVersion"] as? String ?? "0")"
    }
    static var dir: URL {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UMSpeechLM", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static var configuration: SFSpeechLanguageModel.Configuration {
        SFSpeechLanguageModel.Configuration(languageModel: dir.appendingPathComponent("lm.bin"),
                                            vocabulary: dir.appendingPathComponent("vocab.bin"))
    }
    static var isReady: Bool {
        UserDefaults.standard.string(forKey: versionKey) == version
            && FileManager.default.fileExists(atPath: dir.appendingPathComponent("lm.bin").path)
    }
    static var lastPrepMs: Int? { UserDefaults.standard.object(forKey: prepMsKey) as? Int }

    /// Once per app version, in the background, after the role catalog has loaded.
    @MainActor
    static func prepareIfNeeded() {
        guard isEnabled, !isReady, task == nil, RoleCatalog.shared.isReady else { return }
        let roles = RoleCatalog.shared.allRoleNames()
        guard !roles.isEmpty else { return }
        task = Task.detached(priority: .utility) {
            let t0 = CACurrentMediaTime()
            do {
                try await build(roles: roles)
                let ms = Int((CACurrentMediaTime() - t0) * 1000)
                UserDefaults.standard.set(version, forKey: versionKey)
                UserDefaults.standard.set(ms, forKey: prepMsKey)
                UMDiag.log("dictation", "custom LM prepared in \(ms)ms (\(roles.count) roles, v\(version))")
            } catch {
                UMDiag.log("dictation", "custom LM failed after \(Int((CACurrentMediaTime() - t0) * 1000))ms: \(error)")
            }
            task = nil
        }
    }

    private static func build(roles: [String]) async throws {
        let data = SFCustomLanguageModelData(locale: locale, identifier: "com.ultimafia.dictation", version: version)
        for t in DictationVocab.terms { data.insert(phraseCount: .init(phrase: t, count: 200)) }
        for p in ["vote no lynch", "I vote no lynch", "no lynch today", "who do we lynch", "what do you claim",
                  "claim please", "I'm town", "I'm not mafia", "unvote", "vote for", "I'm voting"] {
            data.insert(phraseCount: .init(phrase: p, count: 150))
        }
        for r in roles { data.insert(phraseCount: .init(phrase: r, count: 40)) }
        for c in commands {
            data.insert(phraseCount: .init(phrase: "slash \(c)", count: 150))
        }
        let gen = SFCustomLanguageModelData.TemplatePhraseCountGenerator()
        gen.define(className: "role", values: roles)
        gen.define(className: "cmd", values: commands)
        for (t, n) in [("I claim <role>", 300), ("I'm <role>", 200), ("I am the <role>", 200), ("claiming <role>", 150),
                       ("they claimed <role>", 150), ("is the <role>", 150), ("we have a <role>", 100),
                       ("slash <cmd>", 200), ("vote <role>", 50)] {
            gen.insert(template: t, count: n)
        }
        data.insert(phraseCountGenerator: gen)
        let asset = dir.appendingPathComponent("training.bin")
        try await data.export(to: asset)
        try await SFSpeechLanguageModel.prepareCustomLanguageModel(for: asset, configuration: configuration)
    }
}

// MARK: - Post-transcription fixes

enum DictationFixer {
    private static let stop: Set<String> = ["the", "and", "you", "are", "for", "not", "but", "this", "that", "with",
        "have", "what", "who", "was", "him", "her", "his", "she", "they", "them", "then", "than", "just", "like",
        "vote", "claim", "lynch", "town", "mafia", "kill", "dead", "role", "game", "yes", "no", "out", "all", "any",
        "can", "did", "does", "here", "there", "will", "would", "should", "could", "about", "from", "your", "mine"]

    static func fix(_ raw: String, players: [String], roles: [String]) -> String {
        var s = raw
        var isCommand = false
        if let r = s.range(of: #"^\s*(?:forward\s+)?slash\s+([A-Za-z]+)[.,!?]?"#, options: [.regularExpression, .caseInsensitive]) {
            let word = s[r].split(separator: " ").last.map { String($0).lowercased().trimmingCharacters(in: .punctuationCharacters) } ?? ""
            if let cmd = UMSpeechLM.commands.first(where: { $0 == word || distance($0, word) <= 1 && word.count >= 4 }) {
                s.replaceSubrange(r, with: "/" + cmd)
                isCommand = true
            }
        }
        s = replace(in: s, candidates: players, threshold: 0.75, fuzzy: true)
        s = replace(in: s, candidates: roles, threshold: 0.85, fuzzy: false)
        if isCommand {
            s = s.trimmingCharacters(in: .whitespaces)
            while let last = s.last, ".!?".contains(last) { s.removeLast() }
            if let r = s.range(of: #"^/vote\s+(no\s*lynch|no\s*one|nobody)$"#, options: [.regularExpression, .caseInsensitive]) {
                s.replaceSubrange(r, with: "/vote nl")
            }
            // Commands take bare names: drop commas the transcriber added after the command/name.
            if let space = s.firstIndex(of: " ") {
                s = String(s[..<space]) + s[space...].replacingOccurrences(of: ",", with: "")
            }
        }
        return s
    }

    private static func norm(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    /// Windows of 1–3 words matched against candidates (spaces/punctuation ignored), longest first.
    private static func replace(in text: String, candidates: [String], threshold: Double, fuzzy: Bool) -> String {
        let cands = DictationVocab.unique(candidates).map { ($0, norm($0)) }.filter { !$0.1.isEmpty }
        guard !cands.isEmpty else { return text }
        let words = wordRanges(text)
        var used = [Bool](repeating: false, count: words.count)
        var edits: [(Range<String.Index>, String)] = []
        for n in stride(from: 3, through: 1, by: -1) where words.count >= n {
            for i in 0...(words.count - n) where !used[i..<(i + n)].contains(true) {
                let span = words[i].lowerBound..<words[i + n - 1].upperBound
                let key = norm(String(text[span]))
                guard key.count >= 2 else { continue }
                var best: (String, Double)?
                for (name, k) in cands {
                    let score: Double
                    if k == key { score = 1 }
                    else if fuzzy, key.count >= 4, k.count >= 4, !(n == 1 && stop.contains(key)),
                            k.first == key.first || phonetic(k) == phonetic(key) {
                        score = 1 - Double(distance(k, key)) / Double(max(k.count, key.count))
                    } else { continue }
                    if score >= threshold, score > (best?.1 ?? 0) { best = (name, score) }
                }
                guard let (name, _) = best else { continue }
                if String(text[span]) == name { for j in i..<(i + n) { used[j] = true }; continue }
                // Multi-word windows only when they collapse to the exact (spaceless) name.
                if n > 1, norm(name) != key, !name.contains(" ") { continue }
                edits.append((span, name))
                for j in i..<(i + n) { used[j] = true }
            }
        }
        var out = text
        for (r, name) in edits.sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) { out.replaceSubrange(r, with: name) }
        return out
    }

    private static func wordRanges(_ s: String) -> [Range<String.Index>] {
        var out: [Range<String.Index>] = []
        var start: String.Index?
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            let isWord = c.isLetter || c.isNumber || c == "_" || c == "'"
            if isWord, start == nil { start = i }
            if !isWord, let st = start { out.append(st..<i); start = nil }
            i = s.index(after: i)
        }
        if let st = start { out.append(st..<s.endIndex) }
        return out
    }

    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count), cur = prev
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }

    /// Crude sound-alike key: first letter + consonant classes, vowels and repeats dropped.
    private static func phonetic(_ s: String) -> String {
        let map: [Character: Character] = ["b": "1", "f": "1", "p": "1", "v": "1", "c": "2", "g": "2", "j": "2", "k": "2",
                                           "q": "2", "s": "2", "x": "2", "z": "2", "d": "3", "t": "3", "l": "4",
                                           "m": "5", "n": "5", "r": "6"]
        var out = ""
        var last: Character?
        for c in s {
            guard let m = map[c] else { last = nil; continue }
            if m != last { out.append(m) }
            last = m
        }
        return out
    }
}

// MARK: - Recorder

@MainActor @Observable
final class UMDictation {
    static let shared = UMDictation()

    enum Phase: Equatable { case idle, preparing(Double), recording, denied }
    private(set) var phase: Phase = .idle
    private(set) var owner: UUID?
    private(set) var startedAt = Date()

    var isRecording: Bool { phase == .recording }

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var analyzer: SpeechAnalyzer?
    @ObservationIgnored private var input: AsyncStream<AnalyzerInput>.Continuation?
    @ObservationIgnored private var resultsTask: Task<Void, Never>?
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var lastChange = Date()
    @ObservationIgnored private var vocab = DictationVocab()
    @ObservationIgnored private var base = ""
    @ObservationIgnored private var finalized = ""
    @ObservationIgnored private var volatile = ""
    @ObservationIgnored private var apply: ((String) -> Void)?
    @ObservationIgnored private var stopping = false

    static let maxSeconds: TimeInterval = 60
    static let silenceAfterSpeech: TimeInterval = 2.5
    static let silenceBeforeSpeech: TimeInterval = 6

    func toggle(owner id: UUID, current: String, vocab: DictationVocab, apply: @escaping (String) -> Void) {
        if owner != nil, phase != .idle, phase != .denied {
            if owner == id { stop() }
            return
        }
        Task { await start(owner: id, current: current, vocab: vocab, apply: apply) }
    }

    func updateVocab(_ v: DictationVocab) {
        guard v != vocab else { return }
        vocab = v
        guard let analyzer else { return }
        let ctx = Self.context(v)
        Task { try? await analyzer.setContext(ctx) }
    }

    func clearDenied() { if phase == .denied { phase = .idle; owner = nil } }

    private static func context(_ v: DictationVocab) -> AnalysisContext {
        let ctx = AnalysisContext()
        for (tag, strings) in v.tagged where !strings.isEmpty { ctx.contextualStrings[tag] = strings }
        return ctx
    }

    private func start(owner id: UUID, current: String, vocab v: DictationVocab, apply fn: @escaping (String) -> Void) async {
        owner = id
        phase = .preparing(0)
        guard await Self.authorize() else { phase = .denied; return }
        UMSpeechLM.prepareIfNeeded()

        var hints: Set<DictationTranscriber.ContentHint> = [.shortForm]
        if UMSpeechLM.isReady { hints.insert(.customizedLanguage(modelConfiguration: UMSpeechLM.configuration)) }
        let transcriber = DictationTranscriber(locale: UMSpeechLM.locale, contentHints: hints,
                                               transcriptionOptions: [.punctuation],
                                               reportingOptions: [.volatileResults, .frequentFinalization],
                                               attributeOptions: [])
        do {
            if await AssetInventory.status(forModules: [transcriber]) != .installed,
               let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                let progress = request.progress
                let poll = Task { @MainActor in
                    while !Task.isCancelled {
                        if case .preparing = self.phase { self.phase = .preparing(progress.fractionCompleted) }
                        try? await Task.sleep(for: .milliseconds(200))
                    }
                }
                defer { poll.cancel() }
                try await request.downloadAndInstall()
            }
            guard owner == id else { return }
            // The custom LM builds on the on-device dictation assets; retry now that they exist.
            UMSpeechLM.prepareIfNeeded()

            UMDictationAudio.active = true
            GameSFX.stopNonImportant()
            GameMusic.applyVolume()
            guard await UMAudioSession.beginRecording() else { throw CocoaError(.featureUnsupported) }

            let engine = AVAudioEngine()
            let natural = engine.inputNode.outputFormat(forBus: 0)
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: natural)
            else { throw CocoaError(.featureUnsupported) }
            let (stream, cont) = AsyncStream<AnalyzerInput>.makeStream()
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            try await analyzer.setContext(Self.context(v))
            try await analyzer.prepareToAnalyze(in: format)
            try await analyzer.start(inputSequence: stream)
            try Self.installTap(engine: engine, to: format, cont: cont)
            engine.prepare()
            try engine.start()

            self.engine = engine
            self.analyzer = analyzer
            self.input = cont
            self.vocab = v
            self.base = current.isEmpty || current.hasSuffix(" ") ? current : current + " "
            self.finalized = ""
            self.volatile = ""
            self.apply = fn
            self.stopping = false
            self.startedAt = Date()
            self.lastChange = Date()
            phase = .recording
            Self.haptic(.medium)

            resultsTask = Task { @MainActor in
                do {
                    for try await r in transcriber.results {
                        let text = String(r.text.characters)
                        if r.isFinal { self.finalized += text; self.volatile = "" } else { self.volatile = text }
                        self.lastChange = Date()
                        self.push()
                    }
                } catch {
                    UMDiag.log("dictation", "results error: \(error.localizedDescription)")
                }
            }
            watchdog = Task { @MainActor in
                while !Task.isCancelled, self.phase == .recording {
                    try? await Task.sleep(for: .milliseconds(250))
                    let now = Date()
                    let spoke = !(self.finalized + self.volatile).trimmingCharacters(in: .whitespaces).isEmpty
                    let quiet = now.timeIntervalSince(self.lastChange)
                    if now.timeIntervalSince(self.startedAt) >= Self.maxSeconds
                        || quiet >= (spoke ? Self.silenceAfterSpeech : Self.silenceBeforeSpeech) {
                        self.stop()
                    }
                }
            }
        } catch {
            UMDiag.log("dictation", "start failed: \(error.localizedDescription)")
            await teardown()
            phase = .idle
            owner = nil
        }
    }

    private func push() {
        let spoken = (finalized + volatile).trimmingCharacters(in: .whitespaces)
        guard let apply else { return }
        let fixed = DictationFixer.fix(spoken, players: vocab.players, roles: vocab.roles)
        apply(base + fixed)
    }

    func stop() {
        guard !stopping, owner != nil else { return }
        stopping = true
        watchdog?.cancel()
        Task { @MainActor in
            engine?.inputNode.removeTap(onBus: 0)
            engine?.stop()
            input?.finish()
            if let analyzer { try? await analyzer.finalizeAndFinishThroughEndOfInput() }
            _ = await resultsTask?.value
            push()
            await teardown()
            Self.haptic(.light)
            phase = .idle
            owner = nil
            stopping = false
        }
    }

    private func teardown() async {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        input?.finish()
        if let analyzer { await analyzer.cancelAndFinishNow() }
        resultsTask?.cancel()
        engine = nil; analyzer = nil; input = nil; resultsTask = nil; watchdog = nil; apply = nil
        if UMDictationAudio.active {
            UMDictationAudio.active = false
            UMAudioSession.endRecording()
            GameMusic.applyVolume()
        }
    }

    private static func authorize() async -> Bool {
        let mic = await AVAudioApplication.requestRecordPermission()
        guard mic else { return false }
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .authorized { return true }
        if status != .notDetermined { return false }
        return await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
    }

    /// The tap runs on the audio render thread; convert to the analyzer's format there.
    nonisolated private static func installTap(engine: AVAudioEngine, to format: AVAudioFormat,
                                               cont: AsyncStream<AnalyzerInput>.Continuation) throws {
        let node = engine.inputNode
        let natural = node.outputFormat(forBus: 0)
        let converter = natural == format ? nil : AVAudioConverter(from: natural, to: format)
        node.installTap(onBus: 0, bufferSize: 4096, format: natural) { buffer, _ in
            guard let converter else { cont.yield(AnalyzerInput(buffer: buffer)); return }
            let ratio = format.sampleRate / natural.sampleRate
            let cap = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
            guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: cap) else { return }
            var fed = false
            var err: NSError?
            converter.convert(to: out, error: &err) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true
                status.pointee = .haveData
                return buffer
            }
            if err == nil, out.frameLength > 0 { cont.yield(AnalyzerInput(buffer: out)) }
        }
    }

    private static func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: style).impactOccurred()
        #endif
    }
}

// MARK: - UI

/// Mic toggle for a chat composer. Streams into `text`; never sends.
struct UMMicButton: View {
    @Binding var text: String
    var maxLength: Int
    var vocab: () -> DictationVocab
    var size: CGFloat = 32
    var glass = true

    @State private var id = UUID()
    @State private var showDenied = false
    @AppStorage(UMSpeechLM.enabledKey) private var enabled = false
    private var dictation: UMDictation { UMDictation.shared }
    private var mine: Bool { dictation.owner == id }

    var body: some View {
        if enabled { content }
    }

    private var content: some View {
        Button {
            dictation.toggle(owner: id, current: text, vocab: vocab()) { new in
                text = String(new.prefix(maxLength))
            }
        } label: {
            ZStack {
                if mine, case .preparing(let p) = dictation.phase {
                    ProgressView(value: max(p, 0.02)).progressViewStyle(.circular).controlSize(.small)
                } else {
                    let rec = mine && dictation.isRecording
                    if glass {
                        Image(systemName: rec ? "mic.fill" : "mic")
                            .symbolEffect(.pulse, isActive: rec)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(rec ? Color.red : Color.white.opacity(0.85))
                    } else {
                        // Plain composers (DMs, public chat): send-button size; white idle, red while recording.
                        Image(systemName: rec ? "mic.circle.fill" : "mic.circle")
                            .symbolEffect(.pulse, isActive: rec)
                            .font(.title2)
                            .foregroundStyle(rec ? AnyShapeStyle(Color.red) : AnyShapeStyle(Color.white.opacity(0.9)))
                    }
                }
            }
            .frame(width: size, height: size)
            .background {
                if glass { Color.clear.glassEffect(.regular.interactive(true), in: Capsule()) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mine && dictation.isRecording ? "Stop dictation" : "Dictate")
        .onChange(of: dictation.phase) { _, p in
            if p == .denied, mine { showDenied = true }
        }
        .onChange(of: vocab()) { _, v in if mine { dictation.updateVocab(v) } }
        .onDisappear { if mine { dictation.stop() } }
        .alert("Microphone access needed", isPresented: $showDenied) {
            Button("Open Settings") {
                dictation.clearDenied()
                #if canImport(UIKit)
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                #endif
            }
            Button("Cancel", role: .cancel) { dictation.clearDenied() }
        } message: {
            Text("Allow Microphone and Speech Recognition for UltiMafia in Settings to dictate chat messages.")
        }
    }
}

/// "Listening" strip shown above a composer while that screen is dictating.
struct UMDictationBanner: View {
    private var dictation: UMDictation { UMDictation.shared }

    var body: some View {
        if dictation.isRecording {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let left = max(0, Int(UMDictation.maxSeconds - ctx.date.timeIntervalSince(dictation.startedAt)))
                HStack(spacing: 6) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                        .symbolEffect(.pulse)
                    Text("Listening… tap the mic to stop")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(left)s").font(.caption.monospacedDigit()).foregroundStyle(UMTheme.muted)
                }
                .padding(.horizontal, 14).padding(.vertical, 5)
                .foregroundStyle(.white)
                .background(Color.red.opacity(0.18))
            }
            .transition(.opacity)
        }
    }
}
