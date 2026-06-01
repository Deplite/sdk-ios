import Foundation

public enum JobStatus: String, Codable, Sendable {
    case running, success, failed, timeout, rejected
}

/// Final outcome of a job run. Use the static factories.
public struct JobResult: Sendable, Equatable {
    public let status: JobStatus
    public let exitCode: Int?
    public let errorMessage: String?
    public let output: JSONValue?
    public let rejection: Rejection?

    public struct Rejection: Sendable, Equatable {
        public let reason: String
        public let limitType: String?
        public let retryAfterSeconds: Int?
        public let bypassedLimits: [String]

        public init(reason: String, limitType: String? = nil, retryAfterSeconds: Int? = nil, bypassedLimits: [String] = []) {
            self.reason = reason
            self.limitType = limitType
            self.retryAfterSeconds = retryAfterSeconds
            self.bypassedLimits = bypassedLimits
        }
    }

    internal init(status: JobStatus, exitCode: Int? = nil, errorMessage: String? = nil, output: JSONValue? = nil, rejection: Rejection? = nil) {
        self.status = status
        self.exitCode = exitCode
        self.errorMessage = errorMessage
        self.output = output
        self.rejection = rejection
    }

    public static func running() -> JobResult { JobResult(status: .running) }
    public static func success(exitCode: Int = 0, output: JSONValue? = nil) -> JobResult {
        JobResult(status: .success, exitCode: exitCode, output: output)
    }
    public static func failed(exitCode: Int? = nil, errorMessage: String? = nil) -> JobResult {
        JobResult(status: .failed, exitCode: exitCode, errorMessage: errorMessage)
    }
    public static func timeout(errorMessage: String? = nil) -> JobResult {
        JobResult(status: .timeout, errorMessage: errorMessage)
    }
    public static func rejected(_ rejection: Rejection) -> JobResult {
        JobResult(status: .rejected, rejection: rejection)
    }
}
