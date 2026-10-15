import Foundation

nonisolated enum UMFeatureFlags {
    /// APNs remote push for DMs. OFF for now: re-enable near release by flipping this to true AND
    /// re-adding `aps-environment` (development) to Ultimafia/Ultimafia-iOS.entitlements.
    /// While false the app never registers for remote notifications and never POSTs/DELETEs
    /// /api/user/push/apns. Local in-app DM alerts are unaffected.
    static let pushNotificationsEnabled = false
}
