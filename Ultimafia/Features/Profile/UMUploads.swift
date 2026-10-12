import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import ImageIO
import AVFoundation

// Native versions of the site's upload flows (react_main AvatarUpload / BannerUpload / HiddenUpload /
// Form emoteUpload+stickerUpload / DeathSoundUpload, routes/user.js + routes/family.js).
// The site crops client-side on a canvas and posts a PNG; the server always re-validates and re-encodes
// with sharp (resize/WebP), so we crop + downscale + compress here and post the same multipart field.

nonisolated struct UMUploadSpec: Sendable {
    var title: String
    /// API path under /api/.
    var path: String
    /// Multipart file field ("image" for images, "file" for emotes/stickers/death sound).
    var field: String
    /// Crop aspect (w/h). nil = no crop (backgrounds / stickers keep their shape).
    var aspect: CGFloat?
    /// Exact output size after crop; nil = fit inside `maxEdge`.
    var output: CGSize?
    var maxEdge: CGFloat = 2560
    var maxBytes: Int
    /// Animated GIF/WebP may be uploaded as-is when allowed (site's keepAnimation).
    var animatedAllowed = false
    var maxAnimatedBytes = 0
    var maxAnimatedFrame: CGSize?
    /// Emotes/stickers: file body is a `data:<mime>;base64,...` string (site sends FileReader data URL).
    var dataURL = false
    var fields: [String: String] = [:]

    static func avatar(animated: Bool) -> Self {
        .init(title: "Avatar", path: "user/avatar", field: "image", aspect: 1, output: CGSize(width: 300, height: 300),
              maxBytes: 1 * 1024 * 1024, animatedAllowed: animated, maxAnimatedBytes: 25 * 1024 * 1024,
              maxAnimatedFrame: CGSize(width: 1024, height: 1024))
    }
    static func banner(animated: Bool) -> Self {
        .init(title: "Profile Banner", path: "user/banner", field: "image", aspect: 3, output: CGSize(width: 900, height: 300),
              maxBytes: 20 * 1024 * 1024, animatedAllowed: animated, maxAnimatedBytes: 20 * 1024 * 1024,
              maxAnimatedFrame: CGSize(width: 1800, height: 600))
    }
    static let forumBanner = Self(title: "Forum Banner", path: "user/forumBanner", field: "image", aspect: 5,
                                  output: CGSize(width: 500, height: 100), maxBytes: 2 * 1024 * 1024)
    static let profileBackground = Self(title: "Profile Background", path: "user/profileBackground", field: "image",
                                        aspect: nil, output: nil, maxBytes: 5 * 1024 * 1024)
    static func familyAvatar(animated: Bool) -> Self {
        .init(title: "Family Avatar", path: "family/avatar", field: "image", aspect: 1, output: CGSize(width: 300, height: 300),
              maxBytes: 1 * 1024 * 1024, animatedAllowed: animated, maxAnimatedBytes: 25 * 1024 * 1024)
    }
    static func familyBanner(id: String, animated: Bool) -> Self {
        .init(title: "Family Banner", path: "family/\(id)/banner", field: "image", aspect: 3, output: CGSize(width: 900, height: 300),
              maxBytes: 5 * 1024 * 1024, animatedAllowed: animated, maxAnimatedBytes: 20 * 1024 * 1024)
    }
    static func familyBackground(id: String) -> Self {
        .init(title: "Family Background", path: "family/\(id)/background", field: "image", aspect: nil, output: nil,
              maxBytes: 5 * 1024 * 1024)
    }
    /// Server: 2 MB request file (the data URL text), sharp resizes to fit 30×30, animation kept.
    static func emote(name: String) -> Self {
        .init(title: "Custom Emote", path: "user/customEmote/create", field: "file", aspect: 1, output: CGSize(width: 90, height: 90),
              maxBytes: 1_400_000, animatedAllowed: true, maxAnimatedBytes: 1_400_000, dataURL: true, fields: ["emoteText": name])
    }
    /// Server: GIF/PNG/JPEG/WebP, ≤10 MB, ≤512×512, stored as-is.
    static func sticker(name: String) -> Self {
        .init(title: "Custom Sticker", path: "user/customSticker/create", field: "file", aspect: nil, output: nil, maxEdge: 512,
              maxBytes: 7 * 1024 * 1024, animatedAllowed: true, maxAnimatedBytes: 7 * 1024 * 1024,
              maxAnimatedFrame: CGSize(width: 512, height: 512), dataURL: true, fields: ["stickerText": name])
    }
}

