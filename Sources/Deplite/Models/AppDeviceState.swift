import Foundation

/// Reported lifecycle state of an app on this device.
public enum AppDeviceState: String, Codable, Sendable, Equatable {
    case idle
    case pending
    case updating
    case failed
}
