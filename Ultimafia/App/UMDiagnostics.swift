import Foundation
import os
import QuartzCore

/// On-device diagnostics: os.Logger + a rolling text file in Application Support/UMDiagnostics
/// (not UMCache, so Clear Cached Media keeps it). ~2 MB current file + one rotated file.
/// Everything is cheap and thread-safe; file writes happen on a private serial queue.
nonisolated enum UMDiag {
    static let logger = Logger(subsystem: "VCCCLLC.Ultimafia", category: "diag")
    static let signposter = OSSignposter(subsystem: "VCCCLLC.Ultimafia", category: "game")
    private static let queue = DispatchQueue(label: "com.ultimafia.diag", qos: .utility)
    private static let maxBytes: UInt64 = 2 << 20
    private nonisolated(unsafe) static var handle: FileHandle?
    private static let stamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = .current
        return f
    }()

    static var directory: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UMDiagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static var logFile: URL { directory.appendingPathComponent("diagnostics.log") }
    static var rotatedFile: URL { directory.appendingPathComponent("diagnostics.1.log") }

    static func log(_ category: String, _ message: String) {
        let now = Date()
        logger.log("[\(category, privacy: .public)] \(message, privacy: .public)")
        queue.async {
            let line = "\(stamp.string(from: now)) [\(category)] \(message)\n"
            write(Data(line.utf8))
        }
    }

    private static func write(_ data: Data) {
        if handle == nil {
            if !FileManager.default.fileExists(atPath: logFile.path) {
                FileManager.default.createFile(atPath: logFile.path, contents: nil)
            }
            handle = try? FileHandle(forWritingTo: logFile)
            _ = try? handle?.seekToEnd()
        }
        guard let handle else { return }
        try? handle.write(contentsOf: data)
        if let size = try? handle.offset(), size > maxBytes {
            try? handle.close()
            self.handle = nil
            try? FileManager.default.removeItem(at: rotatedFile)
            try? FileManager.default.moveItem(at: logFile, to: rotatedFile)
        }
    }

    /// Both files, oldest first (for viewing / sharing).
    static func readAll(completion: @escaping @Sendable (String) -> Void) {
        queue.async {
            try? handle?.synchronize()
            let old = (try? String(contentsOf: rotatedFile, encoding: .utf8)) ?? ""
            let cur = (try? String(contentsOf: logFile, encoding: .utf8)) ?? ""
            completion(old + cur)
        }
    }

    /// One shareable file with both parts.
    static func exportFile(completion: @escaping @Sendable (URL?) -> Void) {
        readAll { text in
            let out = FileManager.default.temporaryDirectory.appendingPathComponent("UltiMafia-diagnostics.log")
            do { try text.write(to: out, atomically: true, encoding: .utf8); completion(out) } catch { completion(nil) }
        }
    }

    static func clear(completion: @escaping @Sendable () -> Void = {}) {
        queue.async {
            try? handle?.close()
            handle = nil
            try? FileManager.default.removeItem(at: logFile)
            try? FileManager.default.removeItem(at: rotatedFile)
            completion()
        }
    }

    // MARK: message received -> rendered

    private nonisolated(unsafe) static var received: [String: CFTimeInterval] = [:]
    private static let lock = NSLock()

    static func messageReceived(_ id: String) {
        lock.lock(); received[id] = CACurrentMediaTime(); if received.count > 500 { received.removeAll() }; lock.unlock()
    }

    static func messageRendered(_ id: String) {
        lock.lock(); let t = received.removeValue(forKey: id); lock.unlock()
        guard let t else { return }
        let ms = Int((CACurrentMediaTime() - t) * 1000)
        if ms >= 100 { log("render", "message \(id) shown \(ms)ms after arrival") }
    }

    // MARK: main-thread watchdog

    private nonisolated(unsafe) static var watchdogStarted = false

    /// Logs every main-thread stall over 250 ms with its duration.
    static func startWatchdog() {
        guard !watchdogStarted else { return }
        watchdogStarted = true
        let thread = Thread {
            while true {
                let sem = DispatchSemaphore(value: 0)
                let t0 = CACurrentMediaTime()
                DispatchQueue.main.async { sem.signal() }
                if sem.wait(timeout: .now() + 0.25) == .timedOut {
                    sem.wait()
                    let ms = Int((CACurrentMediaTime() - t0) * 1000)
                    log("hang", "main thread blocked \(ms)ms")
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        thread.name = "UMDiag.watchdog"
        thread.qualityOfService = .utility
        thread.start()
    }
}