/// Site upload URLs (/uploads/...) to purge from every app cache after a confirmed upload/removal.
enum UMUploadURLs {
    private static func u(_ name: String) -> URL { URL(string: "https://ultimafia.com/uploads/\(name)")! }
    static func avatar(_ uid: String) -> [URL] { [u("\(uid)_avatar.webp")] }
    static func banner(_ uid: String) -> [URL] { ["webp", "gif", "png", "jpg"].map { u("\(uid)_banner.\($0)") } }
    static func forumBanner(_ uid: String) -> [URL] { [u("\(uid)_forumBanner.webp")] }
    static func profileBackground(_ uid: String) -> [URL] { [u("\(uid)_profileBackground.webp")] }
    static func familyAvatar(_ fid: String) -> [URL] { [u("\(fid)_family_avatar.webp")] }
    static func familyBanner(_ fid: String) -> [URL] { ["webp", "gif", "png", "jpg"].map { u("\(fid)_family_banner.\($0)") } }
    static func familyBackground(_ fid: String) -> [URL] { [u("\(fid)_familyBackground.webp")] }
}

/// Image types the site's pickers accept for these uploads (accept="image/*"; server: GIF/PNG/JPEG/WebP).
let umUploadImageTypes: [UTType] = [.png, .jpeg, .webP, .gif, .heic]

nonisolated enum UMImageEncode {
    struct Info { var isAnimated: Bool; var utType: String; var frame: CGSize }

    static func inspect(_ data: Data) -> Info? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let type = CGImageSourceGetType(src) as String? ?? ""
        let count = CGImageSourceGetCount(src)
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
        let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        let animated = count > 1 && (type == UTType.gif.identifier || type == UTType.webP.identifier)
        return Info(isAnimated: animated, utType: type, frame: CGSize(width: w, height: h))
    }

    /// Downscale to fit `maxEdge` (no crop) with pixel scale 1.
    static func fit(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let s = min(1, maxEdge / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * s).rounded(), height: (image.size.height * s).rounded())
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    /// PNG when it fits (site exports PNG), else JPEG stepping quality, then shrinking.
    static func encode(_ image: UIImage, maxBytes: Int) -> (Data, String, String)? {
        if let png = image.pngData(), png.count <= maxBytes { return (png, "image/png", "png") }
        var img = image
        for _ in 0..<6 {
            for q in stride(from: 0.9, through: 0.4, by: -0.1) {
                if let jpg = img.jpegData(compressionQuality: q), jpg.count <= maxBytes { return (jpg, "image/jpeg", "jpg") }
            }
            img = fit(img, maxEdge: max(img.size.width, img.size.height) * 0.75)
        }
        return nil
    }

    static func mime(for utType: String) -> (String, String) {
        switch utType {
        case UTType.gif.identifier: return ("image/gif", "gif")
        case UTType.webP.identifier: return ("image/webp", "webp")
        case UTType.png.identifier: return ("image/png", "png")
        default: return ("image/jpeg", "jpg")
        }
    }
}

