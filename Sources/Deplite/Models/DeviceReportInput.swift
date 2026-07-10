import Foundation

/// Device-state report sent by `DepliteAgent.deploy.report`. Absent fields are
/// omitted from the request body.
public struct DeviceReportInput: Sendable, Equatable {
    public let applicationId: String
    public let currentVersion: String?
    public let currentReleaseId: String?
    public let currentSequence: Int64?
    public let state: AppDeviceState?
    public let error: String?

    public init(
        applicationId: String,
        currentVersion: String? = nil,
        currentReleaseId: String? = nil,
        currentSequence: Int64? = nil,
        state: AppDeviceState? = nil,
        error: String? = nil
    ) {
        self.applicationId = applicationId
        self.currentVersion = currentVersion
        self.currentReleaseId = currentReleaseId
        self.currentSequence = currentSequence
        self.state = state
        self.error = error
    }
}
