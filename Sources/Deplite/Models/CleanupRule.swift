import Foundation

/// Cleanup policy applied to a file after upload.
public enum CleanupRule: Sendable, Equatable {
    case ttl(seconds: Int64)
    case persistent
    case onJobEnd

    internal var wireValue: String {
        switch self {
        case .ttl: return "ttl"
        case .persistent: return "persistent"
        case .onJobEnd: return "on_job_end"
        }
    }

    internal var ttlSeconds: Int64? {
        if case .ttl(let s) = self { return s }
        return nil
    }
}