/// "Choose Photo" / "Choose File" menu → (animated choice) → crop → resize/compress → multipart POST.
struct UMImageUploadButton: View {
    let spec: UMUploadSpec
    var label: String
    var disabled = false
    /// Cached URLs replaced by this upload; purged only after the server confirms success.
    var purge: [URL] = []
    var onUploaded: () async -> Void

    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var cropImage: UMCropItem?
    @State private var animatedData: Data?
    @State private var progress: Double?
    @State private var error: String?
    @State private var done: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Menu {
                Button { showPhotos = true } label: { Label("Choose Photo", systemImage: "photo.on.rectangle") }
                Button { showFiles = true } label: { Label("Choose File", systemImage: "folder") }
            } label: {
                Label(label, systemImage: "square.and.arrow.up")
            }
            .disabled(disabled || progress != nil)
            if let progress {
                ProgressView(value: progress) { Text(progress >= 1 ? "Processing…" : "Uploading…").font(.caption) }
                    .tint(UMTheme.blood)
            }
        }
        .photosPicker(isPresented: $showPhotos, selection: $photoItem, matching: .images)
        .fileImporter(isPresented: $showFiles, allowedContentTypes: umUploadImageTypes) { result in
            switch result {
            case .success(let url):
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) { handle(data) } else { error = "Couldn't read that file." }
            case .failure(let e): error = e.localizedDescription
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { handle(data) } else { error = "Couldn't load that photo." }
            }
        }
        .confirmationDialog("Animated image", isPresented: Binding(get: { animatedData != nil }, set: { if !$0 { animatedData = nil } }), titleVisibility: .visible) {
            Button("Keep Animation (upload as-is)") {
                if let d = animatedData { Task { await uploadRaw(d) } }
                animatedData = nil
            }
            Button(spec.aspect == nil ? "Use Still Image" : "Crop (still image)") {
                if let d = animatedData { prepareStill(d) }
                animatedData = nil
            }
            Button("Cancel", role: .cancel) { animatedData = nil }
        } message: {
            Text("Keeping the animation uploads the original file. Cropping makes a still image.")
        }
        .fullScreenCover(item: $cropImage) { item in
            UMCropSheet(image: item.image, aspect: spec.aspect ?? 1, title: spec.title) { cropped in
                cropImage = nil
                if let cropped { Task { await uploadStill(cropped, alreadySized: false) } }
            }
        }
        .alert("Upload failed", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
        .alert("Uploaded", isPresented: Binding(get: { done != nil }, set: { if !$0 { done = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(done ?? "") }
    }

    private func handle(_ data: Data) {
        guard let info = UMImageEncode.inspect(data) else { error = "That file isn't a supported image."; return }
        if info.isAnimated && spec.animatedAllowed {
            if data.count > spec.maxAnimatedBytes {
                error = "Animated file is too large (max \(spec.maxAnimatedBytes / 1_048_576) MB). You can still upload a still image."
                prepareStill(data)
                return
            }
            if let maxF = spec.maxAnimatedFrame, info.frame.width > maxF.width || info.frame.height > maxF.height {
                error = "Animated frames must be at most \(Int(maxF.width))×\(Int(maxF.height)). You can still upload a still image."
                prepareStill(data)
                return
            }
            animatedData = data
            return
        }
        prepareStill(data)
    }

    private func prepareStill(_ data: Data) {
        guard let img = UIImage(data: data) else { error = "Couldn't read that image."; return }
        if spec.aspect != nil {
            cropImage = UMCropItem(image: img)
        } else {
            Task { await uploadStill(img, alreadySized: false) }
        }
    }

    private func uploadStill(_ image: UIImage, alreadySized: Bool) async {
        let sized: UIImage
        if let out = spec.output {
            let fmt = UIGraphicsImageRendererFormat.default()
            fmt.scale = 1
            sized = UIGraphicsImageRenderer(size: out, format: fmt).image { _ in image.draw(in: CGRect(origin: .zero, size: out)) }
        } else {
            sized = UMImageEncode.fit(image, maxEdge: spec.maxEdge)
        }
        guard let (data, mime, ext) = UMImageEncode.encode(sized, maxBytes: spec.maxBytes) else {
            error = "Couldn't compress the image under \(spec.maxBytes / 1_048_576) MB."
            return
        }
        await send(data, mime: mime, ext: ext)
    }

    private func uploadRaw(_ data: Data) async {
        let info = UMImageEncode.inspect(data)
        let (mime, ext) = UMImageEncode.mime(for: info?.utType ?? "")
        await send(data, mime: mime, ext: ext)
    }

    private func send(_ data: Data, mime: String, ext: String) async {
        var body = data
        var sendMime = mime
        if spec.dataURL {
            body = Data("data:\(mime);base64,\(data.base64EncodedString())".utf8)
            sendMime = "application/octet-stream"
        }
        progress = 0
        defer { progress = nil }
        do {
            try await APIClient.shared.upload(spec.path, fields: spec.fields, fileField: spec.field,
                                              filename: "upload.\(ext)", mimeType: sendMime, data: body) { p in
                progress = p
            }
            if !purge.isEmpty { await UMImageCache.shared.purge(purge) }
            done = "\(spec.title) uploaded."
            await onUploaded()
            Task.detached(priority: .utility) { await UMProfileCache.refreshActiveAccount() }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct UMCropItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Pinch/pan crop frame with a fixed aspect, like the site's AvatarUpload/BannerUpload viewports.
struct UMCropSheet: View {
    let image: UIImage
    let aspect: CGFloat
    let title: String
    var onDone: (UIImage?) -> Void

    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let frameW = min(geo.size.width - 32, (geo.size.height - 80) * aspect)
                let frameH = frameW / aspect
                let base = max(frameW / image.size.width, frameH / image.size.height)
                let scale = base * zoom
                let shown = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                ZStack {
                    Color.black
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: shown.width, height: shown.height)
                        .offset(offset)
                    // Dim outside the crop frame.
                    Rectangle()
                        .fill(Color.black.opacity(0.55))
                        .mask {
                            Rectangle()
                                .overlay { Rectangle().frame(width: frameW, height: frameH).blendMode(.destinationOut) }
                                .compositingGroup()
                        }
                        .allowsHitTesting(false)
                    Rectangle()
                        .stroke(Color.white, lineWidth: 1.5)
                        .frame(width: frameW, height: frameH)
                        .allowsHitTesting(false)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(
                    SimultaneousGesture(
                        DragGesture()
                            .onChanged { v in
                                offset = clamp(CGSize(width: lastOffset.width + v.translation.width, height: lastOffset.height + v.translation.height),
                                               shown: shown, frame: CGSize(width: frameW, height: frameH))
                            }
                            .onEnded { _ in lastOffset = offset },
                        MagnifyGesture()
                            .onChanged { v in zoom = min(max(lastZoom * v.magnification, 1), 8) }
                            .onEnded { _ in
                                lastZoom = zoom
                                let s = CGSize(width: image.size.width * base * zoom, height: image.size.height * base * zoom)
                                offset = clamp(offset, shown: s, frame: CGSize(width: frameW, height: frameH))
                                lastOffset = offset
                            }
                    )
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onDone(nil) } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Upload") { onDone(render(frame: CGSize(width: frameW, height: frameH), scale: scale)) }
                    }
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Crop \(title)")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func clamp(_ o: CGSize, shown: CGSize, frame: CGSize) -> CGSize {
        let mx = max(0, (shown.width - frame.width) / 2), my = max(0, (shown.height - frame.height) / 2)
        return CGSize(width: min(max(o.width, -mx), mx), height: min(max(o.height, -my), my))
    }

    /// Maps the frame back to image points and renders that region at source resolution.
    private func render(frame: CGSize, scale: CGFloat) -> UIImage {
        let x0 = (image.size.width * scale / 2 - offset.width - frame.width / 2) / scale
        let y0 = (image.size.height * scale / 2 - offset.height - frame.height / 2) / scale
        let crop = CGSize(width: frame.width / scale, height: frame.height / scale)
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        let outW = min(crop.width * image.scale, 2400)
        let k = outW / crop.width
        let size = CGSize(width: outW.rounded(), height: (crop.height * k).rounded())
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            image.draw(in: CGRect(x: -x0 * k, y: -y0 * k, width: image.size.width * k, height: image.size.height * k))
        }
    }
}

// MARK: - Death sound

/// Site: DeathSoundUpload picks mp3/ogg/wav (≤10 MB), trims to ≤5 s client-side and posts a WAV
/// (field "file" + "durationSeconds") to POST user/deathSound. Server re-checks ext/size/duration.
struct UMDeathSoundUploadButton: View {
    var onUploaded: () async -> Void
    @State private var showFiles = false
    @State private var trimItem: UMTrimItem?
    @State private var progress: Double?
    @State private var error: String?
    @State private var done = false

    nonisolated static let maxSeconds = 5.0
    static let maxSourceBytes = 10 * 1024 * 1024
    static let types: [UTType] = [.mp3, .wav, UTType("org.xiph.ogg") ?? .audio, UTType("public.ogg-audio") ?? .audio, UTType("org.webmproject.webm") ?? .audio, .mpeg4Audio, .audio]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { showFiles = true } label: { Label("Choose Sound File", systemImage: "waveform") }
                .disabled(progress != nil)
            if let progress {
                ProgressView(value: progress) { Text("Uploading…").font(.caption) }.tint(UMTheme.blood)
            }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: Self.types) { result in
            switch result {
            case .success(let url):
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else { error = "Couldn't read that file."; return }
                guard data.count <= Self.maxSourceBytes else { error = "Death sound must be less than 10 MB."; return }
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("um-death-src-\(UUID().uuidString).\(url.pathExtension)")
                do {
                    try data.write(to: tmp)
                    let file = try AVAudioFile(forReading: tmp)
                    let dur = Double(file.length) / file.processingFormat.sampleRate
                    trimItem = UMTrimItem(url: tmp, duration: dur)
                } catch {
                    self.error = "This audio format can't be decoded on iPhone (try MP3 or WAV)."
                }
            case .failure(let e): error = e.localizedDescription
            }
        }
        .sheet(item: $trimItem) { item in
            UMTrimSheet(item: item) { start, length in
                trimItem = nil
                if let start, let length { Task { await upload(item.url, start: start, length: length) } }
            }
        }
        .alert("Upload failed", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
        .alert("Death sound uploaded", isPresented: $done) { Button("OK", role: .cancel) {} }
    }

    private func upload(_ url: URL, start: Double, length: Double) async {
        do {
            let wav = try Self.exportWAV(url, start: start, length: length)
            progress = 0
            defer { progress = nil }
            try await APIClient.shared.upload("user/deathSound", fields: ["durationSeconds": String(format: "%.2f", length)],
                                              fileField: "file", filename: "deathSound.wav", mimeType: "audio/wav", data: wav) { p in
                progress = p
            }
            done = true
            await onUploaded()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 16-bit PCM WAV of [start, start+length), like the site's trimmed WAV export.
    nonisolated static func exportWAV(_ url: URL, start: Double, length: Double) throws -> Data {
        let file = try AVAudioFile(forReading: url)
        let fmt = file.processingFormat
        let sr = fmt.sampleRate
        let startFrame = AVAudioFramePosition(max(0, start) * sr)
        let frames = AVAudioFrameCount(min(length, maxSeconds) * sr)
        file.framePosition = min(startFrame, file.length)
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames) else { throw UMError.message("Couldn't read audio.") }
        try file.read(into: buf, frameCount: frames)
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("um-death-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sr, AVNumberOfChannelsKey: fmt.channelCount,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ]
        do {
            let w = try AVAudioFile(forWriting: out, settings: settings, commonFormat: fmt.commonFormat, interleaved: fmt.isInterleaved)
            try w.write(from: buf)
        }
        defer { try? FileManager.default.removeItem(at: out) }
        return try Data(contentsOf: out)
    }
}

struct UMTrimItem: Identifiable {
    let id = UUID()
    let url: URL
    let duration: Double
}

private struct UMTrimSheet: View {
    let item: UMTrimItem
    var onDone: (Double?, Double?) -> Void
    @State private var start = 0.0
    @State private var player: AVAudioPlayer?

    private var length: Double { min(UMDeathSoundUploadButton.maxSeconds, max(0, item.duration - start)) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Clip length", value: String(format: "%.1f s", item.duration))
                    if item.duration > UMDeathSoundUploadButton.maxSeconds {
                        VStack(alignment: .leading) {
                            Text("Start at \(String(format: "%.1f", start)) s")
                            Slider(value: $start, in: 0...max(0, item.duration - 0.5), step: 0.1).tint(UMTheme.blood)
                        }
                    }
                    LabeledContent("Uploads", value: String(format: "%.1f s – %.1f s", start, start + length))
                    Button("Preview") { preview() }
                } footer: {
                    Text("Death sounds can be at most 5 seconds. Played to everyone in the lobby when you die.")
                }
            }
            .navigationTitle("Trim Death Sound")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { player?.stop(); onDone(nil, nil) } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Upload") { player?.stop(); onDone(start, length) }.disabled(length <= 0.05)
                }
            }
        }
    }

    private func preview() {
        guard let p = try? AVAudioPlayer(contentsOf: item.url) else { return }
        player = p
        p.currentTime = start
        p.play()
        let stopAt = length
        Task {
            try? await Task.sleep(for: .seconds(stopAt))
            if player === p { p.stop() }
        }
    }
}
