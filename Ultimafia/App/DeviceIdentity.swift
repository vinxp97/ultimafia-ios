import Foundation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Local-only install/device identity and the users who signed in on this device.
/// Nothing here is sent to any server (that would need an App Store privacy disclosure update).
enum DeviceIdentity {
    private static let service = "VCCCLLC.Ultimafia.device"
    private static let signInsKey = "um.device.signIns"

    struct SignIn: Codable, Hashable {
        var userId: String
        var firstSignIn: Date
        var lastSignIn: Date
    }

    /// Generated once and kept in the Keychain, which usually survives app reinstall.
    static var installId: String {
        migrateLocalOnlyOnce()
        if let data = UMKeychain.get(service: service, account: "installId"),
           let id = String(data: data, encoding: .utf8), !id.isEmpty { return id }
        let id = UUID().uuidString
        UMKeychain.set(Data(id.utf8), service: service, account: "installId", synced: false)
        return id
    }

    /// Re-store an install ID that predates the sync change as explicitly device-only.
    private static func migrateLocalOnlyOnce() {
        let key = "um.device.installIdLocalOnly.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        if let data = UMKeychain.get(service: service, account: "installId") {
            UMKeychain.set(data, service: service, account: "installId", synced: false)
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    #if os(macOS)
    /// Mac has no identifierForVendor: a per-install UUID kept in defaults.
    static var vendorId: String? {
        let key = "um.device.macVendorId"
        if let v = UserDefaults.standard.string(forKey: key) { return v }
        let v = UUID().uuidString
        UserDefaults.standard.set(v, forKey: key)
        return v
    }
    #else
    static var vendorId: String? { UIDevice.current.identifierForVendor?.uuidString }
    #endif

    static var signIns: [SignIn] {
        guard let data = UserDefaults.standard.data(forKey: signInsKey) else { return [] }
        return (try? JSONDecoder().decode([SignIn].self, from: data)) ?? []
    }

    static func recordSignIn(userId: String) {
        var all = signIns
        let now = Date()
        if let i = all.firstIndex(where: { $0.userId == userId }) {
            all[i].lastSignIn = now
        } else {
            all.append(SignIn(userId: userId, firstSignIn: now, lastSignIn: now))
        }
        UserDefaults.standard.set(try? JSONEncoder().encode(all), forKey: signInsKey)
    }
}
